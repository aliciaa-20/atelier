import Carbon.HIToolbox

/// Global shortcuts via Carbon's `RegisterEventHotKey`: works while another
/// app is frontmost, needs no permission, and adds no dependency (the
/// reference app used the third-party `HotKey` package). Registered only
/// while the setting and the tab are both on. A key another app already
/// owns simply fails to register and is skipped.
///
/// Keys: ⌃⌥P play/pause, ⌃⌥↑ faster, ⌃⌥↓ slower. Deliberately not
/// ⌃⌥Space (macOS's input-source shortcut) or bare ⌘↑/⌘↓ (they'd break
/// text editing everywhere).
@MainActor
final class GlobalHotkeys {
    enum Action: UInt32 {
        case playPause = 1
        case faster = 2
        case slower = 3
    }

    static let shared = GlobalHotkeys()

    private var handler: ((Action) -> Void)?
    private var hotKeyRefs: [EventHotKeyRef] = []
    private var eventHandlerRef: EventHandlerRef?
    private var isRegistered = false

    private static let signature: OSType = 0x41544C52   // 'ATLR'

    func register(handler: @escaping (Action) -> Void) {
        self.handler = handler
        guard !isRegistered else { return }
        isRegistered = true

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
            let id = hotKeyID.id
            DispatchQueue.main.async {
                MainActor.assumeIsolated { GlobalHotkeys.shared.fire(id) }
            }
            return noErr
        }, 1, &spec, nil, &eventHandlerRef)

        let modifiers = UInt32(controlKey | optionKey)
        let keys: [(Action, Int)] = [
            (.playPause, kVK_ANSI_P),
            (.faster, kVK_UpArrow),
            (.slower, kVK_DownArrow)
        ]
        for (action, keyCode) in keys {
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: Self.signature, id: action.rawValue)
            if RegisterEventHotKey(UInt32(keyCode), modifiers, id, GetApplicationEventTarget(), 0, &ref) == noErr,
               let ref {
                hotKeyRefs.append(ref)
            }
        }
    }

    func unregister() {
        guard isRegistered else { return }
        hotKeyRefs.forEach { UnregisterEventHotKey($0) }
        hotKeyRefs.removeAll()
        if let eventHandlerRef { RemoveEventHandler(eventHandlerRef) }
        eventHandlerRef = nil
        handler = nil
        isRegistered = false
    }

    private func fire(_ id: UInt32) {
        guard let action = Action(rawValue: id) else { return }
        handler?(action)
    }
}
