import Foundation

/// One file on the shelf. Pure -- no FileManager/AppKit -- so expiry logic
/// is unit-testable independent of `ShelfStore`'s actual file I/O.
struct ShelfItem: Codable, Identifiable, Equatable {
    let id: UUID
    let originalFilename: String
    let addedAt: Date

    /// Nested under a per-item UUID directory (not stored flat) so two
    /// items with the same original filename never collide.
    func storageURL(root: URL) -> URL {
        root.appendingPathComponent(id.uuidString).appendingPathComponent(originalFilename)
    }

    /// `now`/`keepInterval` are parameters, not read from `Date()`/a stored
    /// default internally, specifically so this stays unit-testable without
    /// wall-clock dependence -- same reasoning `BatteryActivityState.evaluate`
    /// already follows for its own pure threshold check.
    func isExpired(now: Date, keepInterval: TimeInterval) -> Bool {
        now.timeIntervalSince(addedAt) > keepInterval
    }
}
