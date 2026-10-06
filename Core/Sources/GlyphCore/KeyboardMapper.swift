import Foundation

/// Modifier keys that take part in typing characters. (⌃ and ⌘ produce shortcuts and control codes, not text.)
struct KeyModifiers: OptionSet, Hashable, Sendable {
    let rawValue: Int
    static let shift = KeyModifiers(rawValue: 1 << 0)
    static let option = KeyModifiers(rawValue: 1 << 1)

    /// The symbols in the order macOS shows them (⌥⇧).
    var symbols: [String] {
        var out: [String] = []
        if contains(.option) { out.append("⌥") }
        if contains(.shift) { out.append("⇧") }
        return out
    }

    var count: Int { symbols.count }
}

/// The result of pressing one key on a keyboard layout.
enum KeyTranslation: Equatable, Sendable {
    /// The key types nothing (in this state).
    case none
    /// The key types text.
    case text(String)
    /// The key is a dead key (like ⌥E on a US keyboard). `state` identifies the pending accent.
    case dead(state: UInt32)
}

/// Anything that can say what a key press produces: the real macOS layout, or a fake one in tests.
protocol KeyboardLayoutProvider {
    var name: String { get }
    /// Virtual key codes to try, in the order they should be preferred.
    var keyCodes: [UInt16] { get }
    func translate(keyCode: UInt16, modifiers: KeyModifiers, deadKeyState: UInt32) -> KeyTranslation
    /// What is printed on the key cap (without modifiers), for example "E", "Space", "Return".
    func keyCapLabel(keyCode: UInt16) -> String
}

/// One key press: modifiers plus a key.
struct KeyStroke: Hashable, Sendable {
    let keyCode: UInt16
    let modifiers: KeyModifiers
    /// Label printed on the key cap.
    let label: String
}

/// How to produce a character: one stroke, or a dead key followed by a second stroke.
struct TypingSequence: Hashable, Sendable, Identifiable {
    let steps: [KeyStroke]
    var id: String { steps.map { "\($0.keyCode):\($0.modifiers.rawValue)" }.joined(separator: ">") }
    var isDeadKeySequence: Bool { steps.count > 1 }

    /// Lower is simpler: fewer strokes, fewer modifiers.
    var cost: Int {
        steps.reduce(0) { $0 + 10 + $1.modifiers.count * 3 } + (isDeadKeySequence ? 5 : 0)
    }
}

/// Reverse map of a keyboard layout: character -> the key sequences that type it.
final class KeyboardMap: @unchecked Sendable {
    let layoutName: String
    private var table: [String: [TypingSequence]] = [:]

    private static let modifierSets: [KeyModifiers] = [[], .shift, .option, [.shift, .option]]

    init(provider: KeyboardLayoutProvider) {
        layoutName = provider.name
        let codes = provider.keyCodes
        var labels: [UInt16: String] = [:]
        for code in codes { labels[code] = provider.keyCapLabel(keyCode: code) }

        var deadKeys: [(stroke: KeyStroke, state: UInt32)] = []

        for code in codes {
            for mods in Self.modifierSets {
                switch provider.translate(keyCode: code, modifiers: mods, deadKeyState: 0) {
                case .text(let s):
                    guard Self.isTypeable(s) else { continue }
                    add(s, TypingSequence(steps: [KeyStroke(keyCode: code, modifiers: mods, label: labels[code] ?? "")]))
                case .dead(let state):
                    deadKeys.append((KeyStroke(keyCode: code, modifiers: mods, label: labels[code] ?? ""), state))
                case .none:
                    break
                }
            }
        }

        // Second pass: every key pressed after each dead key.
        for dead in deadKeys {
            for code in codes {
                for mods in Self.modifierSets {
                    if case .text(let s) = provider.translate(keyCode: code, modifiers: mods, deadKeyState: dead.state),
                       Self.isTypeable(s) {
                        let second = KeyStroke(keyCode: code, modifiers: mods, label: labels[code] ?? "")
                        add(s, TypingSequence(steps: [dead.stroke, second]))
                    }
                }
            }
        }

        for key in table.keys {
            table[key]?.sort { a, b in
                a.cost == b.cost ? (a.steps.first?.keyCode ?? 0) < (b.steps.first?.keyCode ?? 0) : a.cost < b.cost
            }
        }
    }

    private static func isTypeable(_ s: String) -> Bool {
        guard let first = s.unicodeScalars.first else { return false }
        // Skip control characters: Return, Tab, Delete, Escape ...
        return !(first.value < 0x20 || (0x7F...0x9F).contains(first.value))
    }

    private func add(_ s: String, _ seq: TypingSequence) {
        let key = s.precomposedStringWithCanonicalMapping
        var list = table[key, default: []]
        if !list.contains(seq) { list.append(seq) }
        table[key] = list
    }

    /// The simplest sequences that type `string` (up to `limit`), best first.
    func sequences(for string: String, limit: Int = 3) -> [TypingSequence] {
        Array((table[string.precomposedStringWithCanonicalMapping] ?? []).prefix(limit))
    }

    /// Whether the layout can type the character at all without extra tools.
    func canType(_ string: String) -> Bool { !sequences(for: string, limit: 1).isEmpty }

    /// Number of distinct characters this layout can type.
    var typeableCount: Int { table.count }
}
