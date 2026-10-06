import AppKit
import Carbon
import Foundation
import Observation

/// Keeps a reverse map of the active keyboard layout and rebuilds it when the user switches input source.
@MainActor
@Observable
final class KeyboardService {
    private(set) var map: KeyboardMap?
    private(set) var layoutName = ""
    /// True when the active input source has no layout of its own and an ASCII layout is used instead.
    private(set) var isFallback = false

    @ObservationIgnored private var observer: NSObjectProtocol?
    @ObservationIgnored private var activationObserver: NSObjectProtocol?

    init() {
        refresh()
        observeActivation()
        observer = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // The system updates its "current layout" slightly after posting the notification.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                MainActor.assumeIsolated { self?.refresh() }
            }
        }
    }

    // Safety net: the input source can change while the app is in the background.
    private func observeActivation() {
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func refresh() {
        guard let layout = SystemKeyboardLayout() else {
            map = nil
            layoutName = ""
            isFallback = false
            return
        }
        map = KeyboardMap(provider: layout)
        layoutName = layout.name
        isFallback = layout.isFallback
    }
}
