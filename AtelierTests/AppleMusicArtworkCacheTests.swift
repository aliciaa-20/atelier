import Testing
import Foundation
@testable import Atelier

struct AppleMusicArtworkCacheTests {
    private static func info(title: String) -> NowPlayingInfo {
        NowPlayingInfo(
            title: title, artist: "Artist", album: "Album", artworkURL: nil,
            isPlaying: true, duration: 200, elapsed: 10,
            sourceBundleID: "com.apple.Music", isShuffling: false
        )
    }

    private static func withTempDirectory(_ body: (URL) throws -> Void) rethrows {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        try body(dir)
    }

    @Test func givesDifferentTracksDifferentURLsSoDownstreamCachesSeeNewContent() throws {
        try Self.withTempDirectory { dir in
            let cache = AppleMusicArtworkCache(directory: dir)

            let firstURL = cache.url(for: Self.info(title: "Dreams"), data: Data("first".utf8))
            let secondURL = cache.url(for: Self.info(title: "Rhiannon"), data: Data("second".utf8))

            #expect(firstURL != nil)
            #expect(secondURL != nil)
            #expect(firstURL != secondURL)
        }
    }

    @Test func reusesTheSameURLForTheSameTrack() throws {
        try Self.withTempDirectory { dir in
            let cache = AppleMusicArtworkCache(directory: dir)

            let firstURL = cache.url(for: Self.info(title: "Dreams"), data: Data("first".utf8))
            let secondURL = cache.url(for: Self.info(title: "Dreams"), data: Data("first".utf8))

            #expect(firstURL == secondURL)
        }
    }

    @Test func writesTheActualArtworkBytesToTheReturnedURL() throws {
        try Self.withTempDirectory { dir in
            let cache = AppleMusicArtworkCache(directory: dir)
            let bytes = Data("cover-art".utf8)

            let url = try #require(cache.url(for: Self.info(title: "Dreams"), data: bytes))

            #expect(try Data(contentsOf: url) == bytes)
        }
    }

    @Test func removesThePreviousTracksFileWhenTheTrackChanges() throws {
        try Self.withTempDirectory { dir in
            let cache = AppleMusicArtworkCache(directory: dir)

            let firstURL = try #require(cache.url(for: Self.info(title: "Dreams"), data: Data("first".utf8)))
            _ = cache.url(for: Self.info(title: "Rhiannon"), data: Data("second".utf8))

            #expect(!FileManager.default.fileExists(atPath: firstURL.path))
        }
    }
}
