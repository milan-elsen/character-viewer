import AppKit
import SwiftUI

/// The menu bar item: a standard menu, as users expect from a Mac utility.
struct MenuBarContent: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        Button("Quick Lookup…") {
            adopt()
            model.showQuickLookup()
        }
        Button("Open Glyphfinder") {
            adopt()
            model.showMainWindow()
        }

        Divider()

        Menu("Recent Characters") {
            let recents = model.recents.prefix(10).compactMap { model.record(for: $0) }
            if recents.isEmpty {
                Text("Nothing copied yet")
            } else {
                ForEach(recents) { record in
                    Button(label(for: record)) { model.copy(record) }
                }
            }
        }

        Menu("Favorites") {
            let favorites = model.favorites.prefix(20).compactMap { model.record(for: $0) }
            if favorites.isEmpty {
                Text("No favorites yet")
            } else {
                ForEach(favorites) { record in
                    Button(label(for: record)) { model.copy(record) }
                }
            }
        }

        Divider()

        SettingsLink {
            Text("Settings…")
        }
        .keyboardShortcut(",")

        Button("Quit Glyphfinder") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func adopt() {
        model.adopt(openWindow: openWindow, dismissWindow: dismissWindow)
    }

    private func label(for record: CharacterRecord) -> String {
        let glyph = CharacterInfo.isInvisible(record) ? "␣" : record.string
        return glyph + "  " + record.titleCasedName
    }
}
