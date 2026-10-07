import XCTest
@testable import GlyphCore

final class DatabaseTests: XCTestCase {
    let db = TestSupport.database

    func testHasTensOfThousandsOfCharacters() {
        XCTAssertGreaterThan(db.count, 30_000)
    }

    func testRecordsAreSortedAndUnique() {
        let cps = db.records.map(\.codePoint)
        XCTAssertEqual(cps, cps.sorted())
        XCTAssertEqual(Set(cps).count, cps.count)
        for r in db.records { XCTAssertNotNil(Unicode.Scalar(r.codePoint), "U+\(String(r.codePoint, radix: 16)) is not a scalar") }
    }

    func testEmojiAreExcluded() {
        // Emoji presentation characters.
        for scalar in [0x1F600, 0x1F680, 0x1F355, 0x2705, 0x274C, 0x1F1E9, 0x1F3FB, 0x231A, 0x1F4A9] as [UInt32] {
            XCTAssertNil(db.record(for: scalar), "U+\(String(scalar, radix: 16, uppercase: true)) is an emoji")
        }
        // Text-style symbols stay.
        for scalar in [0x00A9, 0x2122, 0x2665, 0x2194, 0x2713, 0x263A, 0x2603] as [UInt32] {
            XCTAssertNotNil(db.record(for: scalar), "U+\(String(scalar, radix: 16, uppercase: true)) should be kept")
        }
    }

    func testSpacesAndInvisiblesAreIncluded() {
        for scalar in [0x00A0, 0x2000, 0x2001, 0x2002, 0x2003, 0x2004, 0x2005, 0x2006, 0x2007, 0x2008, 0x2009, 0x200A,
                       0x200B, 0x200C, 0x200D, 0x202F, 0x205F, 0x2060, 0x3000, 0xFEFF, 0x00AD, 0xFE0F, 0x034F, 0x200E, 0x200F] as [UInt32] {
            XCTAssertNotNil(db.record(for: scalar), "U+\(String(scalar, radix: 16, uppercase: true)) missing")
        }
        XCTAssertEqual(db.record(for: 0x2009)?.name, "THIN SPACE")
        XCTAssertEqual(db.record(for: 0x2009)?.category, "Zs")
    }

    func testAppleLogoIsPresent() {
        XCTAssertEqual(db.record(for: 0xF8FF)?.name, "APPLE LOGO")
    }

    func testNoCJKIdeographsOrHangulSyllables() {
        XCTAssertNil(db.record(for: 0x4E00))
        XCTAssertNil(db.record(for: 0xAC00))
        XCTAssertNil(db.record(for: 0xF900))
    }

    func testTitleCasedNames() {
        XCTAssertEqual(db.record(for: 0x00A0)?.titleCasedName, "No-Break Space")
        XCTAssertEqual(db.record(for: 0x2009)?.titleCasedName, "Thin Space")
        XCTAssertEqual(db.record(for: 0x00E9)?.titleCasedName, "Latin Small Letter E With Acute")
        XCTAssertEqual(db.record(for: 0x0030)?.titleCasedName, "Digit Zero")
        for r in db.records.prefix(2000) { XCTAssertEqual(r.titleCasedName, r.name.localizedCapitalized, r.name) }
    }

    func testBlocksAndScripts() {
        let r = db.record(for: 0x2009)!
        XCTAssertEqual(db.blockName(of: r), "General Punctuation")
        XCTAssertEqual(db.scriptName(of: db.record(for: 0x0041)!), "Latin")
        XCTAssertEqual(db.scriptName(of: db.record(for: 0x03B1)!), "Greek")
    }

    func testControlCharactersGetReadableNames() {
        XCTAssertEqual(db.record(for: 0x0009)?.name, "CHARACTER TABULATION")
        XCTAssertEqual(db.record(for: 0x0000)?.name, "NULL")
    }

    func testCollections() throws {
        let spaces = try XCTUnwrap(db.collection(id: "spaces"))
        XCTAssertTrue(spaces.contains(0x2009))
        XCTAssertTrue(spaces.contains(0x00A0))
        XCTAssertTrue(spaces.contains(0x200D))
        let dashes = try XCTUnwrap(db.collection(id: "dashes"))
        XCTAssertTrue(dashes.contains(0x2014))
        XCTAssertTrue(dashes.contains(0x2212))
        XCTAssertGreaterThan(db.records(in: spaces).count, 20)
        for id in ["quotes", "math", "arrows", "currency", "typography", "keyboard"] {
            XCTAssertNotNil(db.collection(id: id), id)
        }
    }

    func testRelatedCharactersAreInTheDatabase() {
        for r in db.records.prefix(5000) {
            for rel in r.related { XCTAssertNotNil(db.record(for: rel)) }
            XCTAssertFalse(r.related.contains(r.codePoint))
        }
        // Apostrophe-like characters are related to the right single quotation mark.
        let q = db.record(for: 0x2019)!
        XCTAssertTrue(q.related.contains(0x0027) || q.related.contains(0x02BC))
    }

    func testHTMLEntitiesAndLegacyTables() {
        XCTAssertEqual(db.htmlEntity(for: 0x2009), "thinsp")
        XCTAssertEqual(db.htmlEntity(for: 0x00A0), "nbsp")
        XCTAssertEqual(db.codePoint(forEntity: "eacute"), 0x00E9)
        XCTAssertEqual(db.macRomanByte(for: 0x00E9), 142)
        XCTAssertEqual(db.windows1252Byte(for: 0x00E9), 233)
        XCTAssertEqual(db.windows1252Byte(for: 0x20AC), 128)
    }
}
