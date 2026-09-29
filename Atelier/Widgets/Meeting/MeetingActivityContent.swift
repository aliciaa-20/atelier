import SwiftUI

/// Meeting Join's pill + compact peek. The countdown is
/// `Text(timerInterval:)` over a *fixed* range, so nothing of ours ticks and
/// a re-evaluated body can never build an inverted range.
struct MeetingActivityContent: LiveActivityContent {
    let meeting: MeetingCandidate
    let phase: MeetingPhase
    /// Same reasoning as `PeekPlayerView.notchHeight`.
    let notchHeight: CGFloat
    let onJoin: () -> Void

    /// Phase is part of the id: `.imminent` -> `.started` is a content change,
    /// but `peeksOnChange` is false for `.started` so it never re-peeks.
    var id: String { "meeting:\(meeting.id):\(phase)" }
    var peeksOnChange: Bool { phase == .imminent }
    var hoversToPeek: Bool { true }

    private var countdownRange: ClosedRange<Date> {
        meeting.start.addingTimeInterval(-MeetingSchedule.leadTime)...meeting.start
    }

    private var spokenLabel: String {
        switch phase {
        case .imminent: "\(meeting.title), video call starting soon"
        case .started: "\(meeting.title), video call started"
        }
    }

    @ViewBuilder private var countdown: some View {
        switch phase {
        case .imminent: Text(timerInterval: countdownRange, countsDown: true, showsHours: false)
        case .started: Text("Started")
        }
    }

    /// Short enough for a flank: the pill's middle is the physical notch, so
    /// content goes in the two ears (like `BatteryActivityContent`), never
    /// centred, and the text is the compact `MeetingCountdown` form. The 1 Hz
    /// tick exists only while the pill is showing the last two minutes.
    @ViewBuilder private var pillCountdown: some View {
        switch phase {
        case .imminent:
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(MeetingCountdown.pillText(remaining: meeting.start.timeIntervalSince(context.date)))
            }
        case .started:
            Text("Now")
        }
    }

    func pillView() -> AnyView {
        AnyView(
            HStack(spacing: 0) {
                Image(systemName: "video.fill")
                    .font(.system(size: 10, weight: .semibold))
                Spacer(minLength: 0)
                pillCountdown
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .lineLimit(1)
                    .fixedSize()
            }
            .foregroundStyle(.white)
            // Same 12pt edge inset as `BatteryActivityContent`'s pill; each
            // flank is ~32pt (pillExtraWidth / 2), and "44s" at 10pt is ~17pt.
            .padding(.horizontal, 12)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spokenLabel)
            // The pill has no visible button (Join lives in the hover peek),
            // so VoiceOver users, who can't hover, get it as an action.
            .accessibilityAction(named: "Join meeting", onJoin)
        )
    }

    func peekView() -> AnyView {
        AnyView(
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(meeting.title)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    countdown
                        .font(.system(size: 11).monospacedDigit())
                        .dimmedText()
                }
                Spacer(minLength: 8)
                Button("Join", action: onJoin)
                    .buttonStyle(MeetingJoinButtonStyle())
                    .help("Open the meeting link")
            }
            .foregroundStyle(.white)
            .padding(.horizontal, NotchLayout.peekHorizontalPadding)
            .padding(.bottom, NotchLayout.peekEdgeGap)
            .padding(.top, notchHeight + NotchLayout.peekEdgeGap)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(spokenLabel)
        )
    }
}

/// Capsule button with press feedback (scale via `NotchAnimations.press`).
private struct MeetingJoinButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.green))
            .foregroundStyle(.black)
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(NotchAnimations.press, value: configuration.isPressed)
    }
}
