import SwiftUI

/// Ambient system-resource status -- CPU load and memory pressure.
/// Lowest-priority signal in the stack (see
/// `NotchLiveActivityPriority.systemMonitor`'s own doc comment): unlike
/// Battery, which surfaces a genuine *state change* worth noticing
/// (low, charging, full), this is just background numbers that happen to
/// be true right now, so it only ever reaches the pill when nothing else
/// -- including Battery -- currently has anything to show.
///
/// Pill-only, never auto-peeks -- same reasoning
/// `BatteryActivityContent.peeksOnChange`'s doc comment gives: a peek on
/// every CPU/memory fluctuation would be noise, not information. Unlike
/// Battery, there isn't even a discrete "worth surfacing" threshold here
/// (no equivalent of "low"/"charging") -- it's continuous ambient status
/// for as long as it's the top of the stack.
struct SystemMonitorActivityContent: LiveActivityContent {
    let cpuPercent: Double
    let memoryPercent: Double
    /// Same reasoning as `PeekPlayerView.notchHeight`: the physical notch
    /// cutout has no display pixels, so peek content starts below it.
    let notchHeight: CGFloat

    /// Fixed, not derived from the live percentages -- this is continuous
    /// ambient status like Battery's `.charging`/`.low`, not a sequence of
    /// discrete events, so there's no "identity" worth tracking beyond
    /// "the system monitor has something to show." Keeping it stable
    /// avoids unneeded view-identity churn on every ~4s poll.
    var id: String { "systemMonitor" }

    var peeksOnChange: Bool { false }

    /// `true`, unlike most ambient pill content (Volume/Brightness/Battery
    /// default to `false`) -- those are transient HUDs with no expanded
    /// view of their own, so `NotchRootView`'s hover guard deliberately
    /// ignores hover while they're on top rather than force-opening an
    /// unrelated player. System Monitor is different: it re-publishes
    /// every ~4s indefinitely, so once nothing else is showing it becomes
    /// `topContent` and *stays* there -- inheriting the `false` default
    /// would silently swallow hover-to-open for the rest of the idle
    /// session. It also has a real destination (the systemMonitor tab),
    /// same reasoning `NowPlayingActivityContent.isExpandable` gives.
    var isExpandable: Bool { true }

    private var cpuRounded: Int { Int(cpuPercent.rounded()) }
    private var memoryRounded: Int { Int(memoryPercent.rounded()) }

    /// Text-only both flanks, same ~18pt-per-side budget
    /// `BatteryActivityContent.pillView`'s doc comment documents --
    /// "CPU"/"MEM" labels don't fit that budget alongside a number, so
    /// each flank is a bare percentage instead: CPU on the left, memory on
    /// the right, a fixed order rather than a label, same tradeoff
    /// Battery's own pill makes (time-remaining/percent, no "time"/
    /// "battery" labels either).
    /// Both flanks share one `pillPercent` builder rather than duplicated
    /// modifier chains -- the previous copy-pasted version used identical
    /// modifiers on paper but still read as visibly different sizes
    /// on-device between a 1-digit and 2-digit value ("5%" vs "98%"),
    /// because `frame(maxWidth: 18)` lets `minimumScaleFactor` kick in
    /// independently per string once its natural width nears the cap.
    /// A shared fixed-width frame (18 -> 20, still comfortably inside the
    /// notch's dead-zone budget) removes that per-string variance for the
    /// entire realistic 0-99% range; only the rare literal 100% reading
    /// still leans on `minimumScaleFactor` as a fallback.
    func pillView() -> AnyView {
        AnyView(
            HStack(spacing: 0) {
                pillPercent(cpuRounded, alignment: .leading)
                Spacer(minLength: 0)
                pillPercent(memoryRounded, alignment: .trailing)
            }
            .padding(.leading, 12)
            .padding(.trailing, 12)
        )
    }

    private func pillPercent(_ value: Int, alignment: Alignment) -> some View {
        Text("\(value)%")
            .font(.system(size: 12, weight: .medium))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(width: 20, alignment: alignment)
            .foregroundStyle(.secondary)
    }

    /// Never actually reached in practice (`peeksOnChange == false` means
    /// `LiveActivityCoordinator` never triggers a peek for this content),
    /// but implemented for protocol conformance -- same posture as
    /// `BatteryActivityContent.peekView`, real UI despite the same
    /// constraint, in case a future manual "show peek" path exists.
    func peekView() -> AnyView {
        AnyView(
            HStack(spacing: 8) {
                Image(systemName: "cpu")
                    .foregroundStyle(.secondary)
                Text("CPU \(cpuRounded)%  ·  MEM \(memoryRounded)%")
                    .font(.subheadline)
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 9)
            .padding(.top, notchHeight + 4)
        )
    }
}
