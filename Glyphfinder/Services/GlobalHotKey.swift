import Carbon
import Foundation

/// A system-wide keyboard shortcut. SwiftUI has no API for global shortcuts, so this wraps the Carbon
/// `RegisterEventHotKey` call (the same one Spotlight-style utilities and the KeyboardShortcuts package use).
/// It works inside the App Sandbox and needs no Accessibility permission.
final class GlobalHotKey {
    var onTrigger: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    func register(_ preset: HotKeyPreset) {
        unregister()
        guard let registration = preset.registration else { return }

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installed = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async { hotKey.onTrigger?() }
                return noErr
            },
            1,
            &spec,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )
        guard installed == noErr else { return }

        let identifier = EventHotKeyID(signature: OSType(0x4746_4E44), id: 1)  // 'GFND'
        RegisterEventHotKey(registration.keyCode, registration.modifiers, identifier, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
        if let handlerRef { RemoveEventHandler(handlerRef) }
        handlerRef = nil
    }

    deinit { unregister() }
}
