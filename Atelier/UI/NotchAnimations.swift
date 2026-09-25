import AppKit
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
    /// With Reduce Motion on, the springs (overshoot, bounce) become short
    /// eased fades -- Apple's guidance for bouncy/parallax motion. Read live
    /// so toggling the setting takes effect on the next animation.
    private static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    static var open: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.35, dampingFraction: 0.65)
    }
    /// `response`/`dampingFraction` retuned again after content switched to
    /// `.transition(.identity)` (see `NotchRootView`) -- with content no
    /// longer fading independently, this spring is now the *entire* close
    /// motion, so its own smoothness matters more than before. Slightly
    /// higher damping than the previous 0.88 softens the tail of the
    /// shrink; a starting point for further tuning, not asserted as final.
    static var close: Animation {
        reduceMotion ? .easeInOut(duration: 0.25) : .spring(response: 0.6, dampingFraction: 0.94)
    }
    /// Small state changes (tab dots, week shifts): damped, no overshoot.
    static var standard: Animation {
        reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.3, dampingFraction: 0.85)
    }
    /// Tab/page changes and other non-hover state changes: a hint of bounce only.
    static var page: Animation {
        reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 0.4, bounce: 0.15)
    }
    /// Press feedback on buttons: fast, slightly bouncy.
    static var press: Animation {
        reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.2, dampingFraction: 0.7)
    }
    /// Drag-handle grow/shrink (scrubber thumb).
    static var grab: Animation {
        reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.3, dampingFraction: 0.75)
    }
    /// The player <-> compact volume/brightness HUD swap, the way Dynamic
    /// Island does it: ONE critically damped spring (damping 1.0, no
    /// overshoot -- it isn't a flick, so no bounce) drives the panel size AND
    /// both contents together. Content scales 0.92 <-> 1 and blurs 6pt <-> 0
    /// while it fades, so the cross-dissolve never shows two sharp layers at
    /// once; the panel morph carries the eye. No timelines, delays or
    /// staggered fades, so a second key press mid-swap just retargets the same
    /// spring from where it is (interruptible), and going back is the exact
    /// reverse path.
    static var hud: Animation {
        reduceMotion ? .easeInOut(duration: 0.15) : .spring(duration: 0.4, bounce: 0)
    }
    static var hudContentScale: CGFloat { reduceMotion ? 1 : 0.92 }
    static var hudContentBlur: CGFloat { reduceMotion ? 0 : 6 }
    static let settleTuck: Animation = .easeOut(duration: 0.12)
    static var settleSpringBack: Animation {
        reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.35, dampingFraction: 0.5)
    }
}
