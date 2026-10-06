import Foundation

enum CharacterDatabaseError: Error {
    case unsupportedVersion(Int)
}

/// In-memory character database. Loading ~32k records takes well under a second, so there is no need for
/// SQLite: everything stays in plain Swift value types and is trivially testable.
final class CharacterDatabase: @unchecked Sendable {
    let records: [CharacterRecord]
    let blockNames: [String]
    let scriptNames: [String]
    let ageNames: [String]
    let collections: [CharacterCollection]
    let unicodeVersion: String

    private let indexByCodePoint: [UInt32: Int]
    private let htmlEntities: [UInt32: String]
    private let entityToCodePoint: [String: UInt32]
    private let macRoman: [UInt32: UInt8]
    private let windows1252: [UInt32: UInt8]

    // MARK: Loading

    private struct File: Decodable {
        let version: Int
        let unicodeVersion: String
        let blocks: [String]
        let scripts: [String]
        let ages: [String]
        let collections: [CollectionRow]
        let entities: [String: String]
        let legacy: [String: [String: Int]]
        let characters: [CharacterRecord]
    }

    private struct CollectionRow: Decodable {
        let id: String
        let symbol: String
        let ranges: [[UInt32]]
    }

    convenience init(contentsOf url: URL) throws {
        try self.init(data: Data(contentsOf: url, options: .mappedIfSafe))
    }

    init(data: Data) throws {
        let file = try JSONDecoder().decode(File.self, from: data)
        guard file.version == 1 else { throw CharacterDatabaseError.unsupportedVersion(file.version) }
        records = file.characters
        blockNames = file.blocks
        scriptNames = file.scripts
        ageNames = file.ages
        unicodeVersion = file.unicodeVersion
        collections = file.collections.map { row in
            CharacterCollection(
                id: row.id,
                symbol: row.symbol,
                ranges: row.ranges.compactMap { $0.count == 2 ? $0[0]...$0[1] : nil }
            )
        }
        var index: [UInt32: Int] = [:]
        index.reserveCapacity(file.characters.count)
        for (i, r) in file.characters.enumerated() { index[r.codePoint] = i }
        indexByCodePoint = index

        var entities: [UInt32: String] = [:]
        var reverse: [String: UInt32] = [:]
        for (k, v) in file.entities {
            if let cp = UInt32(k) {
                entities[cp] = v
                reverse[v] = cp
            }
        }
        htmlEntities = entities
        entityToCodePoint = reverse

        func table(_ key: String) -> [UInt32: UInt8] {
            var t: [UInt32: UInt8] = [:]
            for (k, v) in file.legacy[key] ?? [:] {
                if let cp = UInt32(k), let b = UInt8(exactly: v) { t[cp] = b }
            }
            return t
        }
        macRoman = table("macRoman")
        windows1252 = table("windows1252")
    }

    // MARK: Lookup

    var count: Int { records.count }

    func record(for codePoint: UInt32) -> CharacterRecord? {
        indexByCodePoint[codePoint].map { records[$0] }
    }

    func index(of codePoint: UInt32) -> Int? { indexByCodePoint[codePoint] }

    func records(for codePoints: [UInt32]) -> [CharacterRecord] {
        codePoints.compactMap(record(for:))
    }

    func blockName(of record: CharacterRecord) -> String { blockNames[record.blockIndex] }
    func scriptName(of record: CharacterRecord) -> String { scriptNames[record.scriptIndex] }
    func ageName(of record: CharacterRecord) -> String { ageNames[record.ageIndex] }

    var blocks: [CharacterBlock] {
        blockNames.enumerated().map { CharacterBlock(index: $0.offset, name: $0.element) }
    }

    /// Blocks that actually contain at least one included character, in code point order.
    lazy var populatedBlocks: [CharacterBlock] = {
        var seen = Set<Int>()
        var out: [CharacterBlock] = []
        for r in records where seen.insert(r.blockIndex).inserted {
            out.append(CharacterBlock(index: r.blockIndex, name: blockNames[r.blockIndex]))
        }
        return out
    }()

    func records(inBlock index: Int) -> [CharacterRecord] {
        records.filter { $0.blockIndex == index }
    }

    func records(in collection: CharacterCollection) -> [CharacterRecord] {
        records.filter { collection.contains($0.codePoint) }
    }

    func collection(id: String) -> CharacterCollection? {
        collections.first { $0.id == id }
    }

    // MARK: Encodings

    func htmlEntity(for codePoint: UInt32) -> String? { htmlEntities[codePoint] }
    func codePoint(forEntity name: String) -> UInt32? { entityToCodePoint[name] }
    func macRomanByte(for codePoint: UInt32) -> UInt8? { macRoman[codePoint] }
    func windows1252Byte(for codePoint: UInt32) -> UInt8? { windows1252[codePoint] }
}
