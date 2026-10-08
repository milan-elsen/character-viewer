import AppKit
import Observation
import SwiftUI

/// The database and search engine, loaded once. Also used by App Intents, which may run without any UI.
struct LoadedCatalog: @unchecked Sendable {
    let database: CharacterDatabase
    let engine: SearchEngine
}

enum Catalog {
    struct MissingResource: LocalizedError {
        var errorDescription: String? { "The character database is missing from the app bundle." }
    }

    static let shared: Result<LoadedCatalog, Error> = Result {
        guard let url = Bundle.main.url(forResource: "characters", withExtension: "json") else { throw MissingResource() }
        let database = try CharacterDatabase(contentsOf: url)
        return LoadedCatalog(database: database, engine: SearchEngine(database: database))
    }
}

/// What the sidebar can show.
enum SidebarItem: Hashable {
    case all
    case favorites
    case recents
    case collection(String)
    case block(Int)
    /// Every visible character the opened font file contains.
    case customFont

    var storageString: String {
        switch self {
        case .customFont: return "font"
        case .all: return "all"
        case .favorites: return "favorites"
        case .recents: return "recents"
        case .collection(let id): return "collection:" + id
        case .block(let index): return "block:\(index)"
        }
    }

    init?(storageString: String) {
        switch storageString {
        case "all": self = .all
        case "favorites": self = .favorites
        case "recents": self = .recents
        case "font": return nil   // an opened font is never restored: it lives for one session
        default:
            if storageString.hasPrefix("collection:") {
                self = .collection(String(storageString.dropFirst("collection:".count)))
            } else if storageString.hasPrefix("block:"), let i = Int(storageString.dropFirst("block:".count)) {
                self = .block(i)
            } else {
                return nil
            }
        }
    }
}

struct Toast: Equatable, Identifiable {
    let id = UUID()
    let message: String
}

