import SwiftUI

/// A draggable capsule bar shared by Volume's and Brightness's peek HUDs.
/// Live-applies `onScrub` on every drag update (not just on release) --
/// dragging naturally keeps the peek open, since the owning source's
/// `publish()` reschedules its own decay timer on every call, with no
/// separate pause/resume mechanism needed. Mirrors `ExpandedPlayerView`'s
/// `ScrubberView` (`GeometryReader` + `Capsule` track/fill + `DragGesture`,
/// same thicken-while-dragging tactile cue), generalized past time-
/// scrubbing to a plain 0...1 fill fraction.
struct ScrubBarView: View {
    let fillFraction: CGFloat
    let tint: Color
    let onScrub: (Int) -> Void

    @State private var dragging = false
    @State private var dragFraction: CGFloat?

    private var displayedFraction: CGFloat { dragFraction ?? fillFraction }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(tint.opacity(0.25))
                Capsule().fill(tint).frame(width: geometry.size.width * displayedFraction)
            }
            .frame(height: dragging ? 6 : 5)
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        dragging = true
                        let ratio = min(max(value.location.x / geometry.size.width, 0), 1)
                        dragFraction = ratio
                        onScrub(Int((ratio * 100).rounded()))
                    }
                    .onEnded { _ in
                        dragging = false
                        dragFraction = nil
                    }
            )
            .animation(NotchAnimations.grab, value: dragging)
        }
        .frame(height: 8)
    }
}
