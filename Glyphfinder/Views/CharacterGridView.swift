import SwiftUI

/// Scrollable grid of characters. SwiftUI's lazy grids have no built-in selection or arrow-key navigation,
/// so both are implemented here with `focusable` + `onMoveCommand`.
struct CharacterGridView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(SettingsKey.gridCellSize) private var cellSize = GlyphSize.default
    @FocusState private var gridFocused: Bool

    let codePoints: [UInt32]

    private let spacing: CGFloat = 8
    private let padding: CGFloat = 14

    var body: some View {
        GeometryReader { proxy in
            let columnCount = max(1, Int((proxy.size.width - padding * 2 + spacing) / (cellSize + spacing)))
            let columns = Array(repeating: GridItem(.fixed(cellSize), spacing: spacing), count: columnCount)

            ScrollViewReader { scroller in
                ScrollView {
                    LazyVGrid(columns: columns, spacing: spacing) {
                        ForEach(codePoints, id: \.self) { codePoint in
                            if let record = model.record(for: codePoint) {
                                CharacterCell(record: record, size: cellSize, isSelected: model.selection == codePoint)
                                    .id(codePoint)
                                    .onTapGesture(count: 2) { model.copy(record) }
                                    .simultaneousGesture(TapGesture().onEnded {
                                        model.selection = codePoint
                                        gridFocused = true
                                    })
                            }
                        }
                    }
                    .padding(padding)
                    .frame(maxWidth: .infinity)
                }
                .focusable()
                .focused($gridFocused)
                .focusEffectDisabled()
                .onMoveCommand { direction in move(direction, columns: columnCount) }
                .onKeyPress(.return) {
                    if let record = model.selectedRecord { model.copy(record) }
                    return .handled
                }
                .onChange(of: model.selection) { _, newValue in
                    if let newValue { scroller.scrollTo(newValue) }
                }
                .onChange(of: codePoints.first) { _, _ in
                    // New result set: start at the top.
                    if let first = codePoints.first { scroller.scrollTo(first, anchor: .top) }
                }
                .accessibilityLabel("Characters")
            }
        }
    }

    private func move(_ direction: MoveCommandDirection, columns: Int) {
        guard !codePoints.isEmpty else { return }
        let current = model.selection.flatMap { codePoints.firstIndex(of: $0) }
        var index = current ?? 0
        if current != nil {
            switch direction {
            case .left: index -= 1
            case .right: index += 1
            case .up: index -= columns
            case .down: index += columns
            @unknown default: break
            }
        }
        index = min(max(index, 0), codePoints.count - 1)
        model.selection = codePoints[index]
    }
}

/// One cell: the glyph (or a labelled placeholder for invisible characters) and the character's name.
struct CharacterCell: View {
    @Environment(AppModel.self) private var model
    @AppStorage(SettingsKey.previewFont) private var fontName = ""

    let record: CharacterRecord
    let size: CGFloat
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 4) {
            GlyphView(record: record, pointSize: size * 0.42, fontName: fontName)
                .frame(height: size * 0.52)
            Text(record.titleCasedName)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .padding(6)
        .frame(width: size, height: size + 10)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.22) : Color.clear)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
        }
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .draggable(record.string)
        .contextMenu { CharacterContextMenu(record: record) }
        .help(record.titleCasedName + "  " + CodeFormats.codePoint(record.codePoint))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(CharacterInfo.accessibilityLabel(for: record))
        .accessibilityValue(CodeFormats.codePoint(record.codePoint))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(named: "Copy Character") { model.copy(record) }
    }
}

/// The glyph itself. Invisible characters (spaces, joiners ...) get a dashed box with an abbreviation, so that a
/// grid of "nothing" is still readable.
struct GlyphView: View {
    let record: CharacterRecord
    let pointSize: CGFloat
    var fontName: String = ""

    var body: some View {
        if CharacterInfo.isInvisible(record) {
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(.secondary, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                .frame(width: pointSize * 1.1, height: pointSize * 0.8)
                .overlay {
                    Text(CharacterInfo.shortLabel(for: record))
                        .font(.system(size: max(8, pointSize * 0.26), weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .padding(2)
                }
        } else {
            Text(CharacterInfo.displayString(for: record))
                .font(Self.font(named: fontName, size: pointSize))
                .minimumScaleFactor(0.4)
                .lineLimit(1)
        }
    }

    static func font(named name: String, size: CGFloat) -> Font {
        name.isEmpty ? .system(size: size) : .custom(name, size: size)
    }
}

struct CharacterContextMenu: View {
    @Environment(AppModel.self) private var model
    let record: CharacterRecord

    var body: some View {
        Button("Copy Character") { model.copy(record) }
        Button("Copy Code Point") {
            model.copyText(CodeFormats.codePoint(record.codePoint), what: String(localized: "code point"))
        }
        Button("Copy Name") {
            model.copyText(record.name, what: String(localized: "name"))
        }
        Divider()
        Button(model.isFavorite(record.codePoint) ? LocalizedStringKey("Remove from Favorites") : LocalizedStringKey("Add to Favorites")) {
            model.toggleFavorite(record.codePoint)
        }
    }
}
