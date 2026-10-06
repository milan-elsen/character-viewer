import XCTest
@testable import GlyphCore

final class SearchTests: XCTestCase {
    let engine = TestSupport.engine

    /// `query` must return `expected` within the first `within` results.
    private func assertFinds(_ query: String, _ expected: UInt32, within: Int = 1, file: StaticString = #filePath, line: UInt = #line) {
        let top = engine.top(query, within)
        XCTAssertTrue(top.contains(expected),
                      "“\(query)” should find U+\(String(expected, radix: 16, uppercase: true)) in the top \(within); got \(top.map { String($0, radix: 16, uppercase: true) })",
                      file: file, line: line)
    }

    // MARK: Spaces and invisibles
    func testSpaces() {
        assertFinds("thin space", 0x2009)
        assertFinds("hair space", 0x200A)
        assertFinds("nbsp", 0x00A0)
        assertFinds("non breaking space", 0x00A0, within: 2)
        assertFinds("narrow no-break space", 0x202F)
        assertFinds("narrow nbsp", 0x202F)
        assertFinds("en space", 0x2002)
        assertFinds("em space", 0x2003)
        assertFinds("figure space", 0x2007)
        assertFinds("zero width joiner", 0x200D)
        assertFinds("zwj", 0x200D)
        assertFinds("zero width space", 0x200B)
        assertFinds("soft hyphen", 0x00AD)
        assertFinds("byte order mark", 0xFEFF)
        assertFinds("ideographic space", 0x3000)
    }

    // MARK: Typography
    func testDashesAndQuotes() {
        assertFinds("em dash", 0x2014)
        assertFinds("en dash", 0x2013)
        assertFinds("long dash", 0x2014, within: 3)
        assertFinds("minus sign", 0x2212)
        assertFinds("curly apostrophe", 0x2019, within: 3)
        assertFinds("smart quote", 0x201C, within: 6)
        assertFinds("left double quote", 0x201C)
        assertFinds("right single quote", 0x2019)
        assertFinds("guillemets", 0x00AB, within: 3)
        assertFinds("ellipsis", 0x2026)
        assertFinds("bullet", 0x2022, within: 3)
        assertFinds("pilcrow", 0x00B6)
        assertFinds("section sign", 0x00A7)
    }

    func testSymbols() {
        assertFinds("euro", 0x20AC)
        assertFinds("copyright", 0x00A9)
        assertFinds("trademark", 0x2122)
        assertFinds("registered", 0x00AE, within: 2)
        assertFinds("degree", 0x00B0, within: 3)
        assertFinds("infinity", 0x221E)
        assertFinds("square root", 0x221A)
        assertFinds("approximately equal", 0x2248, within: 3)
        assertFinds("not equal", 0x2260, within: 3)
        assertFinds("plus minus", 0x00B1, within: 2)
        assertFinds("multiplication sign", 0x00D7)
        assertFinds("check mark", 0x2713, within: 3)
        assertFinds("right arrow", 0x2192, within: 3)
        assertFinds("command key", 0x2318, within: 3)
        assertFinds("apple logo", 0xF8FF)
        assertFinds("pi", 0x03C0, within: 3)
        assertFinds("heart", 0x2665, within: 6)
    }

    func testLetters() {
        assertFinds("e acute", 0x00E9, within: 3)
        assertFinds("ñ", 0x00F1, within: 3)
        assertFinds("sharp s", 0x00DF, within: 2)
        assertFinds("eszett", 0x00DF, within: 2)
        assertFinds("o with stroke", 0x00F8, within: 3)
        assertFinds("latin small letter e with acute", 0x00E9)
        assertFinds("c cedilla", 0x00E7, within: 3)
        assertFinds("thorn", 0x00FE, within: 3)
    }

    // MARK: Other languages
    func testDutchAndGermanTerms() {
        assertFinds("gedachtestreepje", 0x2013, within: 2)
        assertFinds("Geviertstrich", 0x2014, within: 2)
        assertFinds("harde spatie", 0x00A0, within: 3)
        assertFinds("paragraafteken", 0x00A7, within: 2)
        assertFinds("pijl rechts", 0x2192, within: 3)
        assertFinds("euroteken", 0x20AC, within: 2)
    }

