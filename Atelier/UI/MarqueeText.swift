import SwiftUI

/// Scrolls text horizontally when it doesn't fit its container, instead of
/// truncating with "…". Two real bugs in earlier versions drove this
/// shape:
///
/// 1. A `GeometryReader`-measured container width, combined with a
///    `.clipped()` buried inside a nested view, let the scrolling text
///    bleed past the panel's own edges once actually exercised with a long
///    title — `containerWidth` is now passed in explicitly (the caller
///    already knows it; every call site uses a fixed width) instead of
///    measured at runtime, and `.clipped()` sits on the outermost, already
///    `.frame()`-constrained view so there's exactly one clip boundary,
///    not a chain of them.
/// 2. `.repeatForever(autoreverses: true)` scrolls right, then *back*
///    right-to-left, forever — a back-and-forth wobble, not what a real
///    marquee does. This scrolls left once, snaps back to the start with
///    no visible animation, pauses, and repeats — via `withAnimation`'s
///    completion handler rather than the declarative `.animation(value:)`
///    form, since that form has no "animate one way, reset instantly"
///    primitive.
///
/// `.id(text)` resets all state cleanly on every track change.
struct MarqueeText: View {
    let text: String
    let font: Font
    let color: Color
    var width: CGFloat = 170
    var height: CGFloat = 20

    var body: some View {
        MarqueeTextContent(text: text, font: font, color: color, containerWidth: width)
            .frame(width: width, height: height, alignment: .leading)
            .clipped()
            .id(text)
    }
}

private struct MarqueeTextContent: View {
    let text: String
    let font: Font
    let color: Color
    let containerWidth: CGFloat

    @State private var textWidth: CGFloat = 0
    @State private var offset: CGFloat = 0

    private var overflow: CGFloat { max(0, textWidth - containerWidth) }

    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize()
            .background(WidthReader(width: $textWidth))
            .offset(x: offset)
            .onChange(of: textWidth) { _, newValue in
                guard newValue > 0 else { return }
                scheduleScroll()
            }
    }

    private func scheduleScroll() {
        guard overflow > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            withAnimation(.easeInOut(duration: max(3.5, overflow / 11))) {
                offset = -overflow
            } completion: {
                // Hold the fully-scrolled position (the title's end) on
                // screen for a beat before wrapping, instead of snapping
                // back the instant the scroll finishes.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                    offset = 0
                    scheduleScroll()
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
