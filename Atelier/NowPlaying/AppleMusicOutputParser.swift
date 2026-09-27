import Foundation

/// Parses the list `NSAppleEventDescriptor` returned by Music.app's fetch
/// script (see `AppleMusicSource`). Unlike Spotify, Music.app reports
/// duration/position both in seconds (no ms/s mismatch to normalize, but
/// still worth stating explicitly given `docs/decisions/0002-*`), and has no
/// artwork URL — artwork comes back as raw bytes, which the caller caches to
/// disk and turns into a `file://` URL.
enum AppleMusicOutputParser {
    private static let bundleID = "com.apple.Music"

    struct Parsed {
        let info: NowPlayingInfo
        let artworkData: Data?
    }

    static func parse(_ descriptor: NSAppleEventDescriptor) -> Parsed? {
        guard descriptor.numberOfItems >= 10 else { return nil }
        guard descriptor.atIndex(1)?.booleanValue == true else { return nil }

        let info = NowPlayingInfo(
            title: descriptor.atIndex(3)?.stringValue ?? "",
            artist: descriptor.atIndex(4)?.stringValue ?? "",
            album: descriptor.atIndex(5)?.stringValue ?? "",
            artworkURL: nil,
            isPlaying: descriptor.atIndex(2)?.booleanValue ?? false,
            duration: descriptor.atIndex(7)?.doubleValue ?? 0,
            elapsed: descriptor.atIndex(6)?.doubleValue ?? 0,
            sourceBundleID: bundleID,
            isShuffling: descriptor.atIndex(8)?.booleanValue ?? false
        )

        let hasArtwork = descriptor.atIndex(9)?.booleanValue ?? false
        let artworkData = hasArtwork ? descriptor.atIndex(10)?.data : nil
        return Parsed(info: info, artworkData: artworkData)
    }
}
