import SwiftUI

/// Shown by `ExpandedPlayerView` in place of a bare "Nothing playing"
/// label when there's no `NowPlayingInfo` — date/time and battery percent,
/// the two pieces of ambient info worth surfacing when there's nothing
/// else to show. No reference app combines these two (see the design
/// spec's reference-apps section) — built fresh for Atelier.
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
            VStack(spacing: 3) {
                Text(Self.timeFormatter.string(from: timeline.date))
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(Self.dateFormatter.string(from: timeline.date))
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.6))
                if let percent {
                    Label("\(percent)%", systemImage: "battery.100")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.75))
                        .padding(.top, 2)
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .onReceive(batterySource.currentPercentPublisher) { percent = $0 }
    }
}
