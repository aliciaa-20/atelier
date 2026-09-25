import SwiftUI

/// A momentary brightness HUD replacement. Mirrors `VolumeActivityContent`.
struct BrightnessActivityContent: LiveActivityContent {
    let percent: Int
    /// Same reasoning as `PeekPlayerView.notchHeight`.
    let notchHeight: CGFloat
    /// Applies an absolute level live as the peek's bar is dragged -- see
    /// `BrightnessSource.scrub(toPercent:)`.
    let onScrub: (Int) -> Void

    /// New id per instance -- see `VolumeActivityContent.id` for why.
    let id = UUID().uuidString

    private var symbolName: String {
        percent < 34 ? "sun.min.fill" : "sun.max.fill"
    }

    /// See `VolumeActivityContent.pillView`'s doc comment -- same
    /// notch-width-compact, centered, tightly-grouped treatment.
    func pillView() -> AnyView {
        AnyView(
            HStack(spacing: 4) {
                Image(systemName: symbolName)
                    .foregroundStyle(.white)
                    .font(.system(size: 10))
                Text("\(percent)%")
                    .font(.system(size: 10, weight: .medium))
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

    /// Matches the real macOS brightness OSD -- see
    /// `VolumeActivityContent.peekView`'s doc comment for why this is a
    /// bar, not this app's usual text+percent peek layout. Draggable --
    /// see `ScrubBarView`.
    func peekView() -> AnyView {
        AnyView(
            HStack(spacing: 10) {
                Image(systemName: symbolName)
                    .foregroundStyle(.white)
                    .font(.system(size: 13))
                    .frame(width: 16)

                ScrubBarView(fillFraction: CGFloat(percent) / 100, tint: .white, label: "Brightness", onScrub: onScrub)
            }
            .padding(.leading, 25)
            .padding(.trailing, 24)
            .padding(.bottom, 6)
            .padding(.top, notchHeight + 2)
        )
    }
}
