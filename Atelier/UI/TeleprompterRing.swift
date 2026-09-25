import SwiftUI

/// A small Activity-style progress ring with the time centered inside.
/// Same track/progress construction as `RingGauge` in
/// `SystemMonitorPageView` (12 o'clock start, round cap, 15% track), but a
/// separate view: that one is private, 64pt, and carries an icon + label.
/// ~28pt is tight for text, so the label scales down; confirm on-device.
struct TeleprompterRing: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let fraction: Double
    /// Centered text, e.g. "2:41" (time remaining).
    let label: String
    /// Tooltip / VoiceOver value, e.g. "0:32 of 3:10".
    let detail: String

    static let diameter: CGFloat = 28
    private static let lineWidth: CGFloat = 2.5

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.15), lineWidth: Self.lineWidth)
            Circle()
                .trim(from: 0, to: CGFloat(min(max(fraction, 0), 1)))
                .stroke(Color.white, style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                // Glides between ticks like Apple's own rings.
                .animation(reduceMotion ? nil : .smooth(duration: 0.4), value: fraction)
            Text(label)
                .font(.system(size: 8, weight: .semibold).monospacedDigit())
                .minimumScaleFactor(0.7)
                .lineLimit(1)
                .foregroundStyle(.white)
                .padding(Self.lineWidth + 1)
        }
        .frame(width: Self.diameter, height: Self.diameter)
        .help(detail)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Time remaining \(label)")
        .accessibilityValue(detail)
    }
}

/// Re-renders its content on a fixed schedule only while `active`. When
/// idle it renders once and costs nothing (the same "skip the ticking path
/// entirely" rule `MarqueeText` follows).
struct TeleprompterTicker<Content: View>: View {
    let interval: TimeInterval
    let active: Bool
    @ViewBuilder let content: (Date) -> Content

    var body: some View {
        if active {
            TimelineView(.periodic(from: .now, by: interval)) { context in
                content(context.date)
            }
        } else {
            content(.now)
        }
    }
}
