import SwiftUI

/// Shown by `ExpandedPlayerView` in place of a bare "Nothing playing"
/// label when there's no `NowPlayingInfo` — date/time and battery percent,
/// the two pieces of ambient info worth surfacing when there's nothing
/// else to show. No reference app combines these two (see the design
/// spec's reference-apps section) — built fresh for Atelier.
///
/// Time is the single hero element (large, rounded-design monospaced
/// digits — the same font design `ScrubberView`'s own time labels already
/// use, so numerals read consistently across the app), with date and
/// battery as one tightly-grouped secondary cluster below it rather than
/// three lines of similar weight competing for attention. Same
/// hierarchy Apple's own Lock Screen uses for its date/time.
struct IdleHomeView: View {
    let batterySource: BatterySource
    @State private var percent: Int?

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        return formatter
    }()

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            VStack(spacing: 4) {
                Text(Self.timeFormatter.string(from: timeline.date))
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .monospacedDigit()

                VStack(spacing: 2) {
                    Text(Self.dateFormatter.string(from: timeline.date))
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.6))

                    if let percent {
                        Label("\(percent)%", systemImage: Self.batteryIconName(for: percent))
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .onReceive(batterySource.currentPercentPublisher) { percent = $0 }
    }

    /// Matches the real percent instead of a hardcoded `battery.100` --
    /// the previous version always showed a full-battery glyph regardless
    /// of actual charge, which is simply wrong information next to a real
    /// percentage. Bands match the SF Symbol steps Apple's own battery
    /// icon uses (0/25/50/75/100), not arbitrary thresholds.
    private static func batteryIconName(for percent: Int) -> String {
        switch percent {
        case ..<13: "battery.0"
        case ..<38: "battery.25"
        case ..<63: "battery.50"
        case ..<88: "battery.75"
        default: "battery.100"
        }
    }
}
