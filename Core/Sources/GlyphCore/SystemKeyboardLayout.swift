#if os(macOS)
import Carbon
import Foundation

/// The keyboard layout that is active right now, read through Text Input Sources and `UCKeyTranslate`.
/// This is plain Carbon/CoreFoundation code. Apple offers no SwiftUI or AppKit API for it.
final class SystemKeyboardLayout: KeyboardLayoutProvider {
    let name: String
    /// True when the current input source has no layout of its own (for example a Japanese input method), so the
    /// last ASCII-capable layout is used instead.
    let isFallback: Bool
    let keyCodes: [UInt16]

    private let layoutData: CFData
    private let keyboardType: UInt32

    /// Keypad keys duplicate the main keyboard's digits and symbols, so they are left out.
    private static let keypadKeyCodes: Set<UInt16> = [65, 67, 69, 71, 75, 76, 78, 81, 82, 83, 84, 85, 86, 87, 88, 89, 91, 92, 95]

    init?() {
        var source = TISCopyCurrentKeyboardLayoutInputSource().takeRetainedValue()
        var fallback = false
        if TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) == nil {
            source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource().takeRetainedValue()
            fallback = true
        }
        guard let dataPointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        layoutData = Unmanaged<CFData>.fromOpaque(dataPointer).takeUnretainedValue()
        isFallback = fallback

        if let namePointer = TISGetInputSourceProperty(source, kTISPropertyLocalizedName) {
            name = Unmanaged<CFString>.fromOpaque(namePointer).takeUnretainedValue() as String
        } else {
            name = "Keyboard"
        }
        keyboardType = UInt32(LMGetKbdType())
        keyCodes = (0..<127).map { UInt16($0) }.filter { !Self.keypadKeyCodes.contains($0) }
    }

    func translate(keyCode: UInt16, modifiers: KeyModifiers, deadKeyState: UInt32) -> KeyTranslation {
        var carbonModifiers: UInt32 = 0
        if modifiers.contains(.shift) { carbonModifiers |= UInt32(shiftKey >> 8) }
        if modifiers.contains(.option) { carbonModifiers |= UInt32(optionKey >> 8) }

        var state = deadKeyState
        var length = 0
        var buffer = [UniChar](repeating: 0, count: 8)
        let layout = UnsafeRawPointer(CFDataGetBytePtr(layoutData)).assumingMemoryBound(to: UCKeyboardLayout.self)
        let status = UCKeyTranslate(
            layout,
            keyCode,
            UInt16(kUCKeyActionDown),
            carbonModifiers,
            keyboardType,
            OptionBits(0),
            &state,
            buffer.count,
            &length,
            &buffer
        )
        guard status == noErr else { return .none }
        if length > 0 {
            return .text(String(utf16CodeUnits: buffer, count: length))
        }
        return state != 0 ? .dead(state: state) : .none
    }

    func keyCapLabel(keyCode: UInt16) -> String {
        switch keyCode {
        case 49: return "Space"
        case 36: return "Return"
        case 48: return "Tab"
        case 51: return "Delete"
        case 53: return "Esc"
        case 117: return "⌦"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default: break
        }
        switch translate(keyCode: keyCode, modifiers: [], deadKeyState: 0) {
        case .text(let s):
            let upper = s.uppercased()
            return upper.count == 1 ? upper : s
        case .dead(let state):
            // The visible accent is what this dead key types when followed by Space.
            if case .text(let accent) = translate(keyCode: 49, modifiers: [], deadKeyState: state) { return accent }
            return "?"
        case .none:
            return "?"
        }
    }
}
#endif
