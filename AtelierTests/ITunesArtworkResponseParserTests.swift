import Testing
import Foundation
@testable import Atelier

struct ITunesArtworkResponseParserTests {
    @Test func upscalesTheArtworkURLFromTheFirstResult() {
        // Trimmed to the fields we actually read; real responses have many more.
        let json = #"""
        {
            "resultCount": 1,
            "results": [
                {
                    "artistName": "Bee Gees",
                    "trackName": "Alone",
                    "artworkUrl100": "https://is1-ssl.mzstatic.com/image/thumb/Music/v4/aa/bb/cc/100x100bb.jpg"
                }
            ]
        }
        """#

        let url = ITunesArtworkResponseParser.parseArtworkURL(from: Data(json.utf8))

        #expect(url == URL(string: "https://is1-ssl.mzstatic.com/image/thumb/Music/v4/aa/bb/cc/600x600bb.jpg"))
    }

    @Test func returnsNilWhenThereAreNoResults() {
        let json = #"{"resultCount": 0, "results": []}"#

        let url = ITunesArtworkResponseParser.parseArtworkURL(from: Data(json.utf8))

        #expect(url == nil)
    }

    @Test func returnsNilForMalformedJSON() {
        let url = ITunesArtworkResponseParser.parseArtworkURL(from: Data("not json".utf8))

        #expect(url == nil)
    }
}
