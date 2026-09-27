import Foundation

/// Looks up cover art from the public iTunes Search API (no key required) as
/// a fallback for streaming Apple Music tracks, which don't expose artwork
/// via AppleScript at all. Caches by track so a network request only fires
/// once per track change, not on every 1s/250ms poll tick.
final class ITunesArtworkLookup {
    private var lastTrackKey: String?
    private var lastResult: URL?

    func url(title: String, artist: String, album: String) async -> URL? {
        let key = "\(title)|\(artist)|\(album)"
        if key == lastTrackKey {
            return lastResult
        }

        let result = await Self.fetch(title: title, artist: artist)
        lastTrackKey = key
        lastResult = result
        return result
    }

    private static func fetch(title: String, artist: String) async -> URL? {
        var components = URLComponents(string: "https://itunes.apple.com/search")!
        components.queryItems = [
            URLQueryItem(name: "term", value: "\(artist) \(title)"),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "1"),
        ]
        guard let url = components.url else { return nil }
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        return ITunesArtworkResponseParser.parseArtworkURL(from: data)
    }
}
