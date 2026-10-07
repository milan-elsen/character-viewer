import ServiceManagement
import AppKit
import SwiftUI

/// Settings window (⌘,). Tabs follow the macOS convention of a toolbar-style tab bar.
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            AppearanceSettings()
                .tabItem { Label("Characters", systemImage: "textformat") }
            KeyboardSettings()
                .tabItem { Label("Keyboard", systemImage: "keyboard") }
        }
        .frame(width: 520)
        .scenePadding()
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @Environment(AppModel.self) private var model
    @AppStorage(SettingsKey.hotKey) private var hotKey = HotKeyPreset.default.rawValue
    @AppStorage(SettingsKey.showInDock) private var showInDock = true
    @AppStorage(SettingsKey.showMenuBarItem) private var showMenuBarItem = true
    @AppStorage(SettingsKey.closeQuickAfterCopy) private var closeAfterCopy = true
    @AppStorage(SettingsKey.autoPaste) private var autoPaste = false

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginItemError: String?

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: launchAtLoginBinding)
                Toggle("Always show in Dock", isOn: $showInDock)
                Toggle("Show in menu bar", isOn: $showMenuBarItem)
            } header: {
                Text("Startup")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if !showInDock {
                        Text("The Dock icon appears only while the main window is open.")
                    }
                    if !showInDock && !showMenuBarItem {
                        Text("With both turned off, open Quick Lookup with its keyboard shortcut.")
                    }
                    if let loginItemError {
                        Text(loginItemError).foregroundStyle(.red)
                    }
                }
            }

            Section {
                Picker("Keyboard shortcut", selection: $hotKey) {
                    ForEach(HotKeyPreset.allCases) { preset in
                        if preset == .off {
                            Text("Off").tag(preset.rawValue)
                        } else {
                            Text(preset.display).tag(preset.rawValue)
                        }
                    }
                }
                Toggle("Close after copying", isOn: $closeAfterCopy)
                if Inserter.canPasteAutomatically {
                    Toggle("Paste into the previous app", isOn: $autoPaste)
                }
            } header: {
                Text("Quick Lookup")
            } footer: {
                if Inserter.canPasteAutomatically {
                    Text("Pasting needs permission under System Settings › Privacy & Security › Accessibility.")
                } else {
                    Text("Characters are copied to the clipboard. Press ⌘V in your document to paste.")
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: hotKey) { _, _ in model.registerHotKey() }
        .onChange(of: showInDock) { _, _ in AppDelegate.applyActivationPolicy() }
        .onAppear { launchAtLogin = SMAppService.mainApp.status == .enabled }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin },
            set: { newValue in
                do {
                    if newValue {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                    loginItemError = nil
                } catch {
                    loginItemError = error.localizedDescription
                }
                launchAtLogin = SMAppService.mainApp.status == .enabled
            }
        )
    }
}

// MARK: - Characters

private struct AppearanceSettings: View {
    @Environment(AppModel.self) private var model
    @AppStorage(SettingsKey.previewFont) private var fontName = ""
    @AppStorage(SettingsKey.gridCellSize) private var cellSize = GlyphSize.default
    @State private var families: [String] = []

    var body: some View {
        Form {
            Section {
                Picker("Font", selection: $fontName) {
                    Text("System Font").tag("")
                    ForEach(families, id: \.self) { family in
                        Text(family).tag(family)
                    }
                }
                LabeledContent("Glyph size") {
                    Slider(value: $cellSize, in: GlyphSize.range, step: 8)
                        .frame(width: 180)
                }
                HStack {
                    Text(verbatim: "AaÆæ Ωω €½ ‘’ “” – —")
                        .font(GlyphView.font(named: fontName, size: 22))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } header: {
                Text("Display")
            } footer: {
                Text("The font is used for previews and to look for alternate forms of a character.")
            }

            Section("History") {
                Button("Clear Recents", role: .destructive) { model.clearRecents() }
                    .disabled(model.recents.isEmpty)
            }
        }
        .formStyle(.grouped)
        .task { families = GlyphInspector.installedFamilies() }
    }
}

// MARK: - Keyboard

private struct KeyboardSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section {
                LabeledContent("Current layout", value: model.keyboard.layoutName.isEmpty ? "—" : model.keyboard.layoutName)
                if let map = model.keyboard.map {
                    LabeledContent("Characters you can type", value: map.typeableCount.formatted())
                }
            } header: {
                Text("Active Keyboard")
            } footer: {
                Text("Typing instructions follow the keyboard layout you are using right now and update when you switch input sources.")
            }

            Section {
                Button("Open Keyboard Settings…") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                }
                Button("Open Character Viewer") { NSApp.orderFrontCharacterPalette(nil) }
            } header: {
                Text("Other Ways to Type")
            } footer: {
                Text("Add “Unicode Hex Input” under Input Sources to type any character by holding ⌥ and entering its code.")
            }
        }
        .formStyle(.grouped)
    }
}
