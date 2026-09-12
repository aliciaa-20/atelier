import Foundation

/// Owns dropped files on disk: copies them into `rootDirectory`, tracks
/// them as a plain `[ShelfItem]` (no `OrderedSet`/`swift-collections`
/// dependency), and persists that list as a small JSON manifest.
/// `rootDirectory` is injected rather than hardcoded to a real Application
/// Support path so tests can point this at a temp directory.
@MainActor
final class ShelfStore: ObservableObject {
    @Published private(set) var items: [ShelfItem] = []

    private let rootDirectory: URL
    private let keepInterval: TimeInterval
    private var manifestURL: URL { rootDirectory.appendingPathComponent("manifest.json") }

    init(rootDirectory: URL, keepInterval: TimeInterval = 60 * 60 * 24) {
        self.rootDirectory = rootDirectory
        self.keepInterval = keepInterval
        try? FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        items = Self.loadManifest(at: manifestURL)
    }

    /// Copies `sourceURL` into a fresh per-item directory under
    /// `rootDirectory` and adds it to `items`. The original file is never
    /// modified or moved.
    func addFile(at sourceURL: URL, originalFilename: String) throws {
        let item = ShelfItem(id: UUID(), originalFilename: originalFilename, addedAt: Date())
        let destination = item.storageURL(root: rootDirectory)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: sourceURL, to: destination)

        items.insert(item, at: 0)
        saveManifest()
    }

    func remove(_ id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        try? FileManager.default.removeItem(at: item.storageURL(root: rootDirectory).deletingLastPathComponent())
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
            try? FileManager.default.removeItem(at: item.storageURL(root: rootDirectory).deletingLastPathComponent())
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
