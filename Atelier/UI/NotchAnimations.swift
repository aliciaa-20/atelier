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
/// The `dampingFraction: 0.65` on `open` was a starting point for on-device
/// visual tuning, since confirmed (Phase 7) to read as a genuine elastic
/// overshoot -- `peekOpen`/`peekClose` used to carry separate, slightly
/// different-feeling values (0.8/0.92 damping) pending that result. Now
/// that `open`'s tuning is confirmed, peeking reuses `open`/`close`
/// directly rather than parallel constants that could quietly drift apart
/// again -- a hover-open/close and a peek-open/close should read as the
/// exact same motion, just triggered a different way (confirmed on-device:
/// the separate peek curves read as a visibly different, less smooth
/// close than hovering).
enum NotchAnimations {
    static let open: Animation = .spring(response: 0.35, dampingFraction: 0.65)
    static let close: Animation = .spring(response: 0.55, dampingFraction: 0.92)
    static let settleTuck: Animation = .easeOut(duration: 0.12)
    static let settleSpringBack: Animation = .spring(response: 0.35, dampingFraction: 0.5)
}
