import AppKit
import SwiftUI

/// Hides the traffic-light buttons and the title bar chrome and makes the window transparent, so a SwiftUI view can
/// draw the whole panel
/// (Spotlight style). SwiftUI's `.hiddenTitleBar` still shows the buttons, and `.plain` windows never become key
/// (the search field would not receive typing), so this is one of the few places that needs AppKit.
struct ChromelessWindow: NSViewRepresentable {
    /// The title bar height of the last window measured. Remembered so that the next Quick Lookup opens at the right
    /// size straight away instead of resizing once.
    @MainActor static var lastMeasuredTitlebarHeight: CGFloat = 28

    /// Height the window reserves for its (hidden) title bar. With `.windowResizability(.contentSize)` the window is
    /// that much taller than the content, so the content gives the space back (see `QuickLookupView`).
    @Binding var titlebarHeight: CGFloat

    func makeNSView(context: Context) -> NSView {
        let anchor = Anchor()
        anchor.report = { titlebarHeight = $0 }
        return anchor
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? Anchor)?.report = { titlebarHeight = $0 }
    }

    private final class Anchor: NSView {
        var report: ((CGFloat) -> Void)?

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

            // The part of the window that is not content layout area is the title bar.
            DispatchQueue.main.async { [weak self, weak window] in
                guard let window else { return }
                let height = window.frame.height - window.contentLayoutRect.height
                guard height >= 0 else { return }
                MainActor.assumeIsolated { ChromelessWindow.lastMeasuredTitlebarHeight = height }
                self?.report?(height)
            }
        }
    }
}
