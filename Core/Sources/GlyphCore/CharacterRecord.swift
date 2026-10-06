import Foundation

/// One Unicode character as stored in `Data/characters.json`.
struct CharacterRecord: Identifiable, Hashable, Sendable {
    let codePoint: UInt32
    let name: String
    /// Two-letter Unicode general category, e.g. "Zs".
    let category: String
    let blockIndex: Int
    let scriptIndex: Int
    let ageIndex: Int
    /// 0 = everyday typography, 1 = other living scripts, 2 = historic / exotic. Used to rank search results.
    let priority: Int
    /// Informal and formal aliases from NamesList / NameAliases ("NBSP", "narrow space").
    let aliases: [String]
    /// Hand curated search terms.
    let synonyms: [String]
    /// CLDR keywords in several languages.
    let keywords: [String]
    let related: [UInt32]
    let notes: String

    var id: UInt32 { codePoint }

    var scalar: Unicode.Scalar { Unicode.Scalar(codePoint) ?? "\u{FFFD}" }

    /// The character as a string, ready to be copied.
    var string: String { String(Character(scalar)) }

    var titleCasedName: String { name.localizedCapitalized }
}

extension CharacterRecord: Decodable {
    // Rows are compact arrays: see `fields` in characters.json.
    init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        codePoint = try c.decode(UInt32.self)
        name = try c.decode(String.self)
        category = try c.decode(String.self)
        blockIndex = try c.decode(Int.self)
        scriptIndex = try c.decode(Int.self)
        ageIndex = try c.decode(Int.self)
        priority = try c.decode(Int.self)
        aliases = try c.decode([String].self)
        synonyms = try c.decode([String].self)
        keywords = try c.decode([String].self)
        related = try c.decode([UInt32].self)
        notes = try c.decode(String.self)
    }
}

/// A curated group of characters shown in the sidebar (Spaces, Dashes, Quotes, ...).
struct CharacterCollection: Identifiable, Hashable, Sendable {
    let id: String
    /// SF Symbol name.
    let symbol: String
    let ranges: [ClosedRange<UInt32>]

    var count: Int { ranges.reduce(0) { $0 + Int($1.upperBound - $1.lowerBound) + 1 } }

    func contains(_ cp: UInt32) -> Bool { ranges.contains { $0.contains(cp) } }
}

struct CharacterBlock: Identifiable, Hashable, Sendable {
    let index: Int
    let name: String
    var id: Int { index }
}
