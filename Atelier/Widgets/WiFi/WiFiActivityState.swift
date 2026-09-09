/// A Wi-Fi connectivity change worth surfacing in the notch. Pure -- no
/// Network import -- so the dedup logic is unit-testable independent of
/// `WiFiSource`'s actual `NWPathMonitor` callbacks.
///
/// Connectivity only, not the network name: reading the SSID via CoreWLAN
/// requires Location Services authorization (a whole new permission grant,
/// like `AccessibilityPermission`) -- out of scope for this toast. See
/// `docs/decisions/` for why this widget doesn't ask for that permission.
///
/// Event-shaped, not ambient status, same reasoning as `BatteryActivityState`'s
/// own doc comment contrasts it with: a one-shot toast for the moment of
/// change. `WiFiSource` is responsible for clearing it back to `nil` shortly
/// after publishing.
enum WiFiActivityState: Equatable {
    case connected
    case disconnected

    /// `nil` means "nothing worth surfacing" -- either connectivity didn't
    /// actually change, or there was never a prior reading to compare
    /// against (the startup case, where `previouslyConnected` is `nil`).
    static func evaluate(isConnected: Bool, previouslyConnected: Bool?) -> WiFiActivityState? {
        guard let previouslyConnected, previouslyConnected != isConnected else { return nil }
        return isConnected ? .connected : .disconnected
    }
}
