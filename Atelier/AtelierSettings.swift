import Foundation

/// Small `UserDefaults`-backed settings, checked directly rather than
/// injected — there's no dedicated Settings window yet (planned for a
/// later phase), just a menu-bar toggle. Registers its own defaults so a
/// fresh install starts with peek enabled rather than reading `false`.
enum AtelierSettings {
    static let peekOnTrackChangeKey = "peekOnTrackChangeEnabled"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [peekOnTrackChangeKey: true])
    }

    static var peekOnTrackChangeEnabled: Bool {
        UserDefaults.standard.bool(forKey: peekOnTrackChangeKey)
    }
}
