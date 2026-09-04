import Foundation

/// `ArtworkView` (the visible artwork) and `ArtworkColorLoader` (the
/// waveform's average-color extraction) both need the same artwork bytes on
/// every track change. Before this, each ran its own `URLSession` fetch of
/// the identical URL — two concurrent downloads racing for bandwidth, which
/// was the real cause of artwork taking ~1.5s to appear. This caches by URL
/// and de-duplicates in-flight fetches so the image is downloaded once and
/// shared.
///
/// Caches `Data`, not `NSImage`/`CGImage` — those aren't `Sendable`, and
/// decoding twice from cached data is cheap next to a network round trip.
actor ArtworkImageCache {
    static let shared = ArtworkImageCache()

    private var cache: [URL: Data] = [:]
    private var inFlight: [URL: Task<Data?, Never>] = [:]

    private init() {}

    func data(for url: URL) async -> Data? {
        if let cached = cache[url] {
            return cached
        }
        if let existing = inFlight[url] {
            return await existing.value
        }

        let task = Task<Data?, Never> {
            try? await URLSession.shared.data(from: url).0
        }
        inFlight[url] = task

        let result = await task.value
        inFlight[url] = nil
        if let result {
            cache[url] = result
        }
        return result
    }
}
