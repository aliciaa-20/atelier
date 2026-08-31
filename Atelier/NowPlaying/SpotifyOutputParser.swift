import Foundation

/// Parses the delimited string Spotify's AppleScript dictionary is queried
/// to produce (see `AppleScriptRunner`). A control character delimiter is
/// used rather than something printable, since track/artist/album text could
/// in principle contain any ordinary punctuation.
enum SpotifyOutputParser {
    static let fieldSeparator = "\u{1F}"
    private static let expectedFieldCount = 7
    private static let bundleID = "com.spotify.client"

    static func parse(_ raw: String) -> NowPlayingInfo? {
        let fields = raw.components(separatedBy: fieldSeparator)
        guard fields.count == expectedFieldCount else { return nil }

        let playerState = fields[0]
        guard playerState == "playing" || playerState == "paused" else { return nil }
        guard let durationMs = Double(fields[4]), let elapsedSeconds = Double(fields[5]) else { return nil }

        return NowPlayingInfo(
            title: fields[1],
            artist: fields[2],
            album: fields[3],
            artworkURL: URL(string: fields[6]),
            isPlaying: playerState == "playing",
            duration: durationMs / 1000,
            elapsed: elapsedSeconds,
            sourceBundleID: bundleID
        )
    }
}
