import Testing
@testable import Atelier

struct MediaKeyMappingTests {
    @Test func soundUpMapsToVolumeUp() {
        #expect(MediaKeyMapping.action(forKeyCode: 0) == .volumeUp)
    }

    @Test func soundDownMapsToVolumeDown() {
        #expect(MediaKeyMapping.action(forKeyCode: 1) == .volumeDown)
    }

    @Test func brightnessUpMapsCorrectly() {
        #expect(MediaKeyMapping.action(forKeyCode: 2) == .brightnessUp)
    }

    @Test func brightnessDownMapsCorrectly() {
        #expect(MediaKeyMapping.action(forKeyCode: 3) == .brightnessDown)
    }

    @Test func muteMapsCorrectly() {
        #expect(MediaKeyMapping.action(forKeyCode: 7) == .mute)
    }

    @Test func unrecognizedKeyCodeMapsToNil() {
        #expect(MediaKeyMapping.action(forKeyCode: 99) == nil)
    }

    @Test func successfulApplySuppressesTheEvent() {
        // The stock HUD must not show when we already applied the change.
        #expect(MediaKeyMapping.shouldSuppressEvent(for: .volumeUp, applySucceeded: true))
    }

    @Test func failedApplyFailsOpenAndLetsTheEventThrough() {
        // Fail-open per the Phase 8 design spec: a brightness call that
        // couldn't be applied (missing/broken private symbols) must let
        // the key event pass through so the stock HUD still appears,
        // rather than the key silently doing nothing.
        #expect(!MediaKeyMapping.shouldSuppressEvent(for: .brightnessUp, applySucceeded: false))
    }
}
