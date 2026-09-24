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
    @Binding var showDetail: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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

    private func toggleDetail() {
        withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.85)) {
            showDetail.toggle()
        }
    }

    var body: some View {
        if showDetail, let snap = weather.visibleSnapshot {
            WeatherDetailView(snapshot: snap, onClose: toggleDetail)
                // Extra bottom room: the panel's rounded bottom corners
                // swallow the last row otherwise.
                .padding(.bottom, 10)
                .transition(.opacity)
        } else {
            clock
        }
    }

    private var clock: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            VStack(spacing: 3) {
                Text(Self.timeFormatter.string(from: timeline.date))
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .monospacedDigit()

                // Date and weather share one secondary line so the card keeps
                // its two-level hierarchy (time hero, one quiet line below).
                HStack(spacing: 6) {
                    Text(Self.dateFormatter.string(from: timeline.date))
                    if let snap = weather.visibleSnapshot {
                        Button(action: toggleDetail) { weatherGlance(snap) }
                            .buttonStyle(SoftPressButtonStyle())
                            .focusEffectDisabled()
                    }
                }
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.6))
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

    /// Glyph + temp only. The quip lives in the hover tooltip so the card
    /// stays calm; the unit comes from the snapshot (chosen by locale).
    private func weatherGlance(_ snap: WeatherSnapshot) -> some View {
        let condition = snap.currentCondition
        let temp = "\(Int(snap.currentTemp.rounded()))°"
        return HStack(spacing: 6) {
            Text("·").foregroundStyle(.white.opacity(0.35))
            Image(systemName: condition.symbol)
                .symbolRenderingMode(.multicolor)
            Text(temp).monospacedDigit()
        }
        .contentShape(Rectangle())
        .help(condition.quip)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(condition.label), \(temp)")
        .accessibilityHint("Shows weather details")
    }
}
