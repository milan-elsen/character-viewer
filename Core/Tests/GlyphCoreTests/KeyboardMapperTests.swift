import XCTest
@testable import GlyphCore

/// A tiny US-like layout: enough keys to exercise modifiers and dead keys.
private struct FakeUSLayout: KeyboardLayoutProvider {
    let name = "Fake US"
    let keyCodes: [UInt16] = [0, 14, 19, 40, 49, 36, 24, 27]  // A, E, 2, K, Space, Return, =, -

    func keyCapLabel(keyCode: UInt16) -> String {
        switch keyCode {
        case 0: return "A"
        case 14: return "E"
        case 19: return "2"
        case 40: return "K"
        case 49: return "Space"
        case 36: return "Return"
        case 24: return "="
        case 27: return "-"
        default: return "?"
        }
    }

    func translate(keyCode: UInt16, modifiers: KeyModifiers, deadKeyState: UInt32) -> KeyTranslation {
        if deadKeyState == 1 {  // after ⌥E (acute)
            switch (keyCode, modifiers) {
            case (14, []): return .text("é")
            case (14, .shift): return .text("É")
            case (0, []): return .text("á")
            case (49, []): return .text("´")
            default: return .none
            }
        }
        switch (keyCode, modifiers) {
        case (0, []): return .text("a")
        case (0, .shift): return .text("A")
        case (0, .option): return .text("å")
        case (14, []): return .text("e")
        case (14, .shift): return .text("E")
        case (14, .option): return .dead(state: 1)
        case (19, []): return .text("2")
        case (19, .shift): return .text("@")
        case (19, .option): return .text("™")
        case (40, []): return .text("k")
        case (40, [.shift, .option]): return .text("\u{F8FF}")
        case (49, []): return .text(" ")
        case (49, .option): return .text("\u{00A0}")
        case (36, _): return .text("\r")
        case (24, []): return .text("=")
        case (24, .option): return .text("≠")
        case (27, []): return .text("-")
        case (27, .option): return .text("–")
        case (27, [.shift, .option]): return .text("—")
        default: return .none
        }
    }
}

final class KeyboardMapperTests: XCTestCase {
    let map = KeyboardMap(provider: FakeUSLayout())

    func testSingleStrokeCharacters() {
        let at = map.sequences(for: "@")
        XCTAssertEqual(at.count, 1)
        XCTAssertEqual(at[0].steps, [KeyStroke(keyCode: 19, modifiers: .shift, label: "2")])

        let tm = map.sequences(for: "™")
        XCTAssertEqual(tm[0].steps.first?.modifiers, .option)
        XCTAssertEqual(tm[0].steps.first?.label, "2")

        let apple = map.sequences(for: "\u{F8FF}")
        XCTAssertEqual(apple[0].steps.first?.modifiers, [.shift, .option])
        XCTAssertEqual(apple[0].steps.first?.label, "K")
    }

    func testDashesAndSpaces() {
        XCTAssertEqual(map.sequences(for: "–").first?.steps.first?.modifiers, .option)
        XCTAssertEqual(map.sequences(for: "—").first?.steps.first?.modifiers, [.shift, .option])
        XCTAssertEqual(map.sequences(for: "\u{00A0}").first?.steps.first?.label, "Space")
    }

    func testDeadKeySequences() throws {
        let e = try XCTUnwrap(map.sequences(for: "é").first)
        XCTAssertEqual(e.steps.count, 2)
        XCTAssertEqual(e.steps[0], KeyStroke(keyCode: 14, modifiers: .option, label: "E"))
        XCTAssertEqual(e.steps[1], KeyStroke(keyCode: 14, modifiers: [], label: "E"))
        XCTAssertTrue(e.isDeadKeySequence)

        let a = try XCTUnwrap(map.sequences(for: "á").first)
        XCTAssertEqual(a.steps[1].label, "A")
        XCTAssertEqual(map.sequences(for: "´").first?.steps.last?.label, "Space")
    }

    func testDecomposedInputIsNormalised() {
        XCTAssertTrue(map.canType("e\u{0301}"))
    }

    func testControlCharactersAreNotTypeable() {
        XCTAssertFalse(map.canType("\r"))
    }

    func testUnavailableCharacters() {
        XCTAssertFalse(map.canType("€"))
        XCTAssertTrue(map.sequences(for: "€").isEmpty)
    }

    func testSimplestSequenceWinsAndCapsAtLimit() {
        let seqs = map.sequences(for: "a", limit: 1)
        XCTAssertEqual(seqs.count, 1)
        XCTAssertEqual(seqs[0].steps.count, 1)
        XCTAssertEqual(seqs[0].steps[0].modifiers, [])
    }

    func testModifierSymbols() {
        XCTAssertEqual(KeyModifiers([.shift, .option]).symbols, ["⌥", "⇧"])
    }
}
