import Testing
@testable import Atelier

struct BatteryActivityStateTests {
    @Test func chargingProducesChargingStateWithPercent() {
        let result = BatteryActivityState.evaluate(percent: 40, isCharging: true)
        #expect(result == .charging(percent: 40))
    }

    @Test func chargingStatePersistsAsLongAsPluggedIn() {
        // Ambient status, not a one-shot event: a later poll while still
        // charging keeps producing .charging (with the live percent), not
        // nil -- Battery is pill-only and never auto-peeks, so there's no
        // reason for this to withdraw itself between polls.
        let result = BatteryActivityState.evaluate(percent: 41, isCharging: true)
        #expect(result == .charging(percent: 41))
    }

    @Test func lowBatteryUnplugged() {
        let result = BatteryActivityState.evaluate(percent: 20, isCharging: false)
        #expect(result == .low(percent: 20))
    }

    @Test func aboveLowThresholdProducesNoAlert() {
        let result = BatteryActivityState.evaluate(percent: 21, isCharging: false)
        #expect(result == nil)
    }

    @Test func fullWhilePluggedIn() {
        let result = BatteryActivityState.evaluate(percent: 100, isCharging: true)
        #expect(result == .full)
    }

    @Test func hundredPercentWhileUnpluggedIsNotFull() {
        let result = BatteryActivityState.evaluate(percent: 100, isCharging: false)
        #expect(result == nil)
    }
}
