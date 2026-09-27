import Testing
import Foundation
@testable import Atelier

struct AppleMusicOutputParserTests {
    private static func descriptor(
        hasTrack: Bool = true,
        isPlaying: Bool = true,
        title: String = "Dreams",
        artist: String = "Fleetwood Mac",
        album: String = "Rumours",
        position: Double = 12.5,
        duration: Double = 257.0,
        shuffling: Bool = true,
        hasArtwork: Bool = false,
        artworkData: Data = Data()
    ) -> NSAppleEventDescriptor {
        // 'data' as a raw AppleScript descriptor type (AEDataStorageType),
        // matching what `data of artwork 1 of current track` produces.
        let rawDataType: DescType = 0x6461_7461

        let list = NSAppleEventDescriptor.list()
        list.insert(NSAppleEventDescriptor(boolean: hasTrack), at: 1)
        list.insert(NSAppleEventDescriptor(boolean: isPlaying), at: 2)
        list.insert(NSAppleEventDescriptor(string: title), at: 3)
        list.insert(NSAppleEventDescriptor(string: artist), at: 4)
        list.insert(NSAppleEventDescriptor(string: album), at: 5)
        list.insert(NSAppleEventDescriptor(double: position), at: 6)
        list.insert(NSAppleEventDescriptor(double: duration), at: 7)
        list.insert(NSAppleEventDescriptor(boolean: shuffling), at: 8)
        list.insert(NSAppleEventDescriptor(boolean: hasArtwork), at: 9)
        list.insert(NSAppleEventDescriptor(descriptorType: rawDataType, data: artworkData)!, at: 10)
        return list
    }

    @Test func parsesAPlayingTrack() {
        let parsed = AppleMusicOutputParser.parse(Self.descriptor())

        #expect(parsed?.info == NowPlayingInfo(
            title: "Dreams",
            artist: "Fleetwood Mac",
            album: "Rumours",
            artworkURL: nil,
            isPlaying: true,
            duration: 257.0,
            elapsed: 12.5,
            sourceBundleID: "com.apple.Music",
            isShuffling: true
        ))
    }

    @Test func returnsNilWhenNoTrackIsLoaded() {
        let parsed = AppleMusicOutputParser.parse(Self.descriptor(hasTrack: false))

        #expect(parsed == nil)
    }

    @Test func capturesArtworkBytesWhenPresent() {
        let artworkBytes = "not-really-a-jpeg".data(using: .utf8)!

        let parsed = AppleMusicOutputParser.parse(Self.descriptor(hasArtwork: true, artworkData: artworkBytes))

        #expect(parsed?.artworkData == artworkBytes)
    }

    @Test func hasNoArtworkDataWhenTrackHasNoArtwork() {
        let parsed = AppleMusicOutputParser.parse(Self.descriptor(hasArtwork: false))

        #expect(parsed?.artworkData == nil)
    }
}
