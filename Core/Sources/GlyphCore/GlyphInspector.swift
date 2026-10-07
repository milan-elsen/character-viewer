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
    let descriptor: CTFontDescriptor

    func font(size: CGFloat) -> CTFont {
        CTFontCreateWithFontDescriptor(descriptor, size, nil)
    }
}

/// CoreText queries about how a character looks in installed fonts.
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
        let size: CGFloat = 100
        var font = baseFont(named: fontName, size: size)
        let string = String(scalar)
        let units = Array(string.utf16)
        var utf16 = units
        var glyphs = [CGGlyph](repeating: 0, count: units.count)
        if !CTFontGetGlyphsForCharacters(font, &utf16, &glyphs, units.count) {
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

    /// Variants of `scalar` reachable through the font's features. Each feature selector is switched on in turn, and
    /// the result is kept when it shapes to a different glyph than the default.
    static func alternates(for scalar: Unicode.Scalar, fontName: String?, limit: Int = 12) -> [GlyphAlternate] {
        let size: CGFloat = 48
        let base = baseFont(named: fontName, size: size)
        let string = String(scalar)
        let baseGlyphs = shapedGlyphs(string, font: base)
        guard !baseGlyphs.isEmpty, baseGlyphs != [0] else { return [] }
        guard let features = CTFontCopyFeatures(base) as? [[String: Any]] else { return [] }
        let baseDescriptor = CTFontCopyFontDescriptor(base)

        var seen: Set<[CGGlyph]> = [baseGlyphs]
        var out: [GlyphAlternate] = []
        for feature in features {
            guard let typeID = feature[kCTFontFeatureTypeIdentifierKey as String] as? Int,
                  let selectors = feature[kCTFontFeatureTypeSelectorsKey as String] as? [[String: Any]] else { continue }
            let featureName = feature[kCTFontFeatureTypeNameKey as String] as? String ?? ""
            for selector in selectors {
                guard let selectorID = selector[kCTFontFeatureSelectorIdentifierKey as String] as? Int else { continue }
                let descriptor = CTFontDescriptorCreateCopyWithFeature(baseDescriptor, typeID as CFNumber, selectorID as CFNumber)
                let font = CTFontCreateWithFontDescriptor(descriptor, size, nil)
                let glyphs = shapedGlyphs(string, font: font)
                guard glyphs != [0], !glyphs.isEmpty, !seen.contains(glyphs) else { continue }
                seen.insert(glyphs)
                let selectorName = selector[kCTFontFeatureSelectorNameKey as String] as? String ?? ""
                out.append(GlyphAlternate(id: "\(typeID)-\(selectorID)", featureName: featureName, selectorName: selectorName, descriptor: descriptor))
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

/// Remembers glyph advances (in em) so the grid can draw the width of many blank characters while scrolling
/// without asking CoreText again for every cell on every redraw.
final class AdvanceCache: @unchecked Sendable {
    static let shared = AdvanceCache()

    private struct Key: Hashable {
        let codePoint: UInt32
        let fontName: String
    }

    private let lock = NSLock()
    private var storage: [Key: CGFloat] = [:]
    private static let missing: CGFloat = -1

    /// Advance width in em, or nil when no installed font draws the character.
    func advanceEm(of scalar: Unicode.Scalar, fontName: String) -> CGFloat? {
        let key = Key(codePoint: scalar.value, fontName: fontName)
        lock.lock()
        if let cached = storage[key] {
            lock.unlock()
            return cached == Self.missing ? nil : cached
        }
        lock.unlock()

        let measured = GlyphInspector.advanceEm(of: scalar, fontName: fontName)
        lock.lock()
        storage[key] = measured ?? Self.missing
        lock.unlock()
        return measured
    }
}
#endif
