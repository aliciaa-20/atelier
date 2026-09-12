import Foundation

/// Owns dropped files on disk: copies them into `rootDirectory`, tracks
/// them as a plain `[ShelfItem]` (no `OrderedSet`/`swift-collections`
/// dependency), and persists that list as a small JSON manifest.
/// `rootDirectory` is injected rather than hardcoded to a real Application
/// Support path so tests can point this at a temp directory.
@MainActor
final class ShelfStore: ObservableObject {
    @Published private(set) var items: [ShelfItem] = []

    let rootDirectory: URL
    private let keepInterval: TimeInterval
    private var manifestURL: URL { rootDirectory.appendingPathComponent("manifest.json") }

    init(rootDirectory: URL, keepInterval: TimeInterval = 60 * 60 * 24) {
        self.rootDirectory = rootDirectory
        self.keepInterval = keepInterval
        try? FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        items = Self.loadManifest(at: manifestURL)
    }

    /// Moves `sourceURL` into a fresh per-item directory under
    /// `rootDirectory` and adds it to `items`. This moves rather than
    /// copies `sourceURL` -- the only production caller (`NotchRootView`'s
    /// `onDrop`) already made its own private staging copy before calling
    /// this, so a second full-file copy here was pure waste (and, on a
    /// large file, a synchronous main-actor-blocking one). Never call this
    /// with a URL the caller still needs afterward. `addedAt` is injected
    /// for testing with controlled timestamps; production calls use the
    /// default `Date()`.
    func addFile(at sourceURL: URL, originalFilename: String, addedAt: Date = Date()) throws {
        let item = ShelfItem(id: UUID(), originalFilename: originalFilename, addedAt: addedAt)
        let destination = item.storageURL(root: rootDirectory)
        let destinationDir = destination.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: destinationDir, withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: sourceURL, to: destination)
        } catch {
            // Clean up the directory we just created if moveItem fails.
            try? FileManager.default.removeItem(at: destinationDir)
            throw error
        }

        items.insert(item, at: 0)
        saveManifest()
    }

    func remove(_ id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        // Ignore file-system deletion errors — orphan files don't affect correctness.
        // Constructed directly from the item's own UUID rather than by
        // stripping the filename back off `storageURL` -- if
        // `originalFilename` were ever empty (or "/"), deriving the
        // directory that way could resolve to `rootDirectory` itself and
        // delete the whole shelf.
        try? FileManager.default.removeItem(at: rootDirectory.appendingPathComponent(item.id.uuidString))
        items.removeAll { $0.id == id }
        saveManifest()
    }

    /// Lazy sweep, not a background timer -- called when the shelf is
    /// opened and once at app launch, per the design spec. `now` is a
    /// parameter so this stays testable without wall-clock dependence.
    func sweepExpired(now: Date = Date()) {
        let expired = items.filter { $0.isExpired(now: now, keepInterval: keepInterval) }
        guard !expired.isEmpty else { return }
        for item in expired {
            // Ignore file-system deletion errors — orphan files don't affect correctness.
            // See `remove(_:)` for why this is built from the item's UUID
            // directly rather than derived from `storageURL`.
            try? FileManager.default.removeItem(at: rootDirectory.appendingPathComponent(item.id.uuidString))
        }
        items.removeAll { item in expired.contains(item) }
        saveManifest()
    }

    private func saveManifest() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: manifestURL, options: .atomic)
    }

    private static func loadManifest(at url: URL) -> [ShelfItem] {
        guard let data = try? Data(contentsOf: url),
              let items = try? JSONDecoder().decode([ShelfItem].self, from: data)
        else { return [] }
        return items
    }
}
