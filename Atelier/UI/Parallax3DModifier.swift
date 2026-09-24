import SwiftUI

/// Subtle hover-driven 3D tilt + scale, applied to the lock-screen card's
/// collapsed artwork. Adapted from Ebullioscopic/Atoll's
/// `View+Parallax3D.swift` (read via `gh api` per
/// check-reference-apps-first) -- simplified to a fixed intensity instead
/// of a user-configurable setting (this app has no settings surface for
/// this kind of thing, per the design spec's YAGNI note).
private struct Parallax3DModifier: ViewModifier {
    private static let intensity: Double = 6

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var offset: CGSize = .zero
    @State private var isHovering = false
    @State private var viewSize: CGSize = .zero

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .overlay(
                GeometryReader { proxy in
                    Color.clear
                        .allowsHitTesting(false)
                        .onAppear { viewSize = proxy.size }
                        .onChange(of: proxy.size) { _, newSize in viewSize = newSize }
                }
            )
            .onContinuousHover { phase in
                // Tilt/scale is exactly the kind of motion Reduce Motion asks to drop.
                guard !reduceMotion else { return }
                switch phase {
                case .active(let location):
                    guard viewSize.width > 0, viewSize.height > 0 else { return }
                    let x = (location.x / viewSize.width) * 2 - 1
                    let y = (location.y / viewSize.height) * 2 - 1
                    withAnimation(.interactiveSpring(response: 0.1, dampingFraction: 0.5)) {
                        offset = CGSize(width: x, height: y)
                        isHovering = true
                    }
                case .ended:
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
                        offset = .zero
                        isHovering = false
                    }
                }
            }
            .rotation3DEffect(.degrees(offset.height * Self.intensity), axis: (x: 1, y: 0, z: 0))
            .rotation3DEffect(.degrees(offset.width * -Self.intensity), axis: (x: 0, y: 1, z: 0))
            .scaleEffect(isHovering ? 1.04 : 1.0)
    }
}

extension View {
    func parallax3D() -> some View {
        modifier(Parallax3DModifier())
    }
}
