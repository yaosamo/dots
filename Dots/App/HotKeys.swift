import AppKit
import Carbon.HIToolbox

/// System-wide shortcuts via Carbon hot keys — work from any app and need no Accessibility permission.
@MainActor
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    /// ⌃⌥, used by every Dots shortcut.
    static let modifiers = UInt32(controlKey | optionKey)
    static let modifierFlags: NSEvent.ModifierFlags = [.control, .option]
    private static let signature: OSType = 0x444F_5453 // "DOTS"

    private var actions: [UInt32: () -> Void] = [:]
    private var refs: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?

    func register(keyCode: Int, label: String, action: @escaping () -> Void) {
        installHandlerIfNeeded()
        let id = UInt32(actions.count + 1)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(keyCode), Self.modifiers, EventHotKeyID(signature: Self.signature, id: id),
            GetApplicationEventTarget(), 0, &ref
        )
        guard status == noErr, let ref else {
            Log.hotKeys.error("Failed to register \(label, privacy: .public) (status \(status)); another app may own it")
            return
        }
        refs.append(ref)
        actions[id] = action
        Log.hotKeys.debug("Registered \(label, privacy: .public)")
    }

    func unregisterAll() {
        refs.forEach { UnregisterEventHotKey($0) }
        refs = []
        actions = [:]
    }

    private func fire(_ id: UInt32) {
        actions[id]?()
    }

    private func installHandlerIfNeeded() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID
            )
            let id = hotKeyID.id
            // Carbon delivers hot keys on the main thread.
            MainActor.assumeIsolated { HotKeyCenter.shared.fire(id) }
            return noErr
        }, 1, &spec, nil, &handler)
    }
}
