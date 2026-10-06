import Carbon
import SwiftUI

/// Window ids shared between the scenes and the code that opens them.
enum SceneID {
    static let main = "main"
    static let quick = "quick"
}

/// UserDefaults keys. Views read them with `@AppStorage`.
enum SettingsKey {
    static let hotKey = "hotKeyPreset"
    static let showInDock = "showInDock"
    static let showMenuBarItem = "showMenuBarItem"
    static let showInspector = "showInspector"
    static let closeQuickAfterCopy = "closeQuickLookupAfterCopy"
    static let autoPaste = "pasteAutomatically"
    static let previewFont = "previewFontName"
    static let gridCellSize = "gridCellSize"
    static let favorites = "favoriteCodePoints"
    static let recents = "recentCodePoints"
    static let lastSidebar = "lastSidebarItem"
}

/// Global shortcuts that open Quick Lookup. A fixed list (rather than a free-form recorder) keeps this a pure
/// SwiftUI `Picker`; every entry avoids shortcuts macOS uses itself.
enum HotKeyPreset: String, CaseIterable, Identifiable {
    case controlOptionSpace
    case controlOptionCommandSpace
    case controlOptionCommandU
    case controlOptionCommandG
    case off

    static let `default`: HotKeyPreset = .controlOptionSpace

    var id: String { rawValue }

    var display: String {
        switch self {
        case .controlOptionSpace: return "⌃⌥Space"
        case .controlOptionCommandSpace: return "⌃⌥⌘Space"
        case .controlOptionCommandU: return "⌃⌥⌘U"
        case .controlOptionCommandG: return "⌃⌥⌘G"
        case .off: return ""
        }
    }

    /// Virtual key code and Carbon modifier mask, or nil for "off".
    var registration: (keyCode: UInt32, modifiers: UInt32)? {
        let control = UInt32(controlKey), option = UInt32(optionKey), command = UInt32(cmdKey)
        switch self {
        case .controlOptionSpace: return (UInt32(kVK_Space), control | option)
        case .controlOptionCommandSpace: return (UInt32(kVK_Space), control | option | command)
        case .controlOptionCommandU: return (UInt32(kVK_ANSI_U), control | option | command)
        case .controlOptionCommandG: return (UInt32(kVK_ANSI_G), control | option | command)
        case .off: return nil
        }
    }

    static var stored: HotKeyPreset {
        HotKeyPreset(rawValue: UserDefaults.standard.string(forKey: SettingsKey.hotKey) ?? "") ?? .default
    }
}

enum GlyphSize {
    static let range: ClosedRange<Double> = 64...144
    static let `default`: Double = 88
}
