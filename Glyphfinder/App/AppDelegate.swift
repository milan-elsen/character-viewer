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

    /// "Show in Dock" off means a menu-bar-only app (no Dock icon, no app menu bar until a window is active).
    static func applyActivationPolicy() {
        let showInDock = UserDefaults.standard.object(forKey: SettingsKey.showInDock) as? Bool ?? true
        NSApp.setActivationPolicy(showInDock ? .regular : .accessory)
    }
}