@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    enum LoadState {
        case loading
        case ready
        case failed(String)
    }

    // MARK: State

    private(set) var loadState: LoadState = .loading
    private(set) var database: CharacterDatabase?
    @ObservationIgnored private var engine: SearchEngine?

    // `@Observable` rewrites stored properties, so the "recompute on change" behavior is written as a computed
    // property over private storage instead of using `didSet`.
    private var storedQuery = ""
    private var storedSidebar: SidebarItem = .all

    /// Search field text. Changing it recomputes `results`.
    var query: String {
        get { storedQuery }
        set {
            guard newValue != storedQuery else { return }
            storedQuery = newValue
            refreshResults()
        }
    }

    var sidebar: SidebarItem {
        get { storedSidebar }
        set {
            guard newValue != storedSidebar else { return }
            storedSidebar = newValue
            UserDefaults.standard.set(newValue.storageString, forKey: SettingsKey.lastSidebar)
            if !storedQuery.isEmpty { query = "" } else { refreshResults() }
        }
    }

    /// Code points shown in the results grid: search hits, or the contents of the selected sidebar item.
    private(set) var results: [UInt32] = []
    var selection: UInt32?

    private(set) var favorites: [UInt32]
    private(set) var recents: [UInt32]
    private(set) var toast: Toast?

    /// A font opened from a file. While set, every glyph is drawn with it (falling back, with a warning, for
    /// characters it lacks).
    private(set) var customFont: LoadedFont?
    /// Shows the "Open Font" file dialog (File menu, toolbar and ⌘O all set this).
    var showFontImporter = false

    let keyboard = KeyboardService()

    // Window plumbing -----------------------------------------------------------------------------------------------
    @ObservationIgnored var openWindow: OpenWindowAction?
    @ObservationIgnored var dismissWindow: DismissWindowAction?
    @ObservationIgnored private(set) var quickLookupVisible = false
    /// Whether the main window is open (reported by `MainWindowTracker`); drives the Dock icon.
    @ObservationIgnored private(set) var mainWindowOpen = false
    @ObservationIgnored private var previousApplication: NSRunningApplication?
    @ObservationIgnored private let hotKey = GlobalHotKey()

    private static let maxRecents = 40

    // MARK: Lifecycle

    private init() {
        let defaults = UserDefaults.standard
        favorites = (defaults.array(forKey: SettingsKey.favorites) as? [Int] ?? []).compactMap { UInt32(exactly: $0) }
        recents = (defaults.array(forKey: SettingsKey.recents) as? [Int] ?? []).compactMap { UInt32(exactly: $0) }
        if let stored = defaults.string(forKey: SettingsKey.lastSidebar), let item = SidebarItem(storageString: stored) {
            storedSidebar = item
        }
    }

    /// Loads the database off the main thread.
    func start() {
        guard database == nil else { return }
        #if DEBUG
        // Lets automated UI tests open a font without driving the file dialog.
        if let path = ProcessInfo.processInfo.environment["TYPECASE_OPEN_FONT"] {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                AppModel.shared.openFont(at: URL(fileURLWithPath: path))
            }
        }
        #endif
        Task.detached(priority: .userInitiated) {
            let result = Catalog.shared
            await MainActor.run { AppModel.shared.finishLoading(result) }
        }
    }

    private func finishLoading(_ result: Result<LoadedCatalog, Error>) {
        switch result {
        case .success(let catalog):
            database = catalog.database
            engine = catalog.engine
            loadState = .ready
            refreshResults()
        case .failure(let error):
            loadState = .failed(error.localizedDescription)
        }
    }

    // MARK: Results

    var isSearching: Bool { !query.isEmpty }

    var selectedRecord: CharacterRecord? {
        guard let selection else { return nil }
        return database?.record(for: selection)
    }

    func record(for codePoint: UInt32) -> CharacterRecord? { database?.record(for: codePoint) }

    private func searchBoosts() -> [UInt32: Double] {
        var boosts: [UInt32: Double] = [:]
        for (i, cp) in recents.prefix(12).enumerated() { boosts[cp] = 3.0 / Double(i + 1) }
        for cp in favorites { boosts[cp, default: 0] += 1.5 }
        return boosts
    }

    /// Search used by Quick Lookup (it keeps its own query). Runs on a background thread.
    func searchAsync(_ text: String, limit: Int) async -> [CharacterRecord] {
        guard let engine, let database else { return [] }
        let boosts = searchBoosts()
        return await Task.detached(priority: .userInitiated) {
            engine.search(text, limit: limit, boosts: boosts).compactMap { database.record(for: $0.codePoint) }
        }.value
    }

    @ObservationIgnored private var searchTask: Task<Void, Never>?

    /// Incremented by the Find command; the main window focuses its search field when it changes.
    var focusSearchRequest = 0

    func refreshResults() {
        searchTask?.cancel()
        guard let database, let engine else { results = []; return }
        if !query.isEmpty {
            // Search off the main thread so typing never stalls, and drop answers for outdated queries.
            let text = query
            let boosts = searchBoosts()
            searchTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(20))
                if Task.isCancelled { return }
                let hits = await Task.detached(priority: .userInitiated) {
                    engine.search(text, limit: 800, boosts: boosts).map(\.codePoint)
                }.value
                if Task.isCancelled { return }
                self?.applySearch(hits)
            }
            return
        }
        switch sidebar {
        case .all:
            // Control characters stay searchable (and live in the Spaces collection) but make a poor first impression.
            results = database.records.filter { $0.category != "Cc" }.map(\.codePoint)
        case .favorites:
            results = favorites.filter { database.record(for: $0) != nil }
        case .recents:
            results = recents.filter { database.record(for: $0) != nil }
        case .collection(let id):
            results = database.collection(id: id).map { database.records(in: $0).map(\.codePoint) } ?? []
        case .block(let index):
            results = database.records(inBlock: index).filter { $0.category != "Cc" }.map(\.codePoint)
        case .customFont:
            // "All visible characters in the font": skip spaces, joiners and other characters that draw nothing.
            if let font = customFont {
                results = database.records
                    .filter { $0.category != "Cc" && !CharacterInfo.isInvisible($0) && font.contains($0.scalar) }
                    .map(\.codePoint)
            } else {
                results = []
            }
        }
    }

    /// Localised name of a collection. Looked up with a runtime string key (not a SwiftUI literal), because an
    /// interpolated `LocalizedStringKey` would become the key "collection.%@".
    static func collectionTitle(_ id: String) -> String {
        NSLocalizedString("collection." + id, comment: "Name of a collection of characters")
    }

    private func applySearch(_ hits: [UInt32]) {
        results = hits
        if let wanted = pendingSelection, hits.contains(wanted) {
            selection = wanted
        } else if let first = hits.first {
            selection = first
        }
        pendingSelection = nil
    }

    /// A character that should be selected once the next search finishes (instead of that search's first hit).
    @ObservationIgnored private var pendingSelection: UInt32?

    /// Shows `record` in the main window: closes Quick Lookup, searches for the character's name so it appears with
    /// similar characters around it, selects it, and brings the window forward (Quick Lookup's ⌘↩).
    func reveal(_ record: CharacterRecord) {
        closeQuickLookup(returnToPreviousApp: false)
        if sidebar != .all { sidebar = .all }
        pendingSelection = record.codePoint
        selection = record.codePoint
        if query == record.name {
            refreshResults()   // same query: re-run it so the selection is applied
        } else {
            query = record.name
        }
        showMainWindow()
    }

    var title: String {
        if !query.isEmpty { return String(localized: "Search Results") }
        switch sidebar {
        case .all: return String(localized: "All Characters")
        case .favorites: return String(localized: "Favorites")
        case .recents: return String(localized: "Recents")
        case .collection(let id): return Self.collectionTitle(id)
        case .block(let index): return database?.blockNames[index] ?? ""
        case .customFont: return customFont?.displayName ?? ""
        }
    }

    var subtitle: String {
        guard case .ready = loadState else { return "" }
        return String(localized: "\(results.count) characters")
    }

    // MARK: Opened font

    /// Reads a font file into memory and starts using it for every glyph. The file is not installed.
    func openFont(at url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let font = try LoadedFont(data: Data(contentsOf: url))
            customFont = font
            sidebar = .customFont
            refreshResults()   // also when the font view was already showing another font
            announce(String(localized: "Opened font “\(font.displayName)”"))
        } catch {
            announce(error.localizedDescription)
        }
    }

    func closeFont() {
        customFont = nil
        if sidebar == .customFont { sidebar = .all } else { refreshResults() }
    }

    // MARK: Favorites and recents

    func isFavorite(_ codePoint: UInt32) -> Bool { favorites.contains(codePoint) }

    func toggleFavorite(_ codePoint: UInt32) {
        if let i = favorites.firstIndex(of: codePoint) {
            favorites.remove(at: i)
        } else {
            favorites.insert(codePoint, at: 0)
        }
        UserDefaults.standard.set(favorites.map(Int.init), forKey: SettingsKey.favorites)
        if sidebar == .favorites, query.isEmpty { refreshResults() }
    }

    func clearRecents() {
        recents = []
        UserDefaults.standard.set([Int](), forKey: SettingsKey.recents)
        if sidebar == .recents, query.isEmpty { refreshResults() }
    }

    private func noteUsed(_ codePoint: UInt32) {
        recents.removeAll { $0 == codePoint }
        recents.insert(codePoint, at: 0)
        if recents.count > Self.maxRecents { recents.removeLast(recents.count - Self.maxRecents) }
        UserDefaults.standard.set(recents.map(Int.init), forKey: SettingsKey.recents)
        // Do not reshuffle the grid under the user's cursor while they are looking at Recents.
    }

    // MARK: Copying

    func copy(_ record: CharacterRecord) {
        Inserter.copy(record.string)
        noteUsed(record.codePoint)
        announce(String(localized: "Copied “\(CharacterInfo.isInvisible(record) ? record.name.capitalized : record.string)”"))
    }

    func copyText(_ text: String, what: String) {
        Inserter.copy(text)
        announce(String(localized: "Copied \(what)"))
    }

    func announce(_ message: String) {
        let toast = Toast(message: message)
        self.toast = toast
        AccessibilityNotification.Announcement(message).post()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.6))
            if self.toast?.id == toast.id { self.toast = nil }
        }
    }

    // MARK: Windows

    func registerHotKey() {
        hotKey.onTrigger = { [weak self] in
            MainActor.assumeIsolated { self?.toggleQuickLookup() }
        }
        hotKey.register(HotKeyPreset.stored)
    }

    func setMainWindowOpen(_ open: Bool) {
        guard open != mainWindowOpen else { return }
        mainWindowOpen = open
        AppDelegate.applyActivationPolicy()
    }

    func quickLookupDidAppear() { quickLookupVisible = true }
    func quickLookupDidDisappear() { quickLookupVisible = false }

    func toggleQuickLookup() {
        if quickLookupVisible, NSApp.isActive {
            closeQuickLookup(returnToPreviousApp: true)
        } else {
            showQuickLookup()
        }
    }

    func showQuickLookup() {
        let front = NSWorkspace.shared.frontmostApplication
        if front?.processIdentifier != ProcessInfo.processInfo.processIdentifier { previousApplication = front }
        NSApp.activate()
        openWindow?(id: SceneID.quick)
        // The app may still be activating (shortcut pressed in another app), and an already open panel gets no
        // new appearance event, so make it key explicitly, now and once activation has settled.
        for delay in [0.0, 0.15] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard self?.quickLookupVisible == true else { return }
                ChromelessWindow.focus()
            }
        }
    }

    func closeQuickLookup(returnToPreviousApp: Bool) {
        dismissWindow?(id: SceneID.quick)
        if returnToPreviousApp { previousApplication?.activate() }
    }

    /// Copies, closes Quick Lookup, hands focus back, and (direct-distribution builds) pastes.
    func finishQuickLookup(with record: CharacterRecord) {
        copy(record)
        let closeAfterCopy = UserDefaults.standard.object(forKey: SettingsKey.closeQuickAfterCopy) as? Bool ?? true
        guard closeAfterCopy else { return }
        closeQuickLookup(returnToPreviousApp: true)
        if Inserter.canPasteAutomatically, UserDefaults.standard.bool(forKey: SettingsKey.autoPaste) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { Inserter.pasteIntoFrontmostApp() }
        }
    }

    func showMainWindow() {
        // The floating Quick Lookup would sit on top of the window that is about to open.
        if quickLookupVisible { closeQuickLookup(returnToPreviousApp: false) }
        // Opening the window on purpose: bring the Dock icon back first. (From a menu-bar-only state the new window
        // may not become the "main" window, so the window notifications alone cannot be relied on.)
        setMainWindowOpen(true)
        NSApp.activate()
        if let openWindow {
            openWindow(id: SceneID.main)
        } else {
            NSApp.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
        }
    }

    /// Called by every scene's root view so that the model can open windows from anywhere (hotkey, Dock click, intents).
    func adopt(openWindow: OpenWindowAction, dismissWindow: DismissWindowAction) {
        self.openWindow = openWindow
        self.dismissWindow = dismissWindow
    }
}
