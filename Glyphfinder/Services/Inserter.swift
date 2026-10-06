import ApplicationServices
import AppKit

/// Getting a character out of the app: onto the pasteboard, and (in direct-distribution builds only) pasted into
/// the app that was in front before Quick Lookup opened.
enum Inserter {
    static func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// Automatic pasting needs the Accessibility permission, which the Mac App Store sandbox cannot grant.
    /// Builds for the App Store therefore never compile this (see `DIRECT_DISTRIBUTION` in the project settings).
    static var canPasteAutomatically: Bool {
        #if DIRECT_DISTRIBUTION
        return true
        #else
        return false
        #endif
    }

    /// Sends ⌘V to the frontmost app. Returns false (and shows the system permission prompt) when this app is not
    /// yet trusted for Accessibility.
    @discardableResult
    static func pasteIntoFrontmostApp() -> Bool {
        #if DIRECT_DISTRIBUTION
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else { return false }
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)   // "V"
        let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cgAnnotatedSessionEventTap)
        up?.post(tap: .cgAnnotatedSessionEventTap)
        return true
        #else
        return false
        #endif
    }
}
