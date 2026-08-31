import Testing
@testable import Atelier

struct NotchStateTests {
    @Test func hoverStartedExpandsFromCollapsed() {
        let result = NotchStateMachine.reduce(.collapsed, on: .hoverStarted)

        #expect(result == .expanded)
    }
}

extension NotchStateTests {
    @Test func hoverEndedCollapsesFromExpanded() {
        let result = NotchStateMachine.reduce(.expanded, on: .hoverEnded)

        #expect(result == .collapsed)
    }
}
