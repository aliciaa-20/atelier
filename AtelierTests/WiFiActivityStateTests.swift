import Testing
@testable import Atelier

struct WiFiActivityStateTests {
    @Test func gainingConnectivityProducesConnected() {
        let result = WiFiActivityState.evaluate(isConnected: true, previouslyConnected: false)
        #expect(result == .connected)
    }

    @Test func losingConnectivityProducesDisconnected() {
        let result = WiFiActivityState.evaluate(isConnected: false, previouslyConnected: true)
        #expect(result == .disconnected)
    }

    @Test func noChangeProducesNoAlert() {
        let result = WiFiActivityState.evaluate(isConnected: true, previouslyConnected: true)
        #expect(result == nil)
    }

    @Test func startupWithNoPriorReadingProducesNoAlert() {
        // The first path update after `NWPathMonitor` starts has nothing
        // to compare against yet -- shouldn't announce a "connected" toast
        // just for the app having launched.
        let result = WiFiActivityState.evaluate(isConnected: true, previouslyConnected: nil)
        #expect(result == nil)
    }
}
