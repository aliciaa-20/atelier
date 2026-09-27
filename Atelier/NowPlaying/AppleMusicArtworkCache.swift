import Foundation

/// Writes Apple Music's raw artwork bytes to disk, one file per track. Only
/// rewrites when the track actually changes, so an idle 1s poll on a still-
/// playing track never touches disk.
///
/// The URL must change per track: `ArtworkView` re-fetches via `.task(id:
/// url)` and `ArtworkImageCache` caches by URL, so reusing one fixed filename
/// (the original bug here) makes both layers treat every track after the
/// first as "already loaded" and never show new artwork.
final class AppleMusicArtworkCache {
    private let directory: URL
    private var lastTrackKey: String?
    private var lastURL: URL?

    init(directory: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Atelier/AppleMusicArtwork", isDirectory: true)) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func url(for info: NowPlayingInfo, data: Data) -> URL? {
        let key = "\(info.title)|\(info.artist)|\(info.album)"
        if key == lastTrackKey, let lastURL {
            return lastURL
        }

        let destination = directory.appendingPathComponent("\(UUID().uuidString).jpg")
        guard (try? data.write(to: destination, options: .atomic)) != nil else { return nil }

        if let lastURL {
            try? FileManager.default.removeItem(at: lastURL)
        }
        lastTrackKey = key
        lastURL = destination
        return destination
    }
}
