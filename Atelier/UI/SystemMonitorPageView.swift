import SwiftUI

/// The `NotchPage.systemMonitor` tab -- CPU load and memory pressure as two
/// ring gauges, shown full-size (unlike the pill's bare percentages, which
/// are squeezed into ~18pt flanks). Sits in the same `expandedSize` frame
/// `ExpandedPlayerView`/`ShelfView` already use when selected via
/// `NotchTabBar` (Invariant 3 -- the panel itself never resizes, only this
/// content frame does), so no new panel size was needed for this tab, and
/// per direct feedback this tap-to-detail view deliberately stays within
/// that same footprint rather than growing a new, taller notch state.
///
/// Ring gauges, not the earlier flat capsule bars -- direct feedback that
/// the capsule version "ain't bad but kinda want it to be more visual,"
/// pointing at exelban/stats (credited in CLAUDE.md as "Stats," already
/// this phase's own reference for the underlying Mach reads) and its own
/// tachometer/gauge widget style as the target. `Kit/Widgets/Tachometer.swift`
/// (pulled via `gh api` as ground truth, per this project's convention of
/// reading real reference source rather than guessing) draws an AppKit
/// `NSBezierPath` arc; this is the native SwiftUI equivalent of the same
/// idea -- `Circle().trim(from:to:)` with a rounded stroke cap -- rather
/// than a literal port, matching how Apple's own Activity rings and
/// Control Center gauges read a live percentage.
///
/// Tapping flips to a plain-language status card per metric -- explicitly
/// *not* Stats' own popup content (user/system/idle split, load averages,
/// wired/compressed page breakdown): direct feedback was that this should
/// read at a glance for someone who'd otherwise have to open Activity
/// Monitor to make sense of it, not hand them more numbers. `Severity`
/// below is the same three-tier language Control Center's own Focus/
/// battery-health copy uses -- a word plus one plain sentence, not a
/// dashboard.
struct SystemMonitorPageView: View {
    @ObservedObject var source: SystemMonitorSource
    @State private var showingDetail = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.35, dampingFraction: 0.85)) {
                showingDetail.toggle()
            }
        } label: {
            Group {
                if showingDetail {
                    VStack(spacing: 6) {
                        StatusCard(
                            metric: .cpu,
                            percent: source.hasCPUSample ? source.cpuPercent : nil
                        )
                        StatusCard(
                            metric: .memory,
                            percent: source.memoryPercent
                        )
                    }
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.97)))
                } else {
                    HStack(spacing: 28) {
                        RingGauge(
                            symbolName: "cpu",
                            label: "CPU",
                            percent: source.hasCPUSample ? source.cpuPercent : nil
                        )
                        RingGauge(
                            symbolName: "memorychip",
                            label: "Memory",
                            percent: source.memoryPercent
                        )
                    }
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 1.03)))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .accessibilityLabel(showingDetail ? "System status detail" : "System status rings")
        .accessibilityHint(showingDetail ? "Press to show gauges" : "Press for a plain-language status")
        .padding(.horizontal, NotchLayout.pageHorizontalInset)
        .padding(.top, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

private enum Metric {
    case cpu, memory

    var symbolName: String {
        switch self {
        case .cpu: "cpu"
        case .memory: "memorychip"
        }
    }

    var name: String {
        switch self {
        case .cpu: "CPU"
        case .memory: "Memory"
        }
    }
}

/// Three tiers, not a raw percentage -- the same "does this need my
/// attention or not" read Battery's own low/nominal color language gives,
/// just named in words instead of relying on color alone (color-blind
/// legibility, and it's the actual thing being communicated on tap).
private enum Severity {
    case comfortable, busy, overloaded

    init(percent: Double?) {
        guard let percent else {
            self = .comfortable
            return
        }
        if percent >= 90 {
            self = .overloaded
        } else if percent >= 70 {
            self = .busy
        } else {
            self = .comfortable
        }
    }

    var word: String {
        switch self {
        case .comfortable: "Comfortable"
        case .busy: "Busy"
        case .overloaded: "Overloaded"
        }
    }

    var tint: Color {
        switch self {
        case .comfortable: .green
        case .busy: .yellow
        case .overloaded: .red
        }
    }

    /// One plain sentence per metric/severity pair -- what a non-technical
    /// person needs to know, not what's technically true. No "pages,"
    /// "ticks," or "wired" anywhere here on purpose.
    func message(for metric: Metric) -> String {
        switch (metric, self) {
        case (.cpu, .comfortable): "Your Mac is running smoothly."
        case (.cpu, .busy): "Your Mac is working a bit harder."
        case (.cpu, .overloaded): "Your Mac is under heavy load."
        case (.memory, .comfortable): "Plenty of memory is free."
        case (.memory, .busy): "Memory is getting full."
        case (.memory, .overloaded): "Memory is almost full."
        }
    }
}

/// One metric's plain-language card: icon, status word, and a single
/// explanatory sentence -- the tap-to-detail content itself, in place of
/// a numbers dashboard. `percent` still drives the color/word, it's just
/// never shown as a bare number here (the ring view already has that).
private struct StatusCard: View {
    let metric: Metric
    let percent: Double?

    private var severity: Severity { Severity(percent: percent) }

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(severity.tint.opacity(0.18))
                Image(systemName: metric.symbolName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(severity.tint)
            }
            .frame(width: 26, height: 26)

            VStack(alignment: .leading, spacing: 1) {
                Text(percent == nil ? "Checking\u{2026}" : severity.word)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)

                Text(percent == nil ? "Getting a first reading." : severity.message(for: metric))
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(metric.name): \(percent == nil ? "Checking" : severity.word)")
        .accessibilityValue(percent == nil ? "Getting a first reading" : severity.message(for: metric))
    }
}

