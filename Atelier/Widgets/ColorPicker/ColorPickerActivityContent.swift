import SwiftUI

/// A one-shot peek showing the color just picked with `NSColorSampler` --
/// swatch + hex string, mirroring `VolumeActivityContent`'s "momentary HUD
/// replacement" shape (self-clearing via `ColorPickerSource`'s decay timer,
/// not a persistent pill). Deliberately does not override `isExpandable`
/// (defaults `false`) or `peeksOnChange` (defaults `true`): a picked color
/// is exactly the "deliberate user action, pop a peek" case the default
/// was written for, unlike Battery/ScreenRecording's ambient states.
struct ColorPickerActivityContent: LiveActivityContent {
    let color: NSColor
    let hex: String
    /// Same reasoning as `PeekPlayerView.notchHeight`.
    let notchHeight: CGFloat

    /// Every pick is a new id, same reasoning as `VolumeActivityContent`'s
    /// own per-press `UUID` -- picking the same color twice in a row should
    /// still re-pop the peek.
    let id = UUID().uuidString

    /// `isExpandable` defaulting `false` routes this through
    /// `NotchRootView`'s `compactPeekSize`, matching Volume/Brightness's
    /// own compact HUD rather than the wider now-playing peek layout.
    func pillView() -> AnyView {
        AnyView(
            HStack(spacing: 6) {
                Circle()
                    .fill(Color(color))
                    .frame(width: 8, height: 8)
                Text(hex)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Picked color \(hex)")
        )
    }

    func peekView() -> AnyView {
        AnyView(
            HStack(spacing: 10) {
                Circle()
                    .fill(Color(color))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.3), lineWidth: 1))
                    .frame(width: 16, height: 16)
                Text(hex)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, NotchLayout.peekHorizontalPadding)
            .padding(.bottom, NotchLayout.peekEdgeGap)
            .padding(.top, notchHeight + NotchLayout.peekEdgeGap)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Picked color \(hex)")
        )
    }
}
