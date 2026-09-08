import SwiftUI

struct BatteryActivityContent: LiveActivityContent {
    let state: BatteryActivityState
    /// Same reasoning as `PeekPlayerView.notchHeight`: the physical notch
    /// cutout has no display pixels, so peek content starts below it.
    let notchHeight: CGFloat
    /// Time-to-empty (discharging) or time-to-full (charging), in seconds.
    /// `nil` when macOS is still calculating it (`kIOPSTimeToEmptyKey`/
    /// `kIOPSTimeToFullChargeKey`'s own `-1` sentinel) or the state is
    /// `.full`. Not part of `id` -- see `id`'s own doc comment.
    var timeRemaining: TimeInterval? = nil

    /// Percent-free on purpose -- identity is about *which state*, not the
    /// live number (which updates every poll via `percent` below without
    /// needing a new identity). Doesn't gate a peek either way any more
    /// (`peeksOnChange` is `false`), but keeping identity stable avoids
    /// unnecessary view-identity churn on every 1% change.
    var id: String {
        switch state {
        case .charging: "battery:charging"
        case .low: "battery:low"
        case .full: "battery:full"
        }
    }

    /// Battery is ambient state, not a discrete event worth interrupting
    /// for -- only ever shows as the small pill icon, never the auto-peek.
    var peeksOnChange: Bool { false }

    private var percent: Int {
        switch state {
        case .charging(let percent): percent
        case .low(let percent): percent
        case .full: 100
        }
    }

    private var symbolName: String {
        switch state {
        case .charging: "bolt.fill"
        case .low:
            if percent <= 10 { "battery.0" }
            else if percent <= 35 { "battery.25" }
            else { "battery.50" }
        case .full: "battery.100"
        }
    }

    private var tint: Color {
        switch state {
        case .charging: .green
        case .low: .red
        case .full: .green
        }
    }

    private var label: String {
        let suffix = TimeFormatting.hoursAndMinutes(timeRemaining).map { "  ·  \($0)" } ?? ""
        switch state {
        case .charging: return "Charging  \(percent)%\(suffix)"
        case .low: return "Battery Low  \(percent)%\(suffix)"
        case .full: return "Full Battery"
        }
    }

    /// No icon -- bolt+percent together needed ~35pt, well past the
    /// ~18pt each flank actually has before the physical notch's dead
    /// zone swallows content (the same budget `PillPlayerView`'s
    /// artwork/waveform flanks already proved out). Text-only on both
    /// sides, equal padding, fits the same budget each side.
    func pillView() -> AnyView {
        AnyView(
            HStack(spacing: 0) {
                // Time-remaining/time-to-full on the left flank -- the
                // only place this data is ever actually visible, since
                // Battery's `peeksOnChange == false` means `peekView`
                // (which also carries it, via `label`) never renders.
                // Blank rather than a placeholder while macOS is still
                // calculating it (`nil`) or the battery is full.
                if let compactTime = TimeFormatting.hoursAndMinutesCompact(timeRemaining) {
                    // Unlike the percent text below (anchored to the safe
                    // trailing edge, so it only ever grows away from the
                    // notch), this one is anchored to the safe *leading*
                    // edge -- unconstrained, it grows toward the notch as
                    // the string widens (e.g. "12h34m" vs "51m"). The
                    // fixed max width forces it to shrink via
                    // minimumScaleFactor instead of overlapping the dead
                    // zone -- confirmed on-device as the actual asymmetry
                    // ("m" clipped on the left, right side fine).
                    Text(compactTime)
                        .font(.system(size: 12, weight: .medium))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .frame(maxWidth: 18, alignment: .leading)
                        .foregroundStyle(tint.opacity(0.75))
                }

                Spacer(minLength: 0)

                Text("\(percent)%")
                    .font(.system(size: 12, weight: .medium))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: 18, alignment: .trailing)
                    .foregroundStyle(tint)
            }
            .padding(.leading, 12)
            .padding(.trailing, 12)
        )
    }

    func peekView() -> AnyView {
        AnyView(
            HStack(spacing: 8) {
                Image(systemName: symbolName)
                    .foregroundStyle(tint)
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 9)
            .padding(.top, notchHeight + 4)
        )
    }
}
