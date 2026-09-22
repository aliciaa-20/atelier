import SwiftUI

/// The `NotchPage.systemMonitor` tab -- CPU load and memory pressure as
/// two labeled capsule bars, shown full-size (unlike the pill's bare
/// percentages, which are squeezed into ~18pt flanks). Sits in the same
/// `expandedSize` frame `ExpandedPlayerView`/`ShelfView` already use when
/// selected via `NotchTabBar` (Invariant 3 -- the panel itself never
/// resizes, only this content frame does), so no new panel size was
/// needed for this tab.
///
/// Static capsule fill, not `ScrubBarView` -- that view is draggable
/// (Volume/Brightness adjust the actual system value by dragging it);
/// CPU/memory aren't user-adjustable, so a plain non-interactive bar reads
/// correctly rather than implying a control that does nothing.
struct SystemMonitorPageView: View {
    @ObservedObject var source: SystemMonitorSource

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            MetricRow(
                symbolName: "cpu",
                label: "CPU",
                percent: source.hasCPUSample ? source.cpuPercent : nil
            )
            MetricRow(
                symbolName: "memorychip",
                label: "Memory",
                percent: source.memoryPercent
            )
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// One CPU/memory row -- icon, label, and live percentage on top; a thin
/// capsule fill below, same track/fill construction `ScrubBarView` uses
/// (`Capsule().fill(tint.opacity(0.25))` behind `Capsule().fill(tint)`)
/// minus its drag gesture.
private struct MetricRow: View {
    let symbolName: String
    let label: String
    /// `nil` while `SystemMonitorSource` hasn't taken its second poll yet
    /// (CPU only -- memory is always immediately available, see
    /// `SystemMonitorSource.hasCPUSample`'s own doc comment).
    let percent: Double?

    /// Matches `BatteryActivityContent`'s own low/nominal color language
    /// (red once a resource is under real pressure) rather than inventing
    /// a separate threshold scheme -- green/white reads as "fine," red as
    /// "worth noticing."
    private var tint: Color {
        guard let percent else { return .white.opacity(0.4) }
        if percent >= 90 { return .red }
        if percent >= 70 { return .yellow }
        return .green
    }

    private var displayFraction: CGFloat {
        guard let percent else { return 0 }
        return CGFloat(min(100, max(0, percent))) / 100
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: symbolName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))

                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))

                Spacer(minLength: 0)

                Group {
                    if let percent {
                        Text("\(Int(percent.rounded()))%")
                    } else {
                        // Loading state -- see `percent`'s own doc comment
                        // on why CPU starts as `nil` rather than a
                        // misleading `0%` for the first ~4s after launch.
                        Text("--")
                    }
                }
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.15))
                    Capsule()
                        .fill(tint)
                        .frame(width: geometry.size.width * displayFraction)
                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: displayFraction)
                }
            }
            .frame(height: 5)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(percent.map { "\(Int($0.rounded())) percent" } ?? "Loading")
    }
}
