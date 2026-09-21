import SwiftUI

private let marqueeGap: CGFloat = 24
private let marqueePointsPerSecond: CGFloat = 18
private let marqueeMinCycleDuration: TimeInterval = 4.5

/// Scrolls text horizontally when it doesn't fit its container, instead of
/// truncating with "…". Rewritten from scratch after the `@State` +
/// `withAnimation(.repeatForever)` version got permanently "stuck" on real
/// hardware after repeated track changes -- confirmed via on-device
/// `os.Logger`/`log stream` capture: `ExpandedPlayerView` received a fresh,
/// correct title on every single poll tick (~4Hz), for every track, with
/// zero exceptions, but the old `MarqueeText`'s own render log fired for only
/// 3 of 5 distinct titles across a 4-minute capture. The data was never the
/// problem -- `.id(text)`-driven state teardown, combined with an animation
/// armed via a bare `DispatchQueue.main.asyncAfter` (untied to SwiftUI's
/// identity/transaction system), could silently miss a reset when the parent
/// reconstructed this view faster than that mechanism could keep up. Two
/// prior patches to the timing/cancellation details both failed on real
/// hardware -- the signal that the *mechanism* was wrong, not the details.
///
/// This version has no animation object, no `Task.sleep`-driven restart, and
/// no persistent "am I currently animating" state to desync. `TimelineView`
/// recomputes the scroll offset as a pure function of wall-clock time on
/// every frame: `offset = f(now - startDate)`. There is nothing to get
/// stuck, because there is nothing being mutated by an animation -- the
/// offset is thrown away and recomputed fresh each frame.
///
/// Product requirements carried over unchanged from the previous version:
/// 1. Container width is passed in explicitly by the caller, not measured
///    at runtime, and `.clipped()` sits on the single outermost
///    `.frame()`-constrained view -- exactly one clip boundary.
/// 2. Continuous one-direction scroll only -- no back-and-forth wobble.
/// 3. No visible restart/snap-back at the loop point: when the text doesn't
///    fit, a second copy renders right after the first (separated by
///    `marqueeGap`), and the offset wraps by exactly one copy-width + gap,
///    so the loop point is invisible.
/// 4. `.id(text)` resets all state cleanly on every track change.
struct MarqueeText: View {
    let text: String
    let font: Font
    let color: Color
    var width: CGFloat = 170
    var height: CGFloat = 20

    var body: some View {
        MarqueeTextCore(text: text, font: font, color: color, width: width, height: height)
            // Forces a brand-new `MarqueeTextCore` identity -- and therefore
            // fresh `@State` (`textWidth`, `startDate`) -- on every distinct
            // `text` value. This is the only piece of manual state-reset
            // machinery left; everything downstream of it is a pure
            // recomputation, not a stateful animation to keep in sync.
            .id(text)
    }
}

/// Does the actual measuring + time-driven scrolling. Split out from
/// `MarqueeText` so `.id(text)` on the outer view can reset this one's
/// `@State` wholesale without `MarqueeText` itself needing any.
private struct MarqueeTextCore: View {
    let text: String
    let font: Font
    let color: Color
    let width: CGFloat
    let height: CGFloat

    /// Measured once per identity (i.e. once per distinct `text`) via
    /// `WidthReader`. Read-only input to the per-frame offset calculation
    /// below -- never mutated by animation logic, only by the one-shot
    /// layout measurement, so there's no race between "what the animation
    /// thinks the width is" and "what it actually is".
    @State private var textWidth: CGFloat = 0

    /// Captured once when this view's state is created (i.e. once per
    /// `.id(text)` reset), and read-only from then on. This *is* the whole
    /// "animation state" -- a single fixed reference point in time. Elapsed
    /// time since it is recomputed fresh every frame by `TimelineView`,
    /// instead of accumulating in a mutable `offset` that could get left in
    /// an inconsistent state.
    @State private var startDate = Date()

    private var needsLoop: Bool { textWidth > width }
    private var loopDistance: CGFloat { textWidth + marqueeGap }
    private var cycleDuration: TimeInterval {
        max(marqueeMinCycleDuration, Double(loopDistance / marqueePointsPerSecond))
    }

    var body: some View {
        Group {
            // Short strings that fit (the common case) render completely
            // outside `TimelineView` -- zero ticks, zero redraw cost, not
            // just a paused schedule. `.periodic` (not `.animation`) caps
            // the looping case's redraw rate at 16fps rather than
            // following the display's own refresh rate (up to 120Hz on
            // ProMotion) -- at `marqueePointsPerSecond` (18pt/s), that's
            // ~1.1pt of motion per tick, well under a pixel's worth of
            // visible steppiness, for a fraction of the continuous
            // redraw/wake-up cost `.animation` would carry for however
            // long a long title is on screen.
            if needsLoop {
                TimelineView(.periodic(from: startDate, by: 1.0 / 16.0)) { context in
                    content(offset: currentOffset(at: context.date))
                }
            } else {
                content(offset: 0)
            }
        }
        .frame(width: width, height: height, alignment: .leading)
        .clipped()
    }

    private func content(offset: CGFloat) -> some View {
        HStack(spacing: marqueeGap) {
            line.background(WidthReader(width: $textWidth))
            if needsLoop {
                line
            }
        }
        .offset(x: offset)
    }

    /// Pure function of elapsed time -- no mutable animation state anywhere
    /// in this call chain. `progress` wraps via `truncatingRemainder`, so
    /// the offset sweeps from `0` to `-loopDistance` and then *jumps* back
    /// to `0` in value -- but because the second copy of the text is
    /// sitting exactly `loopDistance` to the right of the first, that jump
    /// in the offset value lands the visible content in exactly the same
    /// place on screen. That's the "invisible loop point" trick, now driven
    /// by arithmetic instead of a manually re-armed animation.
    private func currentOffset(at date: Date) -> CGFloat {
        let elapsed = date.timeIntervalSince(startDate)
        let cycle = cycleDuration
        guard cycle > 0 else { return 0 }
        let progress = elapsed.truncatingRemainder(dividingBy: cycle) / cycle
        return -loopDistance * CGFloat(progress)
    }

    private var line: some View {
        Text(text)
            .font(font)
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize()
    }
}

/// Measures the text's own intrinsic (unclipped, unconstrained) width by
/// reading the size of its own layout pass -- attached to `line` itself,
/// *before* any `.frame`/`.clipped` constraint is applied further out, so
/// this reads the natural width of the text, not the container's fixed
/// width.
private struct WidthReader: View {
    @Binding var width: CGFloat

    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear { width = proxy.size.width }
        }
    }
}
