import CoreText
import SwiftUI

/// Scrollable grid of characters, virtualized by hand.
///
/// "All Characters" has over 32,000 cells. `LazyVGrid` has to estimate the size of the whole grid, and dragging the
/// scroll bar far makes it work through enormous ranges. Every cell here has the same size, so the position of any row
/// is plain arithmetic: the scroll view gets the full content height and only the rows on screen (plus a few spare
/// ones) are built. Jumping to the end costs the same as scrolling by one row.
///
/// SwiftUI has no selection or keyboard navigation for grids either, so both are implemented here.
struct CharacterGridView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(SettingsKey.gridCellSize) private var cellSize = GlyphSize.default
    @FocusState private var gridFocused: Bool
    @State private var scrollPosition = ScrollPosition(edge: .top)
    /// Rows that should exist, updated only when scrolling crosses a row boundary (not on every pixel).
    @State private var scrolledRows: Range<Int>?
    @State private var viewport = ViewportBox()

    let codePoints: [UInt32]

    private let spacing: CGFloat = 8
    private let padding: CGFloat = 14
    private let spareRows = 2

    /// The visible rectangle, kept outside SwiftUI state: it changes every pixel and nothing needs to redraw for it.
    private final class ViewportBox {
        var rect: CGRect = .zero
    }

    private struct ResultsKey: Equatable {
        let first: UInt32?
        let count: Int
    }

    /// Fixed-size cell geometry.
    private struct Metrics {
        let columns: Int
        let rows: Int
        let cellSize: CGFloat
        let spacing: CGFloat
        let padding: CGFloat

        var cellHeight: CGFloat { cellSize + 10 }
        var rowStride: CGFloat { cellHeight + spacing }
        var contentHeight: CGFloat { rows == 0 ? 0 : padding * 2 + CGFloat(rows) * rowStride - spacing }
        var rowWidth: CGFloat { CGFloat(columns) * cellSize + CGFloat(columns - 1) * spacing }

        func rowY(_ row: Int) -> CGFloat { padding + CGFloat(row) * rowStride }

        /// Rows intersecting the vertical span, widened by `spare` rows on each side.
        func visibleRows(minY: CGFloat, maxY: CGFloat, spare: Int) -> Range<Int> {
            guard rows > 0 else { return 0..<0 }
            let first = Int(((minY - padding) / rowStride).rounded(.down)) - spare
            let last = Int(((maxY - padding) / rowStride).rounded(.up)) + spare
            let lower = min(max(first, 0), rows - 1)
            let upper = min(max(last + 1, lower + 1), rows)
            return lower..<upper
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let columns = max(1, Int((proxy.size.width - padding * 2 + spacing) / (cellSize + spacing)))
            let rows = (codePoints.count + columns - 1) / columns
            grid(
                Metrics(columns: columns, rows: rows, cellSize: cellSize, spacing: spacing, padding: padding),
                width: proxy.size.width,
                height: proxy.size.height
            )
        }
    }

    private func grid(_ metrics: Metrics, width: CGFloat, height: CGFloat) -> some View {
        let range = shownRows(metrics, height: height)
        let leading = max(padding, (width - metrics.rowWidth) / 2)

        return ScrollView {
            ZStack(alignment: .topLeading) {
                // Gives the scroll view the height of the whole grid.
                Color.clear.frame(width: 1, height: metrics.contentHeight)
                ForEach(range, id: \.self) { row in
                    rowView(row, metrics)
                        .offset(x: leading, y: metrics.rowY(row))
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollPosition($scrollPosition)
        .onScrollGeometryChange(for: Range<Int>.self, of: { geometry in
            metrics.visibleRows(minY: geometry.visibleRect.minY, maxY: geometry.visibleRect.maxY, spare: spareRows)
        }, action: { _, newRows in
            scrolledRows = newRows
        })
        .onScrollGeometryChange(for: CGRect.self, of: { $0.visibleRect }, action: { _, rect in
            viewport.rect = rect
        })
        .focusable()
        .focused($gridFocused)
        .focusEffectDisabled()
        .onMoveCommand { direction in
            switch direction {
            case .left: moveSelection(by: -1, metrics, extendTo: nil)
            case .right: moveSelection(by: 1, metrics, extendTo: nil)
            case .up: moveSelection(by: -metrics.columns, metrics, extendTo: nil)
            case .down: moveSelection(by: metrics.columns, metrics, extendTo: nil)
            @unknown default: break
            }
        }
        .onKeyPress(.return) {
            if let record = model.selectedRecord { model.copy(record) }
            return .handled
        }
        .onKeyPress(.home) { moveSelection(by: 0, metrics, extendTo: 0); return .handled }
        .onKeyPress(.end) { moveSelection(by: 0, metrics, extendTo: codePoints.count - 1); return .handled }
        .onKeyPress(.pageDown) { moveSelection(by: pageStep(metrics), metrics, extendTo: nil); return .handled }
        .onKeyPress(.pageUp) { moveSelection(by: -pageStep(metrics), metrics, extendTo: nil); return .handled }
        .onChange(of: model.selection) { _, newValue in
            if let newValue { reveal(newValue, metrics) }
        }
        .onChange(of: ResultsKey(first: codePoints.first, count: codePoints.count)) { _, _ in
            // A new result set: start at the top.
            scrolledRows = nil
            scrollPosition.scrollTo(edge: .top)
        }
        .accessibilityLabel("Characters")
    }

    /// The rows to build: the ones reported by scrolling, or an estimate for the first screen.
    private func shownRows(_ metrics: Metrics, height: CGFloat) -> Range<Int> {
        guard metrics.rows > 0 else { return 0..<0 }
        let range = scrolledRows ?? metrics.visibleRows(minY: 0, maxY: height, spare: spareRows)
        let lower = min(range.lowerBound, metrics.rows - 1)
        let upper = min(max(range.upperBound, lower + 1), metrics.rows)
        return lower..<upper
    }

    private func rowView(_ row: Int, _ metrics: Metrics) -> some View {
        HStack(spacing: spacing) {
            ForEach(0..<metrics.columns, id: \.self) { column in
                cell(at: row * metrics.columns + column)
            }
        }
    }

    @ViewBuilder
    private func cell(at index: Int) -> some View {
        if index < codePoints.count, let record = model.record(for: codePoints[index]) {
            CharacterCell(record: record, size: cellSize, isSelected: model.selection == record.codePoint)
                .onTapGesture(count: 2) { model.copy(record) }
                .simultaneousGesture(TapGesture().onEnded {
                    model.selection = record.codePoint
                    gridFocused = true
                })
        } else {
            Color.clear.frame(width: cellSize, height: cellSize + 10)
        }
    }

    // MARK: Selection and scrolling

    /// Moves the selection by `offset` cells, or to `extendTo` (an index) when given.
    private func moveSelection(by offset: Int, _ metrics: Metrics, extendTo target: Int?) {
        guard !codePoints.isEmpty else { return }
        let current = model.selection.flatMap { codePoints.firstIndex(of: $0) }
        var index: Int
        if let target {
            index = target
        } else if let current {
            index = current + offset
        } else {
            index = 0
        }
        index = min(max(index, 0), codePoints.count - 1)
        model.selection = codePoints[index]
    }

    /// One page: the rows that fit, minus one for context.
    private func pageStep(_ metrics: Metrics) -> Int {
        let rowsPerPage = max(1, Int(viewport.rect.height / metrics.rowStride) - 1)
        return rowsPerPage * metrics.columns
    }

    /// Scrolls just far enough for the selected cell to be visible.
    private func reveal(_ codePoint: UInt32, _ metrics: Metrics) {
        guard let index = codePoints.firstIndex(of: codePoint) else { return }
        let rect = viewport.rect
        guard rect.height > 0 else { return }
        let top = metrics.rowY(index / metrics.columns)
        let bottom = top + metrics.cellHeight
        if top < rect.minY + 4 {
            scrollPosition.scrollTo(y: max(0, top - padding))
        } else if bottom > rect.maxY - 4 {
            scrollPosition.scrollTo(y: bottom + padding - rect.height)
        }
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
        } else if custom == nil || missing, !GlyphCoverage.hasGlyph(record.scalar, fontName: fontName) {
            // No installed font has this character. Newer macOS draws a question mark for it; show an empty box.
            NoGlyphBox()
                .frame(width: pointSize * 0.7, height: pointSize * 0.7)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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

/// Whether any installed font can draw a character. Looks at the font CoreText would fall back to: the "Last Resort"
/// font means nothing has it.
enum GlyphCoverage {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [String: Bool] = [:]

    static func hasGlyph(_ scalar: Unicode.Scalar, fontName: String) -> Bool {
        let key = "\(scalar.value)|\(fontName)"
        lock.lock()
        defer { lock.unlock() }
        if let known = cache[key] { return known }
        let base = fontName.isEmpty
            ? CTFontCreateUIFontForLanguage(.system, 16, nil) ?? CTFontCreateWithName("Helvetica" as CFString, 16, nil)
            : CTFontCreateWithName(fontName as CFString, 16, nil)
        let string = String(Character(scalar)) as CFString
        let fallback = CTFontCreateForString(base, string, CFRange(location: 0, length: CFStringGetLength(string)))
        let name = CTFontCopyPostScriptName(fallback) as String
        let covered = !name.localizedCaseInsensitiveContains("LastResort")
        cache[key] = covered
        return covered
    }
}

/// An empty box in the same light yellow as `MissingGlyphBox`, so it reads as "no glyph" and not as a shape.
struct NoGlyphBox: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.yellow.opacity(0.12))
            .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.yellow.opacity(0.35), lineWidth: 1) }
            .aspectRatio(1, contentMode: .fit)
            .accessibilityHidden(true)
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
