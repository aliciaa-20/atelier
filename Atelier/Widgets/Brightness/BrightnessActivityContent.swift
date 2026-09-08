import SwiftUI

/// A momentary brightness HUD replacement. Mirrors `VolumeActivityContent`.
struct BrightnessActivityContent: LiveActivityContent {
    let percent: Int
    /// Same reasoning as `PeekPlayerView.notchHeight`.
    let notchHeight: CGFloat

    /// New id per instance -- see `VolumeActivityContent.id` for why.
    let id = UUID().uuidString

    private var symbolName: String {
        percent < 34 ? "sun.min.fill" : "sun.max.fill"
    }

    func pillView() -> AnyView {
        AnyView(
            HStack(spacing: 0) {
                Text("\(percent)%")
                    .font(.system(size: 9.5, weight: .medium))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: 28, alignment: .leading)
                    .foregroundStyle(.white)

                Spacer(minLength: 0)

                Image(systemName: symbolName)
                    .foregroundStyle(.yellow)
                    .font(.system(size: 10))
            }
            .padding(.leading, 6)
            .padding(.trailing, 16)
        )
    }

    /// Matches the real macOS brightness OSD -- see
    /// `VolumeActivityContent.peekView`'s doc comment for why this is a
    /// bar, not this app's usual text+percent peek layout.
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
                            .frame(width: geometry.size.width * CGFloat(percent) / 100)
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
