import AppKit

/// The few things SwiftUI's `App` cannot express: Dock-click behavior and the Dock/menu-bar-only activation policy.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.applyActivationPolicy()
        AppModel.shared.registerHotKey()
        statusItemController = StatusItemController(model: AppModel.shared)
    }

    /// Clicking the Dock icon when every window is closed brings the main window back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { AppModel.shared.showMainWindow() }
        return true
    }

    /// The app lives on in the menu bar and answers the global shortcut after its windows are closed.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// The Dock icon and ⌘Tab entry are shown when "Always show in Dock" is on, and otherwise only while the main
    /// window is open. With neither, the app is a menu bar utility (no Dock icon, no app menu bar).
    static func applyActivationPolicy() {
        let policy: NSApplication.ActivationPolicy =
            SettingsKey.alwaysShowInDock || AppModel.shared.mainWindowOpen ? .regular : .accessory
        guard NSApp.activationPolicy() != policy else { return }
        NSApp.setActivationPolicy(policy)
        if policy == .regular { NSApp.activate() }
    }
}
