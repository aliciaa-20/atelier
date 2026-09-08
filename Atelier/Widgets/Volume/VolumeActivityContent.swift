import SwiftUI

/// A momentary volume HUD replacement -- present only while the pill/peek
/// should show it, `nil` again once `VolumeSource`'s decay timer fires.
/// Mirrors `BatteryActivityContent`'s shape.
struct VolumeActivityContent: LiveActivityContent {
    let percent: Int
    let isMuted: Bool
    /// Same reasoning as `PeekPlayerView.notchHeight`.
    let notchHeight: CGFloat

    /// Every key press is a new id -- unlike Battery's stable per-state id,
    /// a real system HUD re-pops its peek on every press even if the
    /// percent lands on the same value twice in a row (e.g. already at
    /// 100%). `UUID` per instance achieves that without `VolumeSource`
    /// tracking a monotonic counter itself.
    let id = UUID().uuidString

    private var symbolName: String {
        if isMuted || percent == 0 { return "speaker.slash.fill" }
        if percent < 34 { return "speaker.wave.1.fill" }
        if percent < 67 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }

    func pillView() -> AnyView {
        AnyView(
            HStack(spacing: 0) {
                Text(isMuted ? "Muted" : "\(percent)%")
                    .font(.system(size: 9.5, weight: .medium))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: 34, alignment: .leading)
                    .foregroundStyle(.white)

                Spacer(minLength: 0)

                Image(systemName: symbolName)
                    .foregroundStyle(.white)
                    .font(.system(size: 10))
            }
            .padding(.leading, 6)
            .padding(.trailing, 16)
        )
    }

    /// Matches the real macOS volume/brightness OSD: icon + a single
    /// continuous capsule bar, no numeric label -- not the text+percent
    /// layout the rest of this app's peeks use, deliberately, since this
    /// one HUD replaces a system element people already recognize by
    /// shape.
    func peekView() -> AnyView {
        AnyView(
            HStack(spacing: 10) {
                Image(systemName: symbolName)
                    .foregroundStyle(.white)
                    .font(.system(size: 15))
                    .frame(width: 18)

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.25))
                        Capsule()
                            .fill(Color.white)
                            .frame(width: geometry.size.width * (isMuted ? 0 : CGFloat(percent) / 100))
                    }
                }
                .frame(height: 5)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 9)
            .padding(.top, notchHeight + 4)
        )
    }
}
