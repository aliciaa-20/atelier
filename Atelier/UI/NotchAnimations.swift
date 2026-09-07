import SwiftUI

/// The notch's open/close/peek/settle transition curves, named and
/// centralized instead of scattered inline literals — same shape as
/// dynamicnotch's `NotchAnimations.swift` (read via `gh api` during
/// Phase 7 design), though Atelier keeps fixed values rather than
/// user-selectable presets.
///
/// `open`'s damping is deliberately lower than `close`'s — see the Phase
/// 7 spec's Section 3: the frame-size interpolation between
/// `NotchViewModel.currentSize` values is what SwiftUI already animates,
/// so an underdamped `open` produces a visible overshoot ("jelly" feel)
/// on that existing geometry, with no new `scaleEffect` layer. A
/// symmetric overshoot on `close`/`peekClose` would read as the panel
/// bouncing back open, which looks like a bug — so those stay damped.
///
/// The `dampingFraction: 0.65` on `open` is a starting point for on-device
/// visual tuning; it requires human observation of the running app to
/// determine whether the overshoot reads as elastic/natural or needs
/// adjustment. `peekOpen` is untouched pending the result of tuning `open`.
enum NotchAnimations {
    static let open: Animation = .spring(response: 0.35, dampingFraction: 0.65)
    static let close: Animation = .spring(response: 0.55, dampingFraction: 0.92)
    static let peekOpen: Animation = .spring(response: 0.35, dampingFraction: 0.8)
    static let peekClose: Animation = .spring(response: 0.55, dampingFraction: 0.92)
    static let settleTuck: Animation = .easeOut(duration: 0.12)
    static let settleSpringBack: Animation = .spring(response: 0.35, dampingFraction: 0.5)
}
