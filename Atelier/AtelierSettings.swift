import Foundation

/// Small `UserDefaults`-backed settings, checked directly rather than
/// injected — there's no dedicated Settings window yet (planned for a
/// later phase), just a menu-bar toggle. Registers its own defaults so a
/// fresh install starts with peek enabled rather than reading `false`.
enum AtelierSettings {
    static let peekOnTrackChangeKey = "peekOnTrackChangeEnabled"
    static let gesturesEnabledKey = "gesturesEnabled"
    static let shelfEnabledKey = "shelfEnabled"
    static let systemMonitorEnabledKey = "systemMonitorEnabled"
    static let colorPickerEnabledKey = "colorPickerEnabled"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            peekOnTrackChangeKey: true,
            gesturesEnabledKey: true,
            shelfEnabledKey: true,
            systemMonitorEnabledKey: true,
            colorPickerEnabledKey: true
        ])
    }

    static var peekOnTrackChangeEnabled: Bool {
        UserDefaults.standard.bool(forKey: peekOnTrackChangeKey)
    }

    static var gesturesEnabled: Bool {
        UserDefaults.standard.bool(forKey: gesturesEnabledKey)
    }

    /// Gates both the Shelf tab's visibility and whether a file drag is
    /// even allowed to open it (`NotchDragModifier`'s `onDragEntered` in
    /// `NotchRootView`) -- per ADR 0011, a disabled feature shouldn't have
    /// a leftover way in via drag-and-drop just because its tab is hidden.
    static var shelfEnabled: Bool {
        UserDefaults.standard.bool(forKey: shelfEnabledKey)
    }

    /// Gates the System Monitor tab's visibility and, per the same
    /// lightweight-by-design reasoning `shelfEnabled`'s own drag-and-drop
    /// gating documents, `SystemMonitorSource`'s poll loop itself --
    /// disabled means no Mach syscalls every 4s, not just a hidden tab.
    static var systemMonitorEnabled: Bool {
        UserDefaults.standard.bool(forKey: systemMonitorEnabledKey)
    }

    /// Gates both the "Pick a Color..." menu item's visibility and
    /// `NotchController.pickColor()` itself -- same "no leftover way in
    /// once disabled" reasoning as `shelfEnabled` above, in case something
    /// else ever calls `pickColor()` besides that one menu item.
    static var colorPickerEnabled: Bool {
        UserDefaults.standard.bool(forKey: colorPickerEnabledKey)
    }
}
