import AppKit
import CoreText

/// The menu bar item. A click opens Quick Lookup; the menu appears on a right click, or on a click while Quick Lookup
/// is already showing. SwiftUI's `MenuBarExtra` cannot tell the two kinds of click apart, so this is the one place
/// where the menu bar item is built with AppKit (`NSStatusItem`).
@MainActor
final class StatusItemController: NSObject {
    private let model: AppModel
    private var statusItem: NSStatusItem?
    private var defaultsObserver: NSObjectProtocol?

    init(model: AppModel) {
        self.model = model
        super.init()
        apply()
        // "Show in menu bar" in Settings is a UserDefaults flag.
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.apply() }
        }
    }

    private func apply() {
        let visible = UserDefaults.standard.object(forKey: SettingsKey.showMenuBarItem) as? Bool ?? true
        if visible { install() } else { remove() }
    }

    private func install() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = Self.makeIcon()
            button.target = self
            button.action = #selector(clicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "Glyphfinder"
        }
        statusItem = item
    }

    /// The menu bar icon: the letters "a b c" arranged as a triangle (a on top, b and c below). Drawn in code so it
    /// needs no image asset, and marked as a template so macOS tints it for light and dark menu bars and for the
    /// highlighted state.
    private static func makeIcon() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            let font = NSFont.systemFont(ofSize: 9, weight: .bold)
            context.setFillColor(NSColor.black.cgColor)

            /// Draws `letter` so that the centre of its ink (not of its line box) sits at `center`.
            func draw(_ letter: String, at center: CGPoint) {
                let text = NSAttributedString(string: letter, attributes: [.font: font])
                let line = CTLineCreateWithAttributedString(text)
                let ink = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
                context.textPosition = CGPoint(x: center.x - ink.midX, y: center.y - ink.midY)
                CTLineDraw(line, context)
            }

            draw("a", at: CGPoint(x: 9.0, y: 12.4))
            draw("b", at: CGPoint(x: 4.3, y: 4.8))
            draw("c", at: CGPoint(x: 13.7, y: 4.8))
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Glyphfinder"
        return image
    }

    private func remove() {
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        statusItem = nil
    }

    // MARK: Clicks

    @objc private func clicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let isRightClick = event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true
        if isRightClick || model.quickLookupVisible {
            showMenu()
        } else {
            model.showQuickLookup()
        }
    }

    private func showMenu() {
        guard let statusItem, let button = statusItem.button else { return }
        // Attaching the menu only for the duration of the click keeps ordinary clicks free to open Quick Lookup.
        statusItem.menu = makeMenu()
        button.performClick(nil)
        statusItem.menu = nil
    }

    // MARK: Menu

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(item(String(localized: "Quick Lookup…"), #selector(openQuickLookup)))
        menu.addItem(item(String(localized: "Open Glyphfinder"), #selector(openMainWindow)))
        menu.addItem(.separator())
        menu.addItem(characterSubmenu(
            title: String(localized: "Recent Characters"),
            codePoints: Array(model.recents.prefix(10)),
            emptyTitle: String(localized: "Nothing copied yet")
        ))
        menu.addItem(characterSubmenu(
            title: String(localized: "Favorites"),
            codePoints: Array(model.favorites.prefix(20)),
            emptyTitle: String(localized: "No favorites yet")
        ))
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "Settings…"), #selector(openSettings), key: ","))
        menu.addItem(item(String(localized: "Quit Glyphfinder"), #selector(quit), key: "q"))
        return menu
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: key)
        menuItem.target = self
        return menuItem
    }

    private func characterSubmenu(title: String, codePoints: [UInt32], emptyTitle: String) -> NSMenuItem {
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        let records = codePoints.compactMap { model.record(for: $0) }
        if records.isEmpty {
            let placeholder = NSMenuItem(title: emptyTitle, action: nil, keyEquivalent: "")
            placeholder.isEnabled = false
            submenu.addItem(placeholder)
        } else {
            for record in records {
                let glyph = CharacterInfo.isInvisible(record) ? "␣" : record.string
                let entry = item(glyph + "  " + record.titleCasedName, #selector(copyCharacter(_:)))
                entry.representedObject = NSNumber(value: record.codePoint)
                submenu.addItem(entry)
            }
        }
        parent.submenu = submenu
        return parent
    }

    @objc private func openQuickLookup() { model.showQuickLookup() }
    @objc private func openMainWindow() { model.showMainWindow() }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func openSettings() {
        NSApp.activate()
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    @objc private func copyCharacter(_ sender: NSMenuItem) {
        guard let number = sender.representedObject as? NSNumber, let record = model.record(for: number.uint32Value) else { return }
        model.copy(record)
    }
}
