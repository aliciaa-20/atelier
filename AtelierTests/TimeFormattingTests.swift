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

    @Test func hoursAndMinutesUnderAnHour() {
        #expect(TimeFormatting.hoursAndMinutes(14 * 60) == "14m")
    }

    @Test func hoursAndMinutesOverAnHour() {
        #expect(TimeFormatting.hoursAndMinutes(2 * 3600 + 14 * 60) == "2h 14m")
    }

    @Test func hoursAndMinutesNilMeansStillCalculating() {
        #expect(TimeFormatting.hoursAndMinutes(nil) == nil)
    }

    @Test func hoursAndMinutesNegativeSentinelMeansStillCalculating() {
        // Apple's own documented sentinel for kIOPSTimeToEmptyKey/
        // kIOPSTimeToFullChargeKey (-1) means "still calculating".
        #expect(TimeFormatting.hoursAndMinutes(-1) == nil)
    }
}
