import CoreGraphics

/// Pure math for the scroll-style week swipe: turns the total horizontal
/// distance a finger has dragged into "how many days have we moved" plus a
/// fractional position toward the next day. Foundation/CoreGraphics only,
/// like `CalendarMath` -- no AppKit, no `NSEvent`.
enum CalendarScrub {
    /// Points of drag per day. A starting value -- tune on-device.
    static let defaultStep: CGFloat = 46

    /// `dayOffset` is the whole number of days moved (positive = later);
    /// `fraction` is how far past that day the finger is, in -0.5...0.5.
    /// Rounding (not truncating) means the selection commits at the
    /// midpoint between two days, so `fraction` is continuous across the
    /// commit -- the moving indicator never jumps.
    static func resolve(totalDX: CGFloat, step: CGFloat = defaultStep) -> (dayOffset: Int, fraction: CGFloat) {
        guard step > 0 else { return (0, 0) }
        let days = totalDX / step
        let offset = days.rounded()
        return (Int(offset), days - offset)
    }
}
