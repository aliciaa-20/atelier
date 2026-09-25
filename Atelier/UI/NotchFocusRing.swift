import SwiftUI

extension View {
    /// A thin white ring drawn only while this control has keyboard focus.
    /// The system focus ring is switched off on the notch (it read as a stray
    /// bright rectangle on such a small panel, see ExpandedPlayerView), which
    /// left keyboard users with no focus indication at all. Apply inside a
    /// button style's `makeBody` so `isFocused` is read within the button's
    /// own focus scope.
    func notchFocusRing(cornerRadius: CGFloat = 8) -> some View {
        modifier(NotchFocusRingModifier(cornerRadius: cornerRadius))
    }
}

private struct NotchFocusRingModifier: ViewModifier {
    @Environment(\.isFocused) private var isFocused
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content.overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(.white.opacity(0.75), lineWidth: 1.5)
                .padding(-2)
                .opacity(isFocused ? 1 : 0)
                .allowsHitTesting(false)
        }
    }
}
