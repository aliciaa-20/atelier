/// A battery condition worth surfacing in the notch. Pure -- no IOKit
/// import -- so the threshold logic is unit-testable independent of the
/// actual power-source polling in `BatterySource`.
enum BatteryActivityState: Equatable {
    case charging
    case low(percent: Int)
    case full

    private static let lowThreshold = 20

    /// `nil` means "nothing worth surfacing right now" -- this is what
    /// `BatterySource` publishes as its `LiveActivityContent?` when
    /// nothing has changed enough to matter.
    static func evaluate(percent: Int, isCharging: Bool, wasCharging: Bool) -> BatteryActivityState? {
        if isCharging && !wasCharging {
            return .charging
        }
        if isCharging && percent >= 100 {
            return .full
        }
        if !isCharging && percent <= lowThreshold {
            return .low(percent: percent)
        }
        return nil
    }
}
