import AppKit

struct SpotifySource: NowPlayingSource {
    private static let bundleID = "com.spotify.client"

    var isAvailable: Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == Self.bundleID }
    }

    func fetch() async -> NowPlayingInfo? {
        guard isAvailable, let raw = AppleScriptRunner.run(Self.fetchScript) else { return nil }
        return SpotifyOutputParser.parse(raw)
    }

    func playPause() async {
        guard isAvailable else { return }
        _ = AppleScriptRunner.run(#"tell application "Spotify" to playpause"#)
    }

    func next() async {
        guard isAvailable else { return }
        _ = AppleScriptRunner.run(#"tell application "Spotify" to next track"#)
    }

    func previous() async {
        guard isAvailable else { return }
        _ = AppleScriptRunner.run(#"tell application "Spotify" to previous track"#)
    }

    func seek(to time: TimeInterval) async {
        guard isAvailable else { return }
        _ = AppleScriptRunner.run(#"tell application "Spotify" to set player position to \#(time)"#)
    }

    func toggleShuffle() async {
        guard isAvailable else { return }
        _ = AppleScriptRunner.run(#"tell application "Spotify" to set shuffling to not shuffling"#)
    }

    /// Field order must match `SpotifyOutputParser`: state, name, artist,
    /// album, duration (ms), position (seconds), artwork url, shuffling.
    /// The separator is built with `ASCII character 31` rather than typed
    /// directly, so there's no ambiguity about how AppleScript's compiler
    /// treats a raw control character in source text.
    private static let fetchScript = #"""
    set sep to (ASCII character 31)
    tell application "Spotify"
        set playerState to player state as text
        if playerState is "stopped" then
            return playerState & sep & "" & sep & "" & sep & "" & sep & "0" & sep & "0" & sep & "" & sep & "false"
        end if
        set playerPos to player position
        set theTrack to current track
        return playerState & sep & (name of theTrack) & sep & (artist of theTrack) & sep & (album of theTrack) & sep & (duration of theTrack as text) & sep & (playerPos as text) & sep & (artwork url of theTrack) & sep & (shuffling as text)
    end tell
    """#
}
