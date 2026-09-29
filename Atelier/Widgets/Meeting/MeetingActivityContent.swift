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
        case .imminent: "\(meeting.title), video call starting soon. Join available."
        case .started: "\(meeting.title), video call started. Join available."
        }
    }

    @ViewBuilder private var countdown: some View {
        switch phase {
        case .imminent: Text(timerInterval: countdownRange, countsDown: true, showsHours: false)
        case .started: Text("Started")
        }
    }

    func pillView() -> AnyView {
        AnyView(
            HStack(spacing: 5) {
                Image(systemName: "video.fill").font(.system(size: 9, weight: .semibold))
                countdown
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spokenLabel)
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
                        .foregroundStyle(.white.opacity(0.7))
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
