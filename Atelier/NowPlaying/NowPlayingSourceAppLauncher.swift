import AppKit

/// Opens/activates whichever app is actually playing (`sourceBundleID`),
/// for tapping the title in `ExpandedPlayerView`. `openApplication`, not the
/// deprecated `launchApplication(withBundleIdentifier:)` -- same API
/// boring.notch's own `MusicManager.openMusicApp` uses (read via `gh api`
/// per check-reference-apps-first). Invariant 2's "don't launch a media app
/// that isn't running" doesn't apply here: this info only exists because
/// that app is already running and playing, and opening it is a deliberate
/// tap, not a background poll.
enum NowPlayingSourceAppLauncher {
    static func open(bundleID: String) {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration())
    }
}
