import AppKit
import SwiftUI

/// Reports whether the main window is open. The Dock icon and ⌘Tab entry follow it when "Always show in Dock" is
/// off (SwiftUI has no API for this, so the window's own notifications are observed).
struct MainWindowTracker: NSViewRepresentable {
    let onChange: (Bool) -> Void

    func makeNSView(context: Context) -> NSView {
        let anchor = Anchor()
        anchor.onChange = onChange
        return anchor
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? Anchor)?.onChange = onChange
    }

    private final class Anchor: NSView {
        var onChange: ((Bool) -> Void)?
        private var observers: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            removeObservers()
            guard let window else { return }
            let center = NotificationCenter.default
            observers = [
                // A closed SwiftUI window can be shown again without its views being recreated, so "becomes main" is
                // what reports it open again.
                center.addObserver(forName: NSWindow.didBecomeMainNotification, object: window, queue: .main) { [weak self] _ in
                    self?.onChange?(true)
                },
                center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self] _ in
                    self?.onChange?(true)
                },
                center.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
                    self?.onChange?(false)
                },
            ]
            onChange?(true)
        }

        private func removeObservers() {
            observers.forEach { NotificationCenter.default.removeObserver($0) }
            observers = []
        }

        deinit { removeObservers() }
    }
}
