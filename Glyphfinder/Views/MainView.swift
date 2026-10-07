import SwiftUI
import UniformTypeIdentifiers

/// The main window: sidebar (library, collections, blocks), results grid, and an inspector for the selection.
struct MainView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @AppStorage(SettingsKey.showInspector) private var showInspector = true
    @FocusState private var searchFocused: Bool

    var body: some View {
        @Bindable var model = model

        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 300)
        } detail: {
            ResultsView()
                .navigationTitle(model.title)
                .navigationSubtitle(model.subtitle)
                .inspector(isPresented: $showInspector) {
                    DetailView()
                        .inspectorColumnWidth(min: 300, ideal: 340, max: 480)
                }
        }
        .searchable(text: $model.query, placement: .toolbar, prompt: "Search by name, code or description")
        .searchFocused($searchFocused)
        .onChange(of: model.focusSearchRequest) { _, _ in searchFocused = true }
        .searchSuggestions {
            if model.query.isEmpty {
                Text("thin space").searchCompletion("thin space")
                Text("em dash").searchCompletion("em dash")
                Text("U+2009").searchCompletion("U+2009")
                Text("curly apostrophe").searchCompletion("curly apostrophe")
                Text("right arrow").searchCompletion("right arrow")
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    model.showFontImporter = true
                } label: {
                    Label("Open Font…", systemImage: "textformat")
                }
                .help("Open Font…")
                if model.customFont != nil {
                    Button {
                        model.closeFont()
                    } label: {
                        Label("Close Font", systemImage: "xmark.circle")
                    }
                    .help("Close Font")
                }
                if let record = model.selectedRecord {
                    Button {
                        model.copy(record)
                    } label: {
                        Label("Copy Character", systemImage: "doc.on.doc")
                    }
                    .help("Copy Character")
                }
                Button {
                    showInspector.toggle()
                } label: {
                    Label("Inspector", systemImage: "sidebar.trailing")
                }
                .help("Show or Hide Inspector")
            }
        }
        .fileImporter(isPresented: $model.showFontImporter, allowedContentTypes: [.font], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first { model.openFont(at: url) }
            case .failure(let error):
                model.announce(error.localizedDescription)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            model.openFont(at: url)
            return true
        }
        .toast(model.toast)
        .focusedSceneValue(\.selectedCharacter, model.selectedRecord)
        .frame(minWidth: 780, minHeight: 480)
        .onAppear { model.adopt(openWindow: openWindow, dismissWindow: dismissWindow) }
    }
}

/// Grid of results, or an explanation when there is nothing to show.
struct ResultsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        switch model.loadState {
        case .loading:
            ProgressView("Loading characters…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ContentUnavailableView(
                "Characters Could Not Be Loaded",
                systemImage: "exclamationmark.triangle",
                description: Text(message)
            )
        case .ready:
            if model.results.isEmpty {
                emptyState
            } else {
                CharacterGridView(codePoints: model.results)
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if model.isSearching {
            ContentUnavailableView.search(text: model.query)
        } else {
            switch model.sidebar {
            case .favorites:
                ContentUnavailableView(
                    "No Favorites Yet",
                    systemImage: "star",
                    description: Text("Control-click a character and choose Add to Favorites.")
                )
            case .recents:
                ContentUnavailableView(
                    "Nothing Copied Yet",
                    systemImage: "clock",
                    description: Text("Characters you copy appear here.")
                )
            default:
                ContentUnavailableView("No Characters", systemImage: "character.cursor.ibeam")
            }
        }
    }
}
