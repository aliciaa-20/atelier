import Foundation

/// Adapted from IuCC123/BendMac's `BendMath.swift` (MIT). Blur-led motion:
/// the physical lid supplies most of the rotation. Works in screen-height
/// units so Retina scaling never alters the fold.
enum BendMath {
    /// Smoothstep-eased fold amount: 0 at `clearAngle`, ramping to 1 as the
    /// lid closes down toward 12° (its practical fully-closed floor).
    /// `max(1, clearAngle - 12)` keeps the denominator sane even if
    /// `clearAngle` is set at or below 13°.
    static func progress(angle: Double, clearAngle: Double) -> Double {
        let t = min(1, max(0, (clearAngle - angle) / max(1, clearAngle - 12)))
        return t * t * (3 - 2 * t)
    }

    /// Exponential glide from `current` toward `target` over `dt` seconds
    /// (clamped to 0.1s so a stalled run loop can't overshoot), snapping to
    /// `target` once within 0.0001 so the animation settles instead of
    /// crawling asymptotically forever.
    static func smooth(current: Double, target: Double, dt: Double) -> Double {
        let next = current + (target - current) * (1 - exp(-min(dt, 0.1) / 0.075))
        return abs(next - target) < 0.0001 ? target : next
    }

    /// Throttle for idle-armed snapshot refresh (see `DesktopCapture.snapshot()`):
    /// true on the first call (`lastSnapshotTime == nil`) or once `interval`
    /// seconds have passed since the last one.
    static func shouldRefreshSnapshot(now: Double, lastSnapshotTime: Double?, interval: Double) -> Bool {
        guard let lastSnapshotTime else { return true }
        return now - lastSnapshotTime >= interval
    }
}
