/// A battery condition worth surfacing in the notch. Pure -- no IOKit
/// import -- so the threshold logic is unit-testable independent of the
/// actual power-source polling in `BatterySource`.
///
/// Continuous ambient status, not a one-shot event: `.charging` holds for
/// as long as the charger is connected (not just the moment it's plugged
/// in), same as `.low` holds for as long as the battery stays under the
/// threshold. This only makes sense because Battery is pill-only and never
/// auto-peeks (`BatteryActivityContent.peeksOnChange == false`) -- a
/// genuine notification-shaped one-shot event would need to withdraw
/// itself instead, but ambient status the pill quietly reflects should
/// track the real state directly.
enum BatteryActivityState: Equatable {
    case charging(percent: Int)
    case low(percent: Int)
    case full

    private static let lowThreshold = 20

    /// `nil` means "nothing worth surfacing right now" -- this is what
    /// `BatterySource` publishes as its `LiveActivityContent?` when
    /// nothing has changed enough to matter.
    static func evaluate(percent: Int, isCharging: Bool) -> BatteryActivityState? {
        if isCharging {
            return percent >= 100 ? .full : .charging(percent: percent)
        }
        if percent <= lowThreshold {
            return .low(percent: percent)
        }
        return nil
    }
}
