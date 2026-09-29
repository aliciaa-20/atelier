import Carbon.HIToolbox

/// ⌃⌥J: join the meeting the notch is currently offering. Carbon
/// `RegisterEventHotKey` like `GlobalHotkeys` (no permission, no dependency),
/// but deliberately separate from it: that one is all-or-nothing and tied to
/// the teleprompter's settings, while this key should exist only while a
/// meeting pill/peek is up (`MeetingSource` registers/unregisters it), so it
/// never holds a shortcut the rest of the time. A key another app already owns
/// simply fails to register.
@MainActor
final class MeetingHotkey {
    static let shared = MeetingHotkey()

    private static let signature: OSType = 0x41544D4A   // 'ATMJ'

    private var handler: (() -> Void)?
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    func register(_ handler: @escaping () -> Void) {
        self.handler = handler
        guard hotKeyRef == nil else { return }

        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID
            )
            guard status == noErr else { return status }
            // Only claim our own signature -- returning noErr for another
            // feature's hotkey would swallow it (see `GlobalHotkeys`).
            guard hotKeyID.signature == MeetingHotkey.signature else { return OSStatus(eventNotHandledErr) }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { MeetingHotkey.shared.handler?() }
            }
            return noErr
        }, 1, &spec, nil, &eventHandlerRef)

        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: Self.signature, id: 1)
        if RegisterEventHotKey(UInt32(kVK_ANSI_J), UInt32(controlKey | optionKey), id, GetApplicationEventTarget(), 0, &ref) == noErr,
           let ref {
            hotKeyRef = ref
        } else {
            unregister()
        }
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
        if let eventHandlerRef { RemoveEventHandler(eventHandlerRef) }
        eventHandlerRef = nil
        handler = nil
    }
}
