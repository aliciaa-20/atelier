import Foundation

/// Tracks which of Volume/Brightness was touched most recently. Shared
/// between `VolumeSource` and `BrightnessSource` (one instance, injected
/// into both by `NotchController`) -- each computes its own `priority` by
/// comparing its `id` against `mostRecentID`, so pressing one key
/// immediately outranks whichever OSD was already on top, matching real
/// macOS (pressing brightness while the volume HUD is showing replaces it
/// instantly, not after volume's own peek decays).
///
/// Deliberately not expressed via `LiveActivityStack`'s own equal-priority
/// tie-break -- that tie-break is order-independent by design (see
/// `LiveActivityStackTests.equalPriorityBreaksTieByIDOrdering`), which is
/// the opposite of what's needed here. Baking recency directly into which
/// literal priority integer each source reports keeps that general
/// invariant intact. See ADR 0008 for the full investigation.
final class SystemHUDOrder {
    private(set) var mostRecentID: String?

    func touch(_ id: String) {
        mostRecentID = id
    }
}
