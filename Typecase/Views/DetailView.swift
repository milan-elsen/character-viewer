import AppKit
import SwiftUI

/// Inspector for the selected character: preview, how to type it, codes, related characters, font alternates.
struct DetailView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let record = model.selectedRecord {
            DetailContent(record: record)
        } else {
            ContentUnavailableView(
                "No Character Selected",
                systemImage: "character.cursor.ibeam",
                description: Text("Select a character to see its codes, related characters and how to type it.")
            )
        }
    }
}

private struct DetailContent: View {
    @Environment(AppModel.self) private var model
    let record: CharacterRecord

    var body: some View {
        Form {
            previewSection
            TypingSection(record: record)
            codesSection
            informationSection
            if !relatedRecords.isEmpty { relatedSection }
            FontSection(record: record)
        }
        .formStyle(.grouped)
        .id(record.codePoint)   // reset scroll position and per-character state when the selection changes
    }

    private var database: CharacterDatabase { model.database! }

    private var relatedRecords: [CharacterRecord] { database.records(for: record.related) }

    // MARK: Sections

    private var previewSection: some View {
        Section {
            VStack(spacing: 10) {
                GlyphPreview(record: record)
                    .frame(maxWidth: .infinity)
                if let font = model.customFont, !font.contains(record.scalar), !CharacterInfo.isInvisible(record) || CharacterInfo.isSpace(record) {
                    Label("Not in “\(font.displayName)”. Showing the fallback font.", systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .multilineTextAlignment(.leading)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background { MissingGlyphBox() }
                }
                Text(record.titleCasedName)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
                Text(CodeFormats.codePoint(record.codePoint))
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                HStack {
                    Button {
                        model.copy(record)
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.borderedProminent)
                    .help("Copy Character")

                    Button {
                        model.toggleFavorite(record.codePoint)
                    } label: {
                        Label("Favorite", systemImage: model.isFavorite(record.codePoint) ? "star.fill" : "star")
                    }
                    .help(model.isFavorite(record.codePoint) ? "Remove from Favorites" : "Add to Favorites")
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
    }

    private var codesSection: some View {
        let formats = CodeFormats.formats(for: record, database: database)
        return Section("Codes") {
            ForEach(formats) { format in
                LabeledContent {
                    HStack(spacing: 6) {
                        Text(format.value)
                            .font(.body.monospaced())
                            .textSelection(.enabled)
                        Button {
                            model.copyText(format.value, what: format.title)
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                        .help("Copy")
                        .accessibilityLabel("Copy \(format.title)")
                    }
                } label: {
                    Text(LocalizedStringKey(format.title))
                }
                .contextMenu {
                    Button("Copy") { model.copyText(format.value, what: format.title) }
                }
            }
        }
    }

    private var informationSection: some View {
        Section("Information") {
            LabeledContent("Category", value: CharacterInfo.categoryName(record.category))
            LabeledContent("Block", value: database.blockName(of: record))
            LabeledContent("Script", value: database.scriptName(of: record))
            LabeledContent("Introduced", value: "Unicode " + database.ageName(of: record))
            if !allNames.isEmpty {
                LabeledContent("Also Called") {
                    Text(allNames.joined(separator: ", "))
                        .multilineTextAlignment(.trailing)
                        .textSelection(.enabled)
                }
            }
            if !record.notes.isEmpty {
                Text(record.notes)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Aliases and curated terms, without duplicates.
    private var allNames: [String] {
        var seen = Set<String>([record.name.lowercased()])
        var out: [String] = []
        for name in record.aliases + record.synonyms where seen.insert(name.lowercased()).inserted {
            out.append(name)
        }
        return Array(out.prefix(14))
    }

    private var relatedSection: some View {
        Section("Related Characters") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 44, maximum: 56), spacing: 6)], spacing: 6) {
                ForEach(relatedRecords) { related in
                    Button {
                        model.selection = related.codePoint
                    } label: {
                        GlyphView(record: related, pointSize: 24)
                            .frame(width: 44, height: 40)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .help(related.titleCasedName + "  " + CodeFormats.codePoint(related.codePoint))
                    .accessibilityLabel(CharacterInfo.accessibilityLabel(for: related))
                    .contextMenu { CharacterContextMenu(record: related) }
                }
            }
        }
    }
}

// MARK: - Preview

/// Large preview. Visible characters are drawn in the opened font file (or the font chosen in Settings); blank ones as
/// an em box with a ruler.
struct GlyphPreview: View {
    @Environment(AppModel.self) private var model
    @AppStorage(SettingsKey.previewFont) private var fontName = ""
    let record: CharacterRecord

    var body: some View {
        if CharacterInfo.isInvisible(record) {
            InvisibleGlyphView(record: record, fontName: fontName)
        } else {
            let custom = model.customFont
            let missing = custom.map { !$0.contains(record.scalar) } ?? false
            if custom == nil || missing, !GlyphCoverage.hasGlyph(record.scalar, fontName: fontName) {
                NoGlyphBox()
                    .frame(width: 64, height: 88)
                    .frame(maxWidth: .infinity)
                    .frame(height: 130)
                    .accessibilityElement()
                    .accessibilityLabel(CharacterInfo.accessibilityLabel(for: record))
            } else {
                Text(CharacterInfo.displayString(for: record))
                    .font(GlyphView.font(custom: custom, missing: missing, fontName: fontName, size: 96))
                    .minimumScaleFactor(0.3)
                    .lineLimit(1)
                    .opacity(missing ? GlyphView.missingOpacity : 1)
                    .frame(maxWidth: .infinity)
                    .frame(height: 130)
                    .background { if missing { MissingGlyphBox() } }
                    .textSelection(.enabled)
                    .accessibilityLabel(CharacterInfo.accessibilityLabel(for: record))
            }
        }
    }
}

/// Shows how wide a "blank" character is: the dashed square is 1 em; the filled bar is the character's advance.
/// A thin space, a hair space and a no-break space look identical in text but not here.
struct InvisibleGlyphView: View {
    @Environment(AppModel.self) private var model
    let record: CharacterRecord
    let fontName: String
    @State private var advance: CGFloat?
    @State private var measured = false

    var body: some View {
        VStack(spacing: 6) {
            Canvas { context, size in
                let em = min(size.width, size.height) * 0.9
                let box = CGRect(x: (size.width - em) / 2, y: (size.height - em) / 2, width: em, height: em)
                context.stroke(Path(roundedRect: box, cornerRadius: 6), with: .color(.secondary), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                // Baseline
                var baseline = Path()
                baseline.move(to: CGPoint(x: box.minX, y: box.minY + em * 0.8))
                baseline.addLine(to: CGPoint(x: box.maxX, y: box.minY + em * 0.8))
                context.stroke(baseline, with: .color(.secondary.opacity(0.4)), lineWidth: 0.5)

                guard let advance else { return }
                if advance > 0.001 {
                    let bar = CGRect(x: box.minX, y: box.minY + em * 0.8 - 5, width: max(2, em * advance), height: 10)
                    context.fill(Path(roundedRect: bar, cornerRadius: 2), with: .color(.accentColor))
                } else {
                    var marker = Path()
                    marker.move(to: CGPoint(x: box.minX, y: box.minY + em * 0.15))
                    marker.addLine(to: CGPoint(x: box.minX, y: box.minY + em * 0.85))
                    context.stroke(marker, with: .color(.accentColor), lineWidth: 2)
                }
            }
            .frame(width: 130, height: 130)

            Text(widthDescription)
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(missing ? 8 : 0)
        .background { if missing { MissingGlyphBox() } }
        .task(id: "\(fontName)-\(model.customFont?.id.uuidString ?? "")") {
            if let font = model.customFont, font.contains(record.scalar) {
                advance = AdvanceCache.shared.advanceEm(of: record.scalar, font: font)
            } else {
                advance = AdvanceCache.shared.advanceEm(of: record.scalar, fontName: fontName)
            }
            measured = true
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(CharacterInfo.accessibilityLabel(for: record))
        .accessibilityValue(widthDescription)
    }

    /// The opened font has no glyph for this character, so the width shown is the fallback font's.
    private var missing: Bool {
        guard let font = model.customFont else { return false }
        return !font.contains(record.scalar) && CharacterInfo.isSpace(record)
    }

    private var widthDescription: String {
        guard measured else { return " " }
        guard let advance else { return String(localized: "No installed font draws this character") }
        if advance < 0.001 { return String(localized: "Zero width") }
        return String(localized: "Width: \(Double(advance).formatted(.number.precision(.fractionLength(0...3)))) em")
    }
}

// MARK: - Typing

/// How to type the character with the keyboard layout that is active right now.
private struct TypingSection: View {
    @Environment(AppModel.self) private var model
    let record: CharacterRecord

    var body: some View {
        let keyboard = model.keyboard
        Section {
            if let map = keyboard.map {
                let sequences = map.sequences(for: record.string)
                if sequences.isEmpty {
                    notAvailable
                } else {
                    ForEach(sequences) { sequence in
                        SequenceView(sequence: sequence)
                    }
                }
            } else {
                Text("The active keyboard layout can't be read.")
                    .foregroundStyle(.secondary)
            }
        } header: {
            if keyboard.layoutName.isEmpty {
                Text("Typing")
            } else {
                Text("Typing on “\(keyboard.layoutName)”")
            }
        } footer: {
            if keyboard.isFallback {
                Text("The current input source has no keyboard layout of its own; showing the last Roman layout instead.")
            }
        }
    }

    @ViewBuilder
    private var notAvailable: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Not on this keyboard", systemImage: "keyboard.badge.ellipsis")
                .foregroundStyle(.secondary)
            Text("With the Unicode Hex Input keyboard, hold ⌥ and type \(UnicodeHexInput.digitGroups(for: record.codePoint).joined(separator: " ")).")
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack {
                Button("Keyboard Settings…") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                }
                Button("Character Viewer") { NSApp.orderFrontCharacterPalette(nil) }
            }
            .controlSize(.small)
        }
    }
}

struct KeyCap: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(.callout, design: .rounded).weight(.medium))
            .frame(minWidth: 26, minHeight: 26)
            .padding(.horizontal, text.count > 2 ? 6 : 0)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.separator)
            }
    }
}