    // MARK: Tolerance
    func testTyposAndPrefixes() {
        assertFinds("ellpsis", 0x2026, within: 3)
        assertFinds("apostroph", 0x2019, within: 5)
        assertFinds("thn space", 0x2009, within: 3)
        assertFinds("quotation", 0x201C, within: 20)
        assertFinds("THIN   SPACE", 0x2009)
        assertFinds("  thin space  ", 0x2009)
    }

    func testEverydayWordsForUnicodeTerms() {
        assertFinds("backwards question mark", 0x2E2E, within: 3)
        assertFinds("o umlaut", 0x00F6, within: 3)
        assertFinds("a umlaut", 0x00E4, within: 3)
        assertFinds("upside down exclamation mark", 0x00A1, within: 2)
        assertFinds("line break", 0x000A, within: 4)
        assertFinds("invisible", 0x200B, within: 3)
        assertFinds("tick", 0x2713, within: 4)
    }

    func testNaturalLanguageQueries() {
        assertFinds("the space that is narrower than a normal one", 0x2009, within: 12)
        assertFinds("i need an invisible character", 0x200B, within: 25)
        assertFinds("spanish upside down question mark", 0x00BF, within: 3)
        assertFinds("the long dash", 0x2014, within: 3)
    }

    // MARK: Exact input
    func testCodePointInput() {
        XCTAssertEqual(engine.top("U+2009", 1), [0x2009])
        XCTAssertEqual(engine.top("u+20ac", 1), [0x20AC])
        XCTAssertEqual(engine.top("0x2009", 1), [0x2009])
        XCTAssertEqual(engine.top("\\u2009", 1), [0x2009])
        XCTAssertEqual(engine.top("\\u{2009}", 1), [0x2009])
        XCTAssertEqual(engine.top("&thinsp;", 1), [0x2009])
        XCTAssertEqual(engine.top("&#8201;", 1), [0x2009])
        XCTAssertEqual(engine.top("&#x2009;", 1), [0x2009])
        XCTAssertEqual(engine.top("2009", 1), [0x2009])
        XCTAssertEqual(engine.top("8364", 1).first, 0x20AC, "decimal fallback when the hex reading does not exist")
        XCTAssertEqual(engine.top("U+2009 U+200A", 2), [0x2009, 0x200A])
    }

    func testPastedCharacters() {
        XCTAssertEqual(engine.top("€", 1), [0x20AC])
        XCTAssertEqual(engine.top("\u{2009}", 1), [0x2009], "a pasted thin space must be identified")
        XCTAssertEqual(engine.top("\u{00A0}", 1), [0x00A0])
        XCTAssertEqual(engine.top("é", 1), [0x00E9])
        XCTAssertEqual(engine.top("—", 1), [0x2014])
        XCTAssertEqual(engine.top("a", 1), [0x0061])
        XCTAssertEqual(Array(engine.top("‘’", 2)), [0x2018, 0x2019])
    }

    func testEmptyAndUnknownQueries() {
        XCTAssertTrue(engine.search("").isEmpty)
        XCTAssertTrue(engine.search("qqqqqqqqzzzzzz").isEmpty)
    }

    func testEmojiQueriesDoNotReturnEmoji() {
        let top = engine.search("grinning face", limit: 50).map(\.codePoint)
        XCTAssertFalse(top.contains(0x1F600))
        let rocket = engine.search("rocket", limit: 50).map(\.codePoint)
        XCTAssertFalse(rocket.contains(0x1F680))
    }

    func testBoostsReorderResults() {
        let plain = engine.search("space", limit: 30)
        let target = plain.last!.codePoint
        let boosted = engine.search("space", limit: 30, boosts: [target: 10_000])
        XCTAssertEqual(boosted.first?.codePoint, target)
    }

    func testSearchIsFast() {
        measure {
            for q in ["thin space", "quotation", "arrow left", "ellpsis", "zzzz yyyy"] { _ = engine.search(q) }
        }
    }

    func testEditDistance() {
        XCTAssertEqual(SearchEngine.editDistance(Array("ellipsis"), Array("ellpsis"), limit: 2), 1)
        XCTAssertEqual(SearchEngine.editDistance(Array("space"), Array("spcae"), limit: 2), 1)
        XCTAssertGreaterThan(SearchEngine.editDistance(Array("abc"), Array("xyz"), limit: 1), 1)
    }
}
