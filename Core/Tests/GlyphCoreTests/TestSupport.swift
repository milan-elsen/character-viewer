import Foundation
import XCTest
@testable import GlyphCore

enum TestSupport {
    /// Data/characters.json, found relative to this file (Core/Tests/GlyphCoreTests/TestSupport.swift).
    static let dataURL: URL = {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { url.deleteLastPathComponent() }
        return url.appendingPathComponent("Data/characters.json")
    }()

    static let database: CharacterDatabase = {
        do { return try CharacterDatabase(contentsOf: dataURL) }
        catch { fatalError("Cannot load \(dataURL.path): \(error)") }
    }()

    static let engine = SearchEngine(database: database)
}

extension SearchEngine {
    /// Code points of the first `n` results.
    func top(_ query: String, _ n: Int = 5) -> [UInt32] {
        Array(search(query, limit: n).map(\.codePoint))
    }
}

func cp(_ s: String) -> UInt32 { s.unicodeScalars.first!.value }
