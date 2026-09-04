import SwiftUI

/// Scrolls text horizontally when it doesn't fit its container, instead of
/// truncating with "…". Real bugs in earlier versions drove this shape:
///
/// 1. A `GeometryReader`-measured container width, combined with a
///    `.clipped()` buried inside a nested view, let the scrolling text
///    bleed past the panel's own edges once actually exercised with a long
///    title — `containerWidth` is now passed in explicitly (the caller
///    already knows it; every call site uses a fixed width) instead of
///    measured at runtime, and `.clipped()` sits on the outermost, already
///    `.frame()`-constrained view so there's exactly one clip boundary,
///    not a chain of them.
/// 2. `.repeatForever(autoreverses: true)` scrolled right, then *back*
///    right-to-left, forever — a back-and-forth wobble, not what a real
///    marquee does.
/// 3. A "scroll to the end, snap back to the start, pause" cycle read as
///    restarting rather than continuing — a real ticker never resets, it
///    keeps moving. This renders a second copy of the text right after the
///    first (separated by a gap) and animates a continuous, non-reversing
///    linear scroll by exactly one copy-width + gap — at that point the
///    second copy sits exactly where the first started, so the loop point
///    is invisible instead of a visible jump back to the start.
///
/// `.id(text)` resets all state cleanly on every track change.
struct MarqueeText: View {
    let text: String
    let font: Font
    let color: Color
    var width: CGFloat = 170
    var height: CGFloat = 20

    private static let gap: CGFloat = 24

    @State private var textWidth: CGFloat = 0
    @State private var looping = false
    @State private var offset: CGFloat = 0

    var body: some View {
        HStack(spacing: Self.gap) {
            line.background(WidthReader(width: $textWidth))
            if looping {
                line
            }
        }
        .offset(x: offset)
        .frame(width: width, height: height, alignment: .leading)
        .clipped()
        .id(text)
        .onChange(of: textWidth) { _, newValue in
            guard newValue > 0, newValue > width, !looping else { return }
            startLooping(textWidth: newValue)
        }
    }

    private var line: some View {
        Text(text)
            .font(font)
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize()
    }

    private func startLooping(textWidth: CGFloat) {
        let distance = textWidth + Self.gap
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            looping = true
            // The second copy has to actually be laid out (one runloop
            // turn) before animating past it, or the jump-to-loop-point is
            // visible for one frame instead of seamless.
            DispatchQueue.main.async {
                withAnimation(.linear(duration: max(4.5, distance / 18)).repeatForever(autoreverses: false)) {
                    offset = -distance
                }
            }
        }
    }
}

private struct WidthReader: View {
    @Binding var width: CGFloat

    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear { width = proxy.size.width }
        }
    }
}
