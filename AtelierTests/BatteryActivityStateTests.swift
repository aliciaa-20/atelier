import Testing
@testable import Atelier

struct BatteryActivityStateTests {
    @Test func justStartedChargingProducesChargingState() {
        let result = BatteryActivityState.evaluate(percent: 40, isCharging: true, wasCharging: false)
        #expect(result == .charging)
    }

    @Test func alreadyChargingProducesNoNewAlert() {
        let result = BatteryActivityState.evaluate(percent: 41, isCharging: true, wasCharging: true)
        #expect(result == nil)
    }

    @Test func lowBatteryUnplugged() {
        let result = BatteryActivityState.evaluate(percent: 20, isCharging: false, wasCharging: false)
        #expect(result == .low(percent: 20))
    }

    @Test func aboveLowThresholdProducesNoAlert() {
        let result = BatteryActivityState.evaluate(percent: 21, isCharging: false, wasCharging: false)
        #expect(result == nil)
    }

    @Test func fullWhilePluggedIn() {
        let result = BatteryActivityState.evaluate(percent: 100, isCharging: true, wasCharging: true)
        #expect(result == .full)
    }

    @Test func hundredPercentWhileUnpluggedIsNotFull() {
        let result = BatteryActivityState.evaluate(percent: 100, isCharging: false, wasCharging: false)
        #expect(result == nil)
    }
}
