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

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 10, style: .continuous) }
    private var fillColor: Color { isSelected ? Color.accentColor.opacity(0.22) : Color.clear }
    private var borderColor: Color { isSelected ? Color.accentColor : Color.clear }
    private var traits: AccessibilityTraits { isSelected ? [.isButton, .isSelected] : [.isButton] }
    private var helpText: String {
        let base = record.titleCasedName + "  " + CodeFormats.codePoint(record.codePoint)
        guard let font = model.customFont, !font.contains(record.scalar), !CharacterInfo.isInvisible(record) || CharacterInfo.isSpace(record) else { return base }
        return base + " — " + String(localized: "Not in the opened font")
    }

    var body: some View {
        content
            .contentShape(shape)
            .draggable(record.string)
            .contextMenu { CharacterContextMenu(record: record) }
            .help(helpText)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(CharacterInfo.accessibilityLabel(for: record))
            .accessibilityValue(CodeFormats.codePoint(record.codePoint))
            .accessibilityAddTraits(traits)
            .accessibilityAction(named: Text("Copy Character")) { model.copy(record) }
    }

    private var content: some View {
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
        .background { shape.fill(fillColor) }
        .overlay { shape.strokeBorder(borderColor, lineWidth: 1.5) }
    }
}

/// The glyph itself. Spaces get two dotted lines showing their width, other invisibles a dashed box, and everything
/// else is drawn as text. While a font file is open the glyph is drawn with it; characters the font lacks are drawn with
/// the current font at reduced opacity on a yellow-tinted box, so a missing glyph can never pass for a real one.
struct GlyphView: View {
    @Environment(AppModel.self) private var model

    let record: CharacterRecord
    let pointSize: CGFloat
    var fontName: String = ""

    var body: some View {
        let custom = model.customFont
        let missing = custom.map { !$0.contains(record.scalar) } ?? false
        glyph(custom: custom, missing: missing)
    }

    @ViewBuilder
    private func glyph(custom: LoadedFont?, missing: Bool) -> some View {
        if CharacterInfo.isSpace(record) {
            // Spaces: two dotted lines show how wide the space is (in the opened font, when it has the space).
            let advance = advance(custom: custom, missing: missing)
            InvisibleWidthMark(
                label: CharacterInfo.shortLabel(for: record),
                advance: advance,
                pointSize: pointSize
            )
            .opacity(missing ? Self.missingOpacity : 1)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { if missing { MissingGlyphBox() } }
        } else if CharacterInfo.isInvisible(record) {
            // Other invisibles (joiners, marks, fillers, controls): a dashed box with an abbreviation.
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
                .font(Self.font(custom: custom, missing: missing, fontName: fontName, size: pointSize))
                .minimumScaleFactor(0.4)
                .lineLimit(1)
                .opacity(missing ? Self.missingOpacity : 1)
                .padding(.horizontal, 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background { if missing { MissingGlyphBox() } }
        }
    }

    private func advance(custom: LoadedFont?, missing: Bool) -> CGFloat? {
        if let custom, !missing { return AdvanceCache.shared.advanceEm(of: record.scalar, font: custom) }
        return AdvanceCache.shared.advanceEm(of: record.scalar, fontName: fontName)
    }

    /// How faint a fallback glyph is drawn.
    static let missingOpacity = 0.4

    static func font(named name: String, size: CGFloat) -> Font {
        name.isEmpty ? .system(size: size) : .custom(name, size: size)
    }

    /// The opened font when it has the glyph; otherwise the font chosen in Settings (or the system font).
    static func font(custom: LoadedFont?, missing: Bool, fontName: String, size: CGFloat) -> Font {
        if let custom, !missing { return Font(custom.ctFont(size: size)) }
        return font(named: fontName, size: size)
    }
}

/// Yellow-tinted box behind a glyph that the opened font does not contain.
struct MissingGlyphBox: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.yellow.opacity(0.25))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.yellow.opacity(0.7), lineWidth: 1)
            }
    }
}

/// A space drawn as two dotted vertical lines whose distance is the character's advance width, with its
/// abbreviation above. A thin space, a hair space and an em space therefore look different in the grid, which is the
/// whole point: in text they are all "nothing".
struct InvisibleWidthMark: View {
    let label: String
    /// Advance in em, or nil when no installed font draws the character.
    let advance: CGFloat?
    let pointSize: CGFloat

    var body: some View {
        VStack(spacing: 1) {
            Text(label)
                .font(.system(size: max(7, pointSize * 0.24), weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Canvas { context, size in
                // One em is drawn 1.5 point sizes wide: a full em space still fits inside a grid cell, and a thin
                // space (about a tenth of an em) is still a visibly separate pair of lines.
                let em = pointSize * 1.5
                let width = min(max((advance ?? 0.5) * em, 0), size.width - 6)
                let left = (size.width - width) / 2
                var lines = Path()
                for x in [left, left + width] {
                    lines.move(to: CGPoint(x: x, y: 1))
                    lines.addLine(to: CGPoint(x: x, y: size.height - 1))
                }
                let style = StrokeStyle(lineWidth: 1.4, lineCap: .round, dash: [1.5, 3])
                // Unknown width (no font draws it): grey lines; known width: the usual secondary color.
                context.stroke(lines, with: .color(advance == nil ? .secondary.opacity(0.4) : .secondary), style: style)
            }
            .frame(height: max(14, pointSize * 0.62))
        }
        .accessibilityElement(children: .ignore)
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
