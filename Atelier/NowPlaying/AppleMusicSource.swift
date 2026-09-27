import AppKit

/// Music.app's `NowPlayingSource` conformer. Same shape as `SpotifySource`,
/// with two differences forced by Music.app's own AppleScript dictionary:
/// duration/position are both already in seconds (no ms normalization), and
/// artwork comes back as raw bytes rather than a URL — cached to disk once
/// per track change so we're not writing a file on every 1s poll tick.
struct AppleMusicSource: NowPlayingSource {
    private static let bundleID = "com.apple.Music"

    /// Same race documented on `SpotifySource`: `isAvailable` alone can be
    /// stale between the check and the Apple Event, so every script below
    /// also re-checks `application "Music" is running` internally.
    var isAvailable: Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == Self.bundleID }
    }

    private let artworkCache = AppleMusicArtworkCache()
    /// Streaming tracks report no artwork via AppleScript at all (Music.app's
    /// scripting dictionary only exposes it for tracks downloaded to the
    /// local library) — this is the fallback for that case.
    private let itunesArtworkLookup = ITunesArtworkLookup()

    func fetch() async -> NowPlayingInfo? {
        guard isAvailable, let descriptor = AppleScriptRunner.runDescriptor(Self.fetchScript) else { return nil }
        guard let parsed = AppleMusicOutputParser.parse(descriptor) else { return nil }

        if let artworkData = parsed.artworkData {
            let url = artworkCache.url(for: parsed.info, data: artworkData)
            return parsed.info.with(artworkURL: url)
        }

        let fallbackURL = await itunesArtworkLookup.url(
            title: parsed.info.title, artist: parsed.info.artist, album: parsed.info.album
        )
        return parsed.info.with(artworkURL: fallbackURL)
    }

    func playPause() async {
        guard isAvailable else { return }
        _ = AppleScriptRunner.run(#"if application "Music" is running then tell application "Music" to playpause"#)
    }

    func next() async {
        guard isAvailable else { return }
        _ = AppleScriptRunner.run(#"if application "Music" is running then tell application "Music" to next track"#)
    }

    func previous() async {
        guard isAvailable else { return }
        _ = AppleScriptRunner.run(#"if application "Music" is running then tell application "Music" to previous track"#)
    }

    func seek(to time: TimeInterval) async {
        guard isAvailable else { return }
        _ = AppleScriptRunner.run(#"if application "Music" is running then tell application "Music" to set player position to \#(time)"#)
    }

    func toggleShuffle() async {
        guard isAvailable else { return }
        _ = AppleScriptRunner.run(#"if application "Music" is running then tell application "Music" to set shuffle enabled to not shuffle enabled"#)
    }

    /// Result order must match `AppleMusicOutputParser`: hasTrack, isPlaying,
    /// name, artist, album, position, duration, shuffle enabled, hasArtwork,
    /// artwork data. `hasArtwork` is a separate flag rather than inferring
    /// presence from the data descriptor's type/emptiness, since Music.app
    /// returns a real (small) descriptor either way.
    private static let fetchScript = #"""
    if application "Music" is not running then return {false, false, "", "", "", 0, 0, false, false, missing value}
    tell application "Music"
        if player state is stopped then
            return {false, false, "", "", "", 0, 0, false, false, missing value}
        end if
        set isPlaying to player state is playing
        set trackName to name of current track
        set trackArtist to artist of current track
        set trackAlbum to album of current track
        set trackPosition to player position
        set trackDuration to duration of current track
        set shuffleState to shuffle enabled
        try
            set artData to data of artwork 1 of current track
            set hasArt to true
        on error
            set artData to missing value
            set hasArt to false
        end try
        return {true, isPlaying, trackName, trackArtist, trackAlbum, trackPosition, trackDuration, shuffleState, hasArt, artData}
    end tell
    """#
}