/// "⌥ ⇧ K" or "⌥ E, then E".
struct SequenceView: View {
    let sequence: TypingSequence

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(sequence.steps.enumerated()), id: \.offset) { index, step in
                if index > 0 {
                    Text("then")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 3) {
                    ForEach(step.modifiers.symbols, id: \.self) { KeyCap(text: $0) }
                    KeyCap(text: step.label)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.spokenDescription(sequence))
    }

    static func spokenDescription(_ sequence: TypingSequence) -> String {
        sequence.steps.map { step in
            var parts: [String] = []
            if step.modifiers.contains(.option) { parts.append(String(localized: "Option")) }
            if step.modifiers.contains(.shift) { parts.append(String(localized: "Shift")) }
            parts.append(step.label)
            return parts.joined(separator: " ")
        }.joined(separator: String(localized: ", then "))
    }
}

// MARK: - Fonts

/// Stylistic alternates for the character in the chosen font, and which installed fonts can draw it at all.
private struct FontSection: View {
    @Environment(AppModel.self) private var model
    @AppStorage(SettingsKey.previewFont) private var fontName = ""
    let record: CharacterRecord

    @State private var alternates: [GlyphAlternate] = []
    @State private var families: [String]?

    /// True when a font file is open and has no glyph for this character.
    private var missingInOpenedFont: Bool {
        guard let font = model.customFont else { return false }
        return !font.contains(record.scalar)
    }

