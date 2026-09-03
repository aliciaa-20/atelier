import Foundation

/// Formats a `TimeInterval` (seconds) as `m:ss` for the scrubber's elapsed/
/// remaining labels. Pure, no AppKit — unit-tested like the rest of Notch/.
enum TimeFormatting {
    static func mmss(_ seconds: TimeInterval) -> String {
        let total = Int(max(seconds, 0))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
