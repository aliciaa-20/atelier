import AppKit

/// Trackpad haptics for discrete, deliberate actions (tab switch, toggle,
/// scrub release). Only fires when a finger is on a Force Touch trackpad --
/// with a mouse or external trackpad `perform` is a silent no-op, so there's
/// no cost or fallback to manage. Kept to a handful of call sites on purpose:
/// haptics on every hover or tick would read as noise.
enum NotchHaptics {
    /// Snap-to-position feel: tab switch, scrub release.
    static func alignment() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    /// A slightly stronger detent: a toggle changing state.
    static func toggle() {
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }
}
