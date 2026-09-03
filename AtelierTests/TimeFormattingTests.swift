import Testing
@testable import Atelier

struct TimeFormattingTests {
    @Test func formatsSecondsUnderAMinute() {
        #expect(TimeFormatting.mmss(45) == "0:45")
    }

    @Test func formatsMinutesAndSeconds() {
        #expect(TimeFormatting.mmss(125) == "2:05")
    }

    @Test func roundsDownFractionalSeconds() {
        #expect(TimeFormatting.mmss(59.9) == "0:59")
    }

    @Test func clampsNegativeToZero() {
        #expect(TimeFormatting.mmss(-3) == "0:00")
    }
}
