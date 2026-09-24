import SwiftUI

/// Shown by `ExpandedPlayerView` in place of a bare "Nothing playing"
/// label when there's no `NowPlayingInfo` — just date/time. No reference
/// app does this exact thing (see the design spec's reference-apps
/// section) — built fresh for Atelier.
///
/// Battery was dropped from here (an earlier version showed it below the
/// date) -- it made the card taller than `NotchController.idleHomeContentHeight`
/// budgeted for and got clipped at the bottom edge on-device. Battery
/// already has its own pill/peek surface (`BatterySource`'s own
/// `LiveActivitySource`), so this doesn't lose the information, just this
/// one redundant, overflow-prone place it was also shown.
///
/// Time is the single hero element (large, rounded-design monospaced
/// digits — the same font design `ScrubberView`'s own time labels already
/// use, so numerals read consistently across the app), date secondary
/// below it -- same hierarchy Apple's own Lock Screen uses.
struct IdleHomeView: View {
    @ObservedObject var weather: WeatherSource

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
            VStack(spacing: 3) {
                Text(Self.timeFormatter.string(from: timeline.date))
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .monospacedDigit()

                Text(Self.dateFormatter.string(from: timeline.date))
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.6))

                if let snap = weather.visibleSnapshot {
                    weatherRow(snap)
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .center)
            // Scoped here, not on the shared `ExpandedPlayerView` bottom
            // padding -- that one also governs the transport row's
            // spacing in the playing state, unrelated to this ask.
            .padding(.bottom, 2.5)
        }
        .onAppear { weather.refreshIfStale() }
    }

    /// One quiet line under the date: glyph, temp, and a quip. Unit comes from
    /// the snapshot (locale-chosen at fetch time).
    private func weatherRow(_ snap: WeatherSnapshot) -> some View {
        let condition = snap.currentCondition
        let temp = "\(Int(snap.currentTemp.rounded()))°"
        return HStack(spacing: 4) {
            Image(systemName: condition.symbol)
                .symbolRenderingMode(.multicolor)
            Text(temp).monospacedDigit()
            Text("·").foregroundStyle(.white.opacity(0.4))
            Text(condition.quip)
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .font(.caption2)
        .padding(.top, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(condition.label), \(temp)")
    }
}
