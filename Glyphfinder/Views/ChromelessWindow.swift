import AppKit
import SwiftUI

/// Hides the traffic-light buttons and the title bar chrome and makes the window transparent, so a SwiftUI view can
/// draw the whole panel
/// (Spotlight style). SwiftUI's `.hiddenTitleBar` still shows the buttons, and `.plain` windows never become key
/// (the search field would not receive typing), so this is one of the few places that needs AppKit.
struct ChromelessWindow: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { Anchor() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class Anchor: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.standardWindowButton(.closeButton)?.isHidden = true
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true
            window.styleMask.insert(.fullSizeContentView)
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.titlebarSeparatorStyle = .none
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = true
        }
    }
}
