import SwiftUI

@main
struct TypecaseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel.shared

    init() {
        AppModel.shared.start()
    }

    var body: some Scene {
        // Main window: sidebar, character grid and inspector.
        Window("Typecase", id: SceneID.main) {
            MainView()
                .environment(model)
        }
        .defaultSize(width: 1080, height: 700)
        .commands { AppCommands(model: model) }

        // Quick Lookup: a small floating window opened with the global shortcut.
        Window("Quick Lookup", id: SceneID.quick) {
            QuickLookupView()
                .environment(model)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .windowLevel(.floating)
        .windowBackgroundDragBehavior(.enabled)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}
