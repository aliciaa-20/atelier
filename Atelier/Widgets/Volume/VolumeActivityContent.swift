import SwiftUI

/// A momentary volume HUD replacement -- present only while the pill/peek
/// should show it, `nil` again once `VolumeSource`'s decay timer fires.
/// Mirrors `BatteryActivityContent`'s shape.
struct VolumeActivityContent: LiveActivityContent {
    let percent: Int
    let isMuted: Bool
    /// Same reasoning as `PeekPlayerView.notchHeight`.
    let notchHeight: CGFloat
    /// Applies an absolute level live as the peek's bar is dragged -- see
    /// `VolumeSource.scrub(toPercent:)`.
    let onScrub: (Int) -> Void

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

    /// Sized to match the bare notch's own width exactly (Volume/
    /// Brightness's pill is compact, unlike the wider music pill -- see
    /// `NotchRootView.frameSize`), so icon+percent are grouped tightly and
    /// centered rather than pinned to opposite edges the way the wider
    /// music pill's artwork/waveform layout is -- on the notch's own
    /// width, edge-pinning read as the content bleeding outward past
    /// where there's room for it (on-device feedback).
    func pillView() -> AnyView {
        AnyView(
            HStack(spacing: 4) {
                Image(systemName: symbolName)
                    .foregroundStyle(.white)
                    .font(.system(size: 9))
                Text(isMuted ? "Muted" : "\(percent)%")
                    .font(.system(size: 9, weight: .medium))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(percent)))
                    .animation(.snappy(duration: 0.2), value: percent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)
        )
    }

    /// Matches the real macOS volume/brightness OSD: icon + a single
    /// continuous capsule bar, no numeric label -- not the text+percent
    /// layout the rest of this app's peeks use, deliberately, since this
    /// one HUD replaces a system element people already recognize by
    /// shape. Draggable -- see `ScrubBarView`.
    func peekView() -> AnyView {
        AnyView(
            HStack(spacing: 10) {
                Image(systemName: symbolName)
                    .foregroundStyle(.white)
                    .font(.system(size: 13))
                    .frame(width: 16)

                ScrubBarView(fillFraction: isMuted ? 0 : CGFloat(percent) / 100, tint: .white, label: "Volume", onScrub: onScrub)
            }
            .padding(.leading, 25)
            .padding(.trailing, 24)
            .padding(.bottom, 6)
            .padding(.top, notchHeight + 2)
        )
    }
}
