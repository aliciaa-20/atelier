import Foundation
import Testing
@testable import Atelier

struct BendMathTests {
    // MARK: - progress

    @Test func progressAtClearAngleIsZero() {
        #expect(BendMath.progress(angle: 105, clearAngle: 105) == 0)
    }

    @Test func progressAboveClearAngleClampsToZero() {
        // Lid open wider than the clear angle must never produce a negative fold.
        #expect(BendMath.progress(angle: 130, clearAngle: 105) == 0)
    }

    @Test func progressAtTwelveDegreesClampsToOne() {
        // 12° is the reference app's practical fully-closed floor.
        #expect(BendMath.progress(angle: 12, clearAngle: 105) == 1)
    }

    @Test func progressBelowTwelveDegreesStillClampsToOne() {
        #expect(BendMath.progress(angle: 5, clearAngle: 105) == 1)
    }

    @Test func progressAtMidpointAngleIsExactlyOneHalf() {
        // Midpoint of the 12...clearAngle range smoothsteps to exactly 0.5
        // (t=0.5 -> t*t*(3-2t) = 0.25*2 = 0.5), a clean value to pin the curve to.
        let clearAngle = 105.0
        let midAngle = (clearAngle + 12) / 2
        #expect(BendMath.progress(angle: midAngle, clearAngle: clearAngle) == 0.5)
    }

    @Test func progressFloorsTinyClearAngleDenominatorRatherThanBlowingUp() {
        // clearAngle <= 13 makes (clearAngle - 12) <= 1; the denominator floors
        // at 1 so this stays a normal clamp instead of dividing by <= 0.
        #expect(BendMath.progress(angle: 5, clearAngle: 10) == 1)
        #expect(BendMath.progress(angle: 10, clearAngle: 10) == 0)
    }

    // MARK: - smooth

    @Test func smoothWithZeroDeltaTimeStaysAtCurrent() {
        #expect(BendMath.smooth(current: 0.3, target: 1.0, dt: 0) == 0.3)
    }

    @Test func smoothGlidesPartwayTowardTargetOverOneTimeConstant() {
        // dt equal to the 0.075s time constant covers exactly 1 - e^-1 of the gap.
        let result = BendMath.smooth(current: 0, target: 1, dt: 0.075)
        #expect(abs(result - (1 - exp(-1.0))) < 0.000001)
    }

    @Test func smoothClampsDeltaTimeAtOneTenthOfASecond() {
        // A stalled run loop (dt=5) must not overshoot -- it's clamped exactly
        // like a plausible dt of 0.1 would be.
        let clamped = BendMath.smooth(current: 0, target: 1, dt: 0.1)
        let stalled = BendMath.smooth(current: 0, target: 1, dt: 5)
        #expect(clamped == stalled)
    }

    @Test func smoothSnapsToTargetWithinEpsilonRatherThanCrawlingForever() {
        // Within 0.0003 of target, one 0.1s step lands within the 0.0001
        // snap threshold and returns the target exactly.
        let result = BendMath.smooth(current: 0.9997, target: 1.0, dt: 0.1)
        #expect(result == 1.0)
    }
}
