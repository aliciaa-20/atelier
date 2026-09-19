import SwiftUI

/// The compound shape real macOS notches use: the top edge is flush full
/// width, but each top corner immediately curves concave inward as it
/// descends — cutting a small scoop out of our own corner so macOS's own
/// dark menu-bar accent beside the physical notch shows through instead of
/// our shape competing with it at a mismatched radius. Only the bottom
/// corners round in the ordinary (convex) direction.
///
/// Adapted from the algorithm in TheBoredTeam/boring.notch (itself credited
/// there to MrKai77/DynamicNotchKit) — a verified solution to this exact
/// problem rather than a guess.
nonisolated struct NotchShape: Shape {
    var topCornerRadius: CGFloat = 6
    var bottomCornerRadius: CGFloat = 14

    /// Lets the corner radius itself animate across a state transition
    /// (collapsed's sharp notch-cutout radii vs. expanded's softer,
    /// rounder-card radii -- see `NotchRootView.cornerRadii`), instead of
    /// snapping instantly while the frame size eases.
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topCornerRadius, bottomCornerRadius) }
        set {
            topCornerRadius = newValue.first
            bottomCornerRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()

        path.move(to: CGPoint(x: rect.minX, y: rect.minY))

        path.addQuadCurve(
            to: CGPoint(x: rect.minX + topCornerRadius, y: rect.minY + topCornerRadius),
            control: CGPoint(x: rect.minX + topCornerRadius, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.minX + topCornerRadius, y: rect.maxY - bottomCornerRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + topCornerRadius + bottomCornerRadius, y: rect.maxY),
            control: CGPoint(x: rect.minX + topCornerRadius, y: rect.maxY)
        )

        path.addLine(to: CGPoint(x: rect.maxX - topCornerRadius - bottomCornerRadius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - topCornerRadius, y: rect.maxY - bottomCornerRadius),
            control: CGPoint(x: rect.maxX - topCornerRadius, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - topCornerRadius, y: rect.minY + topCornerRadius))

        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - topCornerRadius, y: rect.minY)
        )

        path.closeSubpath()
        return path
    }
}
