import SwiftUI

/// The main window: sidebar (library, collections, blocks), results grid, and an inspector for the selection.
struct MainView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @AppStorage(SettingsKey.showInspector) private var showInspector = true

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
