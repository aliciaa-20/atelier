import Testing
@testable import Atelier

struct NotchHoverPolicyTests {
    private func handles(
        hovering: Bool, state: NotchState, expandable: Bool? = false,
        hoversToPeek: Bool = false, hud: Bool = false
    ) -> Bool {
        NotchHoverPolicy.handlesHover(
            hovering: hovering, state: state, topContentIsExpandable: expandable,
            topContentHoversToPeek: hoversToPeek, hudActive: hud)
    }

    // Final review #1: leaving a peek must retract even when non-expandable,
    // non-HUD content (e.g. charging Battery) took over from a joined meeting.
    @Test func exitFromPeekRetractsForNonExpandableNonHUDContent() {
        #expect(handles(hovering: false, state: .peeking))
    }

    @Test func exitFromPeekIsIgnoredWhileAHUDOwnsIt() {
        #expect(!handles(hovering: false, state: .peeking, hud: true))
    }

    @Test func hoverIntoNonExpandableContentIsStillIgnored() {
        #expect(!handles(hovering: true, state: .pill))
        #expect(!handles(hovering: true, state: .peeking))
    }

    @Test func hoverPeekContentHandlesBothDirections() {
        #expect(handles(hovering: true, state: .pill, hoversToPeek: true))
        #expect(handles(hovering: false, state: .peeking, hoversToPeek: true))
    }

    @Test func expandableOrAbsentContentHandlesHover() {
        #expect(handles(hovering: true, state: .pill, expandable: true))
        #expect(handles(hovering: true, state: .collapsed, expandable: nil))
    }

    @Test func expandedAlwaysHandlesExit() {
        #expect(handles(hovering: false, state: .expanded))
    }

    // Final review #4: the initial meeting peek must not depend on the
    // unrelated "Peek on track change" setting.
    @Test func hoverPeekContentPeeksEvenWithTrackChangePeekOff() {
        #expect(NotchHoverPolicy.allowsPeek(peekSettingEnabled: false, contentHoversToPeek: true))
    }

    @Test func ordinaryContentStillFollowsThePeekSetting() {
        #expect(!NotchHoverPolicy.allowsPeek(peekSettingEnabled: false, contentHoversToPeek: false))
        #expect(NotchHoverPolicy.allowsPeek(peekSettingEnabled: true, contentHoversToPeek: false))
    }

    // MARK: replaying a hover-out swallowed mid-animation

    // `onHover` drops an exit that arrives while the open/close/tab spring is
    // running (the hit-test region is moving under the cursor). Nothing
    // replayed it, so a fast flick out during the open left the notch stuck
    // open with `pointerInside` still true.
    @Test func settleRetractsWhenExitWasSwallowedAndPointerIsAway() {
        #expect(NotchHoverPolicy.shouldRetractAfterSettle(state: .expanded, pointerOverPanel: false, pointerInsideFlag: true))
        #expect(NotchHoverPolicy.shouldRetractAfterSettle(state: .peeking, pointerOverPanel: false, pointerInsideFlag: true))
    }

    @Test func settleDoesNothingWhilePointerIsStillOverThePanel() {
        #expect(!NotchHoverPolicy.shouldRetractAfterSettle(state: .expanded, pointerOverPanel: true, pointerInsideFlag: true))
    }

    @Test func settleDoesNothingWhenTheExitWasAlreadyHandled() {
        // Flag already false: the exit got through normally, or the pointer
        // never entered (e.g. a track-change peek) -- don't retract it.
        #expect(!NotchHoverPolicy.shouldRetractAfterSettle(state: .expanded, pointerOverPanel: false, pointerInsideFlag: false))
        #expect(!NotchHoverPolicy.shouldRetractAfterSettle(state: .peeking, pointerOverPanel: false, pointerInsideFlag: false))
    }

    @Test func settleOnlyAppliesToOpenStates() {
        for state in [NotchState.collapsed, .pill, .shelf] {
            #expect(!NotchHoverPolicy.shouldRetractAfterSettle(state: state, pointerOverPanel: false, pointerInsideFlag: true))
        }
    }
}

