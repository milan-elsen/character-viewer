import SwiftUI

// The selected character, published by the main window so menu commands can act on it.
private struct SelectedCharacterKey: FocusedValueKey {
    typealias Value = CharacterRecord
}

extension FocusedValues {
    var selectedCharacter: CharacterRecord? {
        get { self[SelectedCharacterKey.self] }
        set { self[SelectedCharacterKey.self] = newValue }
    }
}

/// The menu bar. Standard menus (App, Edit, Window, Help) come from the system; these commands add what is
/// specific to this app.
struct AppCommands: Commands {
    let model: AppModel

    @FocusedValue(\.selectedCharacter) private var selected
    @AppStorage(SettingsKey.gridCellSize) private var cellSize = GlyphSize.default

    var body: some Commands {
        SidebarCommands()
        InspectorCommands()

        // File > New is meaningless in a single-window utility; Quick Lookup takes its place.
        CommandGroup(replacing: .newItem) {
            Button("Quick Lookup") { model.showQuickLookup() }
                .keyboardShortcut("l", modifiers: [.command, .option])

            Divider()

            Button("Open Font…") { model.showFontImporter = true }
                .keyboardShortcut("o", modifiers: .command)
            Button("Close Font") { model.closeFont() }
                .disabled(model.customFont == nil)
        }

        CommandGroup(after: .textEditing) {
            Button("Find…") { model.focusSearchRequest += 1 }
                .keyboardShortcut("f", modifiers: .command)
        }

        CommandMenu("Character") {
            Button("Copy Character") {
                if let selected { model.copy(selected) }
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(selected == nil)

            Button("Copy Code Point") {
                if let selected { model.copyText(CodeFormats.codePoint(selected.codePoint), what: String(localized: "code point")) }
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .disabled(selected == nil)

            Button("Copy HTML Entity") {
                if let selected {
                    model.copyText(htmlEntity(for: selected), what: String(localized: "HTML entity"))
                }
            }
            .keyboardShortcut("c", modifiers: [.command, .option])
            .disabled(selected == nil)

            Divider()

            Button(isSelectedFavorite ? LocalizedStringKey("Remove from Favorites") : LocalizedStringKey("Add to Favorites")) {
                if let selected { model.toggleFavorite(selected.codePoint) }
            }
            .keyboardShortcut("d", modifiers: .command)
            .disabled(selected == nil)

            Divider()

            Button("Clear Recents") { model.clearRecents() }
                .disabled(model.recents.isEmpty)
        }

        CommandGroup(after: .toolbar) {
            Divider()
            Button("Larger Glyphs") { cellSize = min(cellSize + 16, GlyphSize.range.upperBound) }
                .keyboardShortcut("+", modifiers: .command)
            Button("Smaller Glyphs") { cellSize = max(cellSize - 16, GlyphSize.range.lowerBound) }
                .keyboardShortcut("-", modifiers: .command)
            Button("Default Glyph Size") { cellSize = GlyphSize.default }
                .keyboardShortcut("0", modifiers: .command)
        }
    }

    private var isSelectedFavorite: Bool {
        selected.map { model.isFavorite($0.codePoint) } ?? false
    }

    private func htmlEntity(for record: CharacterRecord) -> String {
        CodeFormats.formats(for: record, database: model.database!)
            .first { $0.id == "html-named" }?.value ?? "&#\(record.codePoint);"
    }
}
