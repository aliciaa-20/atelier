import Foundation

/// Small `UserDefaults`-backed settings, checked directly rather than
/// injected — there's no dedicated Settings window yet (planned for a
/// later phase), just a menu-bar toggle. Registers its own defaults so a
/// fresh install starts with peek enabled rather than reading `false`.
enum AtelierSettings {
    static let peekOnTrackChangeKey = "peekOnTrackChangeEnabled"
    static let gesturesEnabledKey = "gesturesEnabled"
    static let shelfEnabledKey = "shelfEnabled"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            peekOnTrackChangeKey: true,
            gesturesEnabledKey: true,
            shelfEnabledKey: true
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
}
