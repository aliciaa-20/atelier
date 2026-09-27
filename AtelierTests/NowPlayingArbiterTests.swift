import Testing
import Foundation
@testable import Atelier

struct NowPlayingArbiterTests {
    private static func info(isPlaying: Bool, bundleID: String) -> NowPlayingInfo {
        NowPlayingInfo(
            title: "Title", artist: "Artist", album: "Album", artworkURL: nil,
            isPlaying: isPlaying, duration: 200, elapsed: 10,
            sourceBundleID: bundleID, isShuffling: false
        )
    }

    @Test func choosesTheOnlyAvailableSource() {
        let candidates = [
            NowPlayingArbiter.Candidate(sourceID: "spotify", info: Self.info(isPlaying: true, bundleID: "com.spotify.client")),
            NowPlayingArbiter.Candidate(sourceID: "appleMusic", info: nil),
        ]

        let chosen = NowPlayingArbiter.choose(candidates: candidates, previousActiveID: nil)

        #expect(chosen == "spotify")
    }

    @Test func returnsNilWhenNoSourceIsAvailable() {
        let candidates = [
            NowPlayingArbiter.Candidate(sourceID: "spotify", info: nil),
            NowPlayingArbiter.Candidate(sourceID: "appleMusic", info: nil),
        ]

        let chosen = NowPlayingArbiter.choose(candidates: candidates, previousActiveID: "spotify")

        #expect(chosen == nil)
    }

    @Test func prefersThePlayingSourceOverThePausedOne() {
        let candidates = [
            NowPlayingArbiter.Candidate(sourceID: "spotify", info: Self.info(isPlaying: false, bundleID: "com.spotify.client")),
            NowPlayingArbiter.Candidate(sourceID: "appleMusic", info: Self.info(isPlaying: true, bundleID: "com.apple.Music")),
        ]

        let chosen = NowPlayingArbiter.choose(candidates: candidates, previousActiveID: "spotify")

        #expect(chosen == "appleMusic")
    }

    @Test func staysOnThePreviousActiveSourceWhenBothAreCurrentlyPlaying() {
        let candidates = [
            NowPlayingArbiter.Candidate(sourceID: "spotify", info: Self.info(isPlaying: true, bundleID: "com.spotify.client")),
            NowPlayingArbiter.Candidate(sourceID: "appleMusic", info: Self.info(isPlaying: true, bundleID: "com.apple.Music")),
        ]

        let chosen = NowPlayingArbiter.choose(candidates: candidates, previousActiveID: "appleMusic")

        #expect(chosen == "appleMusic")
    }

    @Test func fallsBackToFirstCandidateWhenAmbiguousAndNoPreviousActiveSource() {
        let candidates = [
            NowPlayingArbiter.Candidate(sourceID: "spotify", info: Self.info(isPlaying: false, bundleID: "com.spotify.client")),
            NowPlayingArbiter.Candidate(sourceID: "appleMusic", info: Self.info(isPlaying: false, bundleID: "com.apple.Music")),
        ]

        let chosen = NowPlayingArbiter.choose(candidates: candidates, previousActiveID: nil)

        #expect(chosen == "spotify")
    }
}
