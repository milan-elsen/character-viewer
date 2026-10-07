#if canImport(CoreText)
import CoreText
import CoreGraphics
import Foundation

/// A stylistic variant of a character that a font offers through an OpenType/AAT feature
/// (stylistic sets, alternates, small caps ...).
struct GlyphAlternate: Identifiable, @unchecked Sendable {
    let id: String
    /// For example "Stylistic Alternatives".
    let featureName: String
    /// For example "Stylistic Set 3".
    let selectorName: String

    private let base: CTFont
    private let typeID: Int
    private let selectorID: Int

    init(id: String, featureName: String, selectorName: String, base: CTFont, typeID: Int, selectorID: Int) {
        self.id = id
        self.featureName = featureName
        self.selectorName = selectorName
        self.base = base
        self.typeID = typeID
        self.selectorID = selectorID
    }

    /// The base font with this feature switched on, at the given size.
    func font(size: CGFloat) -> CTFont {
        GlyphInspector.variant(of: base, size: size, typeID: typeID, selectorID: selectorID)
    }
}

enum FontFileError: LocalizedError {
    case notAFont

    var errorDescription: String? {
        String(localized: "This file is not a font that macOS can read.")
    }
}

/// A font opened from a file. It is read into memory and used for drawing only; it is never installed.
final class LoadedFont: Identifiable, @unchecked Sendable {
    let id = UUID()
    let displayName: String
    let glyphCount: Int

    private let graphicsFont: CGFont
    private let characters: CFCharacterSet

    init(data: Data) throws {
        let graphics: CGFont
        if let provider = CGDataProvider(data: data as CFData), let direct = CGFont(provider) {
            graphics = direct
        } else if let descriptors = CTFontManagerCreateFontDescriptorsFromData(data as CFData) as? [CTFontDescriptor],
                  let first = descriptors.first {
            // Font collections (.ttc / .otc): use the first font in the file.
            graphics = CTFontCopyGraphicsFont(CTFontCreateWithFontDescriptor(first, 12, nil), nil)
        } else {
            throw FontFileError.notAFont
        }
        graphicsFont = graphics

        let font = CTFontCreateWithGraphicsFont(graphics, 12, nil, nil)
        let fullName = CTFontCopyFullName(font) as String
        displayName = fullName.isEmpty ? (CTFontCopyFamilyName(font) as String) : fullName
        characters = CTFontCopyCharacterSet(font)
        glyphCount = graphics.numberOfGlyphs
    }

    func ctFont(size: CGFloat) -> CTFont {
        CTFontCreateWithGraphicsFont(graphicsFont, size, nil, nil)
    }

    /// Whether the font has a glyph for the character (as opposed to drawing it with a fallback font).
    func contains(_ scalar: Unicode.Scalar) -> Bool {
        CFCharacterSetIsLongCharacterMember(characters, scalar.value)
    }
}

/// CoreText queries about how a character looks in installed or opened fonts.
enum GlyphInspector {
    static func baseFont(named name: String?, size: CGFloat) -> CTFont {
        if let name, !name.isEmpty {
            return CTFontCreateWithName(name as CFString, size, nil)
        }
        return CTFontCreateUIFontForLanguage(.system, size, nil) ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
    }

    // MARK: Width

    /// Advance width of the character in em units, or nil if no font draws it.
    static func advanceEm(of scalar: Unicode.Scalar, fontName: String?) -> CGFloat? {
        advanceEm(of: scalar, baseFont: baseFont(named: fontName, size: 100), allowFallback: true)
    }

    /// - Parameter allowFallback: when false, only glyphs the font itself has are measured.
    static func advanceEm(of scalar: Unicode.Scalar, baseFont: CTFont, allowFallback: Bool) -> CGFloat? {
        let size: CGFloat = 100
        var font = CTFontCreateCopyWithAttributes(baseFont, size, nil, nil)
        let string = String(scalar)
        let units = Array(string.utf16)
        var utf16 = units
        var glyphs = [CGGlyph](repeating: 0, count: units.count)
        if !CTFontGetGlyphsForCharacters(font, &utf16, &glyphs, units.count) {
            guard allowFallback else { return nil }
            font = CTFontCreateForString(font, string as CFString, CFRange(location: 0, length: units.count))
            utf16 = units
            glyphs = [CGGlyph](repeating: 0, count: units.count)
            guard CTFontGetGlyphsForCharacters(font, &utf16, &glyphs, units.count) else { return nil }
        }
        let advance = CTFontGetAdvancesForGlyphs(font, .horizontal, glyphs, nil, 1)
        return CGFloat(advance) / size
    }

    // MARK: Alternates