/// One CPU/memory ring -- a track circle behind a trimmed progress arc,
/// icon + live percentage centered inside, label below. Same
/// track/progress construction `ScrubBarView`'s capsule used
/// (`.opacity(0.15)` track, solid tint fill) just traced along a circle
/// instead of a straight line.
private struct RingGauge: View {
    let symbolName: String
    let label: String
    /// `nil` while `SystemMonitorSource` hasn't taken its second poll yet
    /// (CPU only -- memory is always immediately available, see
    /// `SystemMonitorSource.hasCPUSample`'s own doc comment).
    let percent: Double?

    // Sized against the real content budget, not guessed: the tab sits
    // below `NotchController.playerContentHeight` (134pt) minus the tab
    // bar's own vertical footprint (~34pt incl. its top clearance) minus
    // this view's own top padding, leaving ~90pt -- a 64pt ring plus its
    // label fits with margin; 92pt (the first pass) did not and clipped.
    private static let diameter: CGFloat = 64
    private static let lineWidth: CGFloat = 7

    /// Matches `BatteryActivityContent`'s own low/nominal color language
    /// (red once a resource is under real pressure) rather than inventing
    /// a separate threshold scheme -- green/white reads as "fine," red as
    /// "worth noticing." Same thresholds `Severity` uses for the tap-to-
    /// detail card, so color means the same thing in both views.
    private var tint: Color { Severity(percent: percent).tint }

    private var displayFraction: CGFloat {
        guard let percent else { return 0 }
        return CGFloat(min(100, max(0, percent))) / 100
    }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.15), lineWidth: Self.lineWidth)

                // Starts at the top (`-90°` via the `rotationEffect` below),
                // not the default 3-o'clock start -- matches how Apple's own
                // Activity rings and Control Center gauges begin their fill,
                // so the direction of "more full" reads as clockwise from
                // 12 rather than from the right edge.
                Circle()
                    .trim(from: 0, to: displayFraction)
                    .stroke(tint, style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: displayFraction)

                VStack(spacing: 2) {
                    Image(systemName: symbolName)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))

                    Group {
                        if let percent {
                            Text("\(Int(percent.rounded()))%")
                                .contentTransition(.numericText(value: percent))
                                .animation(.snappy(duration: 0.2), value: Int(percent.rounded()))
                        } else {
                            // Loading state -- see `percent`'s own doc
                            // comment on why CPU starts as `nil` rather
                            // than a misleading `0%` for the first ~4s
                            // after launch.
                            Text("--")
                        }
                    }
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                }
            }
            .frame(width: Self.diameter, height: Self.diameter)

            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(percent.map { "\(Int($0.rounded())) percent" } ?? "Loading")
    }
}
