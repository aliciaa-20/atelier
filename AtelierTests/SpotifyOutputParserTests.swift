import Testing
import Foundation
@testable import Atelier

struct SpotifyOutputParserTests {
    @Test func parsesPlayingTrackWithCorrectUnitNormalization() {
        // Real numbers captured live from Spotify (scripts/spotify-probe.applescript,
        // see docs/decisions/0002-spotify-only-for-v1.md): duration is
        // milliseconds, elapsed is seconds. Using distinct, asymmetric values
        // here means a units mixup fails loudly rather than by coincidence.
        let raw = [
            "playing",
            "You Make Loving Fun - 2004 Remaster",
            "Fleetwood Mac",
            "Rumours",
            "213693",
            "194.891006469727",
            "https://i.scdn.co/image/ab67616d0000b27357df7ce0eac715cf70e519a7",
        ].joined(separator: SpotifyOutputParser.fieldSeparator)

        let info = SpotifyOutputParser.parse(raw)

        #expect(info == NowPlayingInfo(
            title: "You Make Loving Fun - 2004 Remaster",
            artist: "Fleetwood Mac",
            album: "Rumours",
            artworkURL: URL(string: "https://i.scdn.co/image/ab67616d0000b27357df7ce0eac715cf70e519a7"),
            isPlaying: true,
            duration: 213.693,
            elapsed: 194.891006469727,
            sourceBundleID: "com.spotify.client"
        ))
    }
}

extension SpotifyOutputParserTests {
    @Test func returnsNilWhenStopped() {
        let raw = [
            "stopped", "", "", "", "0", "0", "",
        ].joined(separator: SpotifyOutputParser.fieldSeparator)

        let info = SpotifyOutputParser.parse(raw)

        #expect(info == nil)
    }
}
