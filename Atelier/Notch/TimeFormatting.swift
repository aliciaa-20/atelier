import Foundation

/// Formats a `TimeInterval` (seconds) as `m:ss` for the scrubber's elapsed/
/// remaining labels. Pure, no AppKit — unit-tested like the rest of Notch/.
enum TimeFormatting {
    static func mmss(_ seconds: TimeInterval) -> String {
        let total = Int(max(seconds, 0))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// Formats a duration as "2h 14m" (or "14m" under an hour) for
    /// `BatteryActivityContent`'s time-remaining/time-to-full label. `nil`
    /// input means "still calculating" -- Apple's own documented sentinel
    /// for `kIOPSTimeToEmptyKey`/`kIOPSTimeToFullChargeKey` (-1) -- and
    /// returns `nil` rather than a nonsense duration.
    static func hoursAndMinutes(_ seconds: TimeInterval?) -> String? {
        guard let seconds, seconds >= 0 else { return nil }
        let totalMinutes = Int(seconds / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }

    /// Same as `hoursAndMinutes`, without the space -- for
    /// `BatteryActivityContent`'s pill, which has far less room than the
    /// peek (only the pillView is ever actually shown, per Battery's
    /// deliberate `peeksOnChange == false`).
    static func hoursAndMinutesCompact(_ seconds: TimeInterval?) -> String? {
        guard let seconds, seconds >= 0 else { return nil }
        let totalMinutes = Int(seconds / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return hours > 0 ? "\(hours)h\(minutes)m" : "\(minutes)m"
    }
}
