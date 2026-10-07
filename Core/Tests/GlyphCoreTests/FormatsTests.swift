import XCTest
@testable import GlyphCore

final class FormatsTests: XCTestCase {
    let db = TestSupport.database

    private func value(_ id: String, _ cp: UInt32) -> String? {
        let r = db.record(for: cp)!
        return CodeFormats.formats(for: r, database: db).first { $0.id == id }?.value
    }

    func testThinSpace() {
        XCTAssertEqual(value("codepoint", 0x2009), "U+2009")
        XCTAssertEqual(value("decimal", 0x2009), "8201")
        XCTAssertEqual(value("utf8", 0x2009), "E2 80 89")
        XCTAssertEqual(value("utf16", 0x2009), "2009")
        XCTAssertEqual(value("html-named", 0x2009), "&thinsp;")
        XCTAssertEqual(value("html-dec", 0x2009), "&#8201;")
        XCTAssertEqual(value("html-hex", 0x2009), "&#x2009;")
        XCTAssertEqual(value("css", 0x2009), "\\2009")
        XCTAssertEqual(value("swift", 0x2009), "\\u{2009}")
        XCTAssertEqual(value("javascript", 0x2009), "\\u2009")
        XCTAssertEqual(value("url", 0x2009), "%E2%80%89")
    }

    func testSupplementaryPlane() {
        let treble: UInt32 = 0x1D11E
        XCTAssertNotNil(db.record(for: treble))
        XCTAssertEqual(value("utf16", treble), "D834 DD1E")
        XCTAssertEqual(value("utf8", treble), "F0 9D 84 9E")
        XCTAssertEqual(value("javascript", treble), "\\u{1D11E}")
        XCTAssertEqual(value("python", treble), "\\U0001D11E")
        XCTAssertEqual(value("json", treble), "\\uD834\\uDD1E")
    }

    func testLegacyEncodings() {
        XCTAssertEqual(value("ascii", 0x41), "65  (0x41)")
        XCTAssertNil(value("ascii", 0xE9))
        XCTAssertEqual(value("latin1", 0xE9), "233  (0xE9)")
        XCTAssertEqual(value("macroman", 0xE9), "142  (0x8E)")
        XCTAssertEqual(value("win1252", 0xE9), "233  (Alt+0233)")
        XCTAssertEqual(value("win1252", 0x20AC), "128  (Alt+0128)")
        XCTAssertNil(value("macroman", 0x2009))
    }

    func testInvisibleDetection() {
        XCTAssertTrue(CharacterInfo.isInvisible(db.record(for: 0x2009)!))
        XCTAssertTrue(CharacterInfo.isInvisible(db.record(for: 0x200D)!))
        XCTAssertTrue(CharacterInfo.isInvisible(db.record(for: 0xFE0F)!))
        XCTAssertFalse(CharacterInfo.isInvisible(db.record(for: 0x0041)!))
        XCTAssertEqual(CharacterInfo.shortLabel(for: db.record(for: 0x00A0)!), "NBSP")
        XCTAssertEqual(CharacterInfo.shortLabel(for: db.record(for: 0x200D)!), "ZWJ")
        XCTAssertTrue(CharacterInfo.isCombining(db.record(for: 0x0301)!))
        XCTAssertEqual(CharacterInfo.displayString(for: db.record(for: 0x0301)!), "\u{25CC}\u{0301}")
    }

    func testOnlySpacesGetTheWidthMark() {
        for cp: UInt32 in [0x0020, 0x00A0, 0x2002, 0x2003, 0x2009, 0x200A, 0x202F, 0x205F, 0x3000] {
            XCTAssertTrue(CharacterInfo.isSpace(db.record(for: cp)!), "U+\(String(cp, radix: 16)) is a space")
        }
        // Invisible, but not spaces: these keep the dashed box.
        for cp: UInt32 in [0x200B, 0x200C, 0x200D, 0x2060, 0xFEFF, 0x00AD, 0x200E, 0xFE0F, 0x3164, 0x2800, 0x0009] {
            let record = db.record(for: cp)!
            XCTAssertFalse(CharacterInfo.isSpace(record), "U+\(String(cp, radix: 16)) is not a space")
            XCTAssertTrue(CharacterInfo.isInvisible(record))
        }
    }

    func testHexInputGroups() {
        XCTAssertEqual(UnicodeHexInput.digitGroups(for: 0x2009), ["2009"])
        XCTAssertEqual(UnicodeHexInput.digitGroups(for: 0x1D11E), ["D834", "DD1E"])
    }
}