    private static func shapedGlyphs(_ string: String, font: CTFont) -> [CGGlyph] {
        let attributes: [NSAttributedString.Key: Any] = [NSAttributedString.Key(rawValue: kCTFontAttributeName as String): font]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: attributes))
        guard let runs = CTLineGetGlyphRuns(line) as? [CTRun] else { return [] }
        var out: [CGGlyph] = []
        for run in runs {
            let count = CTRunGetGlyphCount(run)
            guard count > 0 else { continue }
            var glyphs = [CGGlyph](repeating: 0, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
            out.append(contentsOf: glyphs)
        }
        return out
    }

    /// `base` with one feature selector switched on. Works for installed fonts and for fonts opened from a file.
    static func variant(of base: CTFont, size: CGFloat, typeID: Int, selectorID: Int) -> CTFont {
        let setting: [String: Any] = [
            kCTFontFeatureTypeIdentifierKey as String: typeID,
            kCTFontFeatureSelectorIdentifierKey as String: selectorID,
        ]
        let attributes: [String: Any] = [kCTFontFeatureSettingsAttribute as String: [setting]]
        let descriptor = CTFontDescriptorCreateWithAttributes(attributes as CFDictionary)
        return CTFontCreateCopyWithAttributes(base, size, nil, descriptor)
    }

    static func alternates(for scalar: Unicode.Scalar, fontName: String?, limit: Int = 12) -> [GlyphAlternate] {
        alternates(for: scalar, base: baseFont(named: fontName, size: 48), limit: limit)
    }

    /// Variants of `scalar` reachable through the font's features. Each feature selector is switched on in turn, and
    /// the result is kept when it shapes to a different glyph than the default.
    static func alternates(for scalar: Unicode.Scalar, base: CTFont, limit: Int = 12) -> [GlyphAlternate] {
        let size: CGFloat = 48
        let sized = CTFontCreateCopyWithAttributes(base, size, nil, nil)
        let string = String(scalar)
        let baseGlyphs = shapedGlyphs(string, font: sized)
        guard !baseGlyphs.isEmpty, baseGlyphs != [0] else { return [] }
        guard let features = CTFontCopyFeatures(sized) as? [[String: Any]] else { return [] }

        var seen: Set<[CGGlyph]> = [baseGlyphs]
        var out: [GlyphAlternate] = []
        for feature in features {
            guard let typeID = feature[kCTFontFeatureTypeIdentifierKey as String] as? Int,
                  let selectors = feature[kCTFontFeatureTypeSelectorsKey as String] as? [[String: Any]] else { continue }
            let featureName = feature[kCTFontFeatureTypeNameKey as String] as? String ?? ""
            for selector in selectors {
                guard let selectorID = selector[kCTFontFeatureSelectorIdentifierKey as String] as? Int else { continue }
                let font = variant(of: sized, size: size, typeID: typeID, selectorID: selectorID)
                let glyphs = shapedGlyphs(string, font: font)
                guard glyphs != [0], !glyphs.isEmpty, !seen.contains(glyphs) else { continue }
                seen.insert(glyphs)
                let selectorName = selector[kCTFontFeatureSelectorNameKey as String] as? String ?? ""
                out.append(GlyphAlternate(
                    id: "\(typeID)-\(selectorID)",
                    featureName: featureName,
                    selectorName: selectorName,
                    base: sized,
                    typeID: typeID,
                    selectorID: selectorID
                ))
                if out.count >= limit { return out }
            }
        }
        return out
    }

    // MARK: Coverage

    static func installedFamilies() -> [String] {
        let families = CTFontManagerCopyAvailableFontFamilyNames() as? [String] ?? []
        return families.filter { !$0.hasPrefix(".") }.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Installed font families that have a glyph for the character.
    static func families(containing scalar: Unicode.Scalar) -> [String] {
        installedFamilies().filter { family in
            let font = CTFontCreateWithName(family as CFString, 12, nil)
            return CFCharacterSetIsLongCharacterMember(CTFontCopyCharacterSet(font), scalar.value)
        }
    }
}

/// Remembers glyph advances (in em) so the grid can draw the width of many spaces while scrolling
/// without asking CoreText again for every cell on every redraw.
final class AdvanceCache: @unchecked Sendable {
    static let shared = AdvanceCache()

    private struct Key: Hashable {
        let codePoint: UInt32
        let font: String
    }

    private let lock = NSLock()
    private var storage: [Key: CGFloat] = [:]
    private static let missing: CGFloat = -1

    /// Advance width in em in an installed font (empty name: the system font), or nil when no font draws it.
    func advanceEm(of scalar: Unicode.Scalar, fontName: String) -> CGFloat? {
        value(Key(codePoint: scalar.value, font: "installed:" + fontName)) {
            GlyphInspector.advanceEm(of: scalar, fontName: fontName)
        }
    }

    /// Advance width in em in a font opened from a file, or nil when that font has no glyph for the character.
    func advanceEm(of scalar: Unicode.Scalar, font: LoadedFont) -> CGFloat? {
        value(Key(codePoint: scalar.value, font: "file:" + font.id.uuidString)) {
            GlyphInspector.advanceEm(of: scalar, baseFont: font.ctFont(size: 100), allowFallback: false)
        }
    }

    private func value(_ key: Key, compute: () -> CGFloat?) -> CGFloat? {
        lock.lock()
        if let cached = storage[key] {
            lock.unlock()
            return cached == Self.missing ? nil : cached
        }
        lock.unlock()

        let measured = compute()
        lock.lock()
        storage[key] = measured ?? Self.missing
        lock.unlock()
        return measured
    }
}
#endif
