import Foundation

/// Parses the iTunes Search API's JSON response, used as an artwork fallback
/// when Music.app's own AppleScript reports none — true for any streaming
/// (non-downloaded) track, since Music.app's scripting dictionary only
/// exposes `artwork` for tracks actually stored in the local library.
enum ITunesArtworkResponseParser {
    private struct Response: Decodable {
        struct Result: Decodable { let artworkUrl100: String? }
        let results: [Result]
    }

    /// iTunes's artwork URLs encode the requested size in the filename
    /// (`.../100x100bb.jpg`); swapping it is the standard way callers get a
    /// higher resolution than the default thumbnail.
    private static let requestedSize = "100x100bb"
    private static let upscaledSize = "600x600bb"

    static func parseArtworkURL(from data: Data) -> URL? {
        guard let response = try? JSONDecoder().decode(Response.self, from: data),
              let raw = response.results.first?.artworkUrl100 else { return nil }
        return URL(string: raw.replacingOccurrences(of: requestedSize, with: upscaledSize))
    }
}