    var body: some View {
        if !CharacterInfo.isInvisible(record) {
            Section("Font Alternates") {
                if alternates.isEmpty {
                    Text(missingInOpenedFont
                         ? LocalizedStringKey("This character is not in the opened font.")
                         : LocalizedStringKey("This font has no alternate forms of this character."))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 84, maximum: 120), spacing: 8)], spacing: 8) {
                        ForEach(alternates) { alternate in
                            VStack(spacing: 2) {
                                Text(CharacterInfo.displayString(for: record))
                                    .font(Font(alternate.font(size: 34)))
                                    .frame(height: 44)
                                Text(alternate.selectorName)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(6)
                            .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .help(alternate.featureName)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("\(alternate.featureName), \(alternate.selectorName)")
                        }
                    }
                }
            }
            .task(id: "\(record.codePoint)-\(fontName)-\(model.customFont?.id.uuidString ?? "")") {
                let scalar = record.scalar
                let installedName = fontName
                let opened = model.customFont
                alternates = await Task.detached(priority: .utility) { () -> [GlyphAlternate] in
                    if let opened {
                        return opened.contains(scalar) ? GlyphInspector.alternates(for: scalar, base: opened.ctFont(size: 48)) : []
                    }
                    return GlyphInspector.alternates(for: scalar, fontName: installedName)
                }.value
            }
        }

        Section("Installed Fonts") {
            if let families {
                if families.isEmpty {
                    Label("No installed font has this character.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                } else {
                    DisclosureGroup("In \(families.count) font families") {
                        Text(families.joined(separator: ", "))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .task(id: record.codePoint) {
            families = nil
            let scalar = record.scalar
            families = await Task.detached(priority: .utility) {
                GlyphInspector.families(containing: scalar)
            }.value
        }
    }
}
