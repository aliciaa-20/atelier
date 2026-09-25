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
    /// The panel morphing between the player and a compact volume/brightness
    /// HUD: critically damped (no overshoot), 0.4s -- a bouncy or slow spring on a size change the user
    /// didn't trigger by hovering reads as jitter. The content fades are
    /// sequenced strictly one after the other (never both on
    /// screen): player out 0.16s, then the bar in 0.24s; on the way back the bar
    /// out 0.16s, then the player in once the panel has mostly regrown.
    static var hud: Animation {
        reduceMotion ? .easeInOut(duration: 0.15) : .spring(duration: 0.4, bounce: 0)
    }
    static var hudPlayerFade: (hudIn: Animation, hudOut: Animation) {
        (.easeOut(duration: 0.16), .easeOut(duration: 0.24).delay(0.24))
    }
    static var hudBarFade: (hudIn: Animation, hudOut: Animation) {
        (.easeOut(duration: 0.24).delay(0.2), .easeOut(duration: 0.16))
    }
    static let settleTuck: Animation = .easeOut(duration: 0.12)
    static var settleSpringBack: Animation {
        reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.35, dampingFraction: 0.5)
    }
}
