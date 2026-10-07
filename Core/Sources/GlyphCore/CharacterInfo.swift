import Foundation

/// Presentation helpers that depend only on the data, not on any UI framework.
enum CharacterInfo {
    /// Human readable name of a two-letter general category.
    static func categoryName(_ gc: String) -> String {
        switch gc {
        case "Lu": return "Uppercase Letter"
        case "Ll": return "Lowercase Letter"
        case "Lt": return "Titlecase Letter"
        case "Lm": return "Modifier Letter"
        case "Lo": return "Other Letter"
        case "Mn": return "Nonspacing Mark"
        case "Mc": return "Spacing Mark"
        case "Me": return "Enclosing Mark"
        case "Nd": return "Decimal Digit"
        case "Nl": return "Letter Number"
        case "No": return "Other Number"
        case "Pc": return "Connector Punctuation"
        case "Pd": return "Dash Punctuation"
        case "Ps": return "Open Punctuation"
        case "Pe": return "Close Punctuation"
        case "Pi": return "Initial Quote"
        case "Pf": return "Final Quote"
        case "Po": return "Other Punctuation"
        case "Sm": return "Math Symbol"
        case "Sc": return "Currency Symbol"
        case "Sk": return "Modifier Symbol"
        case "So": return "Other Symbol"
        case "Zs": return "Space Separator"
        case "Zl": return "Line Separator"
        case "Zp": return "Paragraph Separator"
        case "Cc": return "Control"
        case "Cf": return "Format"
        case "Co": return "Private Use"
        default: return gc
        }
    }

    /// True for characters that draw nothing (or nothing useful on their own): spaces, format and control
    /// characters, fillers, variation selectors and lone combining marks.
    static func isInvisible(_ record: CharacterRecord) -> Bool {
        switch record.category {
        case "Zs", "Zl", "Zp", "Cf", "Cc": return true
        default: break
        }
        switch record.codePoint {
        case 0x034F, 0x115F, 0x1160, 0x17B4, 0x17B5, 0x2800, 0x3164, 0xFFA0, 0x180B...0x180F, 0xFE00...0xFE0F, 0xE0100...0xE01EF:
            return true
        default:
            return false
        }
    }

    /// True for space separators (general category Zs): SPACE, NBSP, thin, hair, em, ideographic space and so on.
    /// These have a meaningful width, which the grid draws as two dotted lines. Other invisibles (joiners, marks,
    /// fillers, control characters) have no width worth showing and keep the dashed box.
    static func isSpace(_ record: CharacterRecord) -> Bool {
        record.category == "Zs"
    }

    /// True for combining marks, which need a base character to be drawn.
    static func isCombining(_ record: CharacterRecord) -> Bool {
        record.category == "Mn" || record.category == "Me" || record.category == "Mc"
    }

    /// Short label (for example "NBSP", "ZWJ", "U+2009") drawn inside the placeholder box for invisible characters.
    static func shortLabel(for record: CharacterRecord) -> String {
        let abbreviations = record.aliases.filter { alias in
            alias.count >= 2 && alias.count <= 5 && alias.allSatisfy { $0.isUppercase || $0.isNumber }
        }
        if let a = abbreviations.sorted(by: { $0.count < $1.count }).first { return a }
        return "U+" + String(record.codePoint, radix: 16, uppercase: true).leftPadded(to: 4)
    }

    /// The string used to *display* a character in a grid cell: combining marks are attached to a dotted circle
    /// so they are visible.
    static func displayString(for record: CharacterRecord) -> String {
        isCombining(record) ? "\u{25CC}" + record.string : record.string
    }

    /// Text to put in front of a character when reading the character aloud (VoiceOver).
    static func accessibilityLabel(for record: CharacterRecord) -> String {
        record.name.lowercased()
    }
}

/// How to type an arbitrary code point with the "Unicode Hex Input" keyboard (hold ⌥, type the hex digits).
enum UnicodeHexInput {
    static func digitGroups(for codePoint: UInt32) -> [String] {
        guard let scalar = Unicode.Scalar(codePoint) else { return [] }
        return String(scalar).utf16.map { CodeFormats.hex($0, width: 4) }
    }
}
