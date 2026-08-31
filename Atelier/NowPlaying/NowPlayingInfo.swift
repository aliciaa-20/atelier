import Foundation

/// `duration` and `elapsed` are always seconds here — sources normalize their
/// own native units (Spotify reports duration in milliseconds, elapsed in
/// seconds; see docs/decisions/0002-spotify-only-for-v1.md) before
/// constructing this.
struct NowPlayingInfo: Equatable {
    let title: String
    let artist: String
    let album: String
    let artworkURL: URL?
    let isPlaying: Bool
    let duration: TimeInterval
    let elapsed: TimeInterval
    let sourceBundleID: String
}
