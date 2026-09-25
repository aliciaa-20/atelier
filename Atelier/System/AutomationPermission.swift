import AppKit
import CoreServices

/// Automation (Apple Events) TCC helper for Spotify. Unlike Camera/Calendar,
/// macOS only reveals this permission by asking about a *running* target, so
/// this never queries while Spotify is closed (Invariant 2: never launch
/// Spotify unprompted) and reports `.targetNotRunning` instead.
enum AutomationPermission {
    enum Status {
        case granted, denied, notDetermined, targetNotRunning
    }

    private nonisolated static let spotifyBundleID = "com.spotify.client"

    private nonisolated static var spotifyIsRunning: Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == spotifyBundleID }
    }

    /// `askUser: false` only reads the current answer; `true` may show the
    /// system prompt and blocks until it's answered, so call it off the main
    /// thread (`requestSpotifyAccess`).
    nonisolated static func spotifyStatus(askUser: Bool = false) -> Status {
        guard spotifyIsRunning else { return .targetNotRunning }

        var target = AEAddressDesc()
        let created = spotifyBundleID.withCString {
            AECreateDesc(DescType(typeApplicationBundleID), $0, strlen($0), &target)
        }
        guard created == noErr else { return .targetNotRunning }
        defer { AEDisposeDesc(&target) }

        let result = AEDeterminePermissionToAutomateTarget(
            &target, AEEventClass(typeWildCard), AEEventID(typeWildCard), askUser
        )
        switch result {
        case noErr: return .granted
        case OSStatus(errAEEventNotPermitted): return .denied
        case OSStatus(errAEEventWouldRequireUserConsent): return .notDetermined
        default: return .targetNotRunning
        }
    }

    static func requestSpotifyAccess() async {
        await Task.detached { _ = spotifyStatus(askUser: true) }.value
    }

    static func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") else { return }
        NSWorkspace.shared.open(url)
    }
}
