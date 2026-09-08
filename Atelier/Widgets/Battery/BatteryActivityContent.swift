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

    func pillView() -> AnyView {
        AnyView(
            HStack(spacing: 0) {
                // The real, live percent -- always, not just for `.low`.
                // `minimumScaleFactor` only does anything once the text is
                // actually width-constrained -- without the `.frame`
                // below it had nothing to shrink against, so "100%" (the
                // widest case) rendered at full size and overflowed
                // anyway. The frame is the real fix; the smaller base
                // size and scale factor are the safety margin under it.
                Text("\(percent)%")
                    .font(.system(size: 9.5, weight: .medium))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: 22, alignment: .leading)
                    .foregroundStyle(tint)

                Spacer(minLength: 0)

                // Smaller and with more trailing clearance than the pill's
                // flat-edge padding alone -- NotchShape's bottom corner
                // curves inward more than the padding accounted for, so a
                // 12pt icon at 13pt padding was bleeding past the visible
                // black area right at the corner.
                Image(systemName: symbolName)
                    .foregroundStyle(tint)
                    .font(.system(size: 10))
            }
            .padding(.leading, 6)
            .padding(.trailing, 16)
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
