import Testing
@testable import Atelier

struct EnergyMathTests {
    // MARK: watts

    @Test func wattsIsEnergyDeltaOverElapsedSeconds() {
        // 6 J (6e9 nJ) over 3 s = 2 W.
        let watts = EnergyMath.watts(previousNJ: 1_000_000_000, currentNJ: 7_000_000_000, elapsed: 3)
        #expect(abs(watts - 2.0) < 0.0001)
    }

    @Test func wattsIsZeroWhenCounterWentBackwards() {
        // pid reuse / counter reset must never produce a negative or wrapped value.
        let watts = EnergyMath.watts(previousNJ: 9_000_000_000, currentNJ: 1_000, elapsed: 3)
        #expect(watts == 0)
    }

    @Test func wattsIsZeroWhenNoTimeElapsed() {
        #expect(EnergyMath.watts(previousNJ: 0, currentNJ: 5_000_000_000, elapsed: 0) == 0)
        #expect(EnergyMath.watts(previousNJ: 0, currentNJ: 5_000_000_000, elapsed: -1) == 0)
    }

    // MARK: fraction

    @Test func fractionIsRelativeToTheTopApp() {
        #expect(EnergyMath.fraction(watts: 2, topWatts: 4) == 0.5)
        #expect(EnergyMath.fraction(watts: 4, topWatts: 4) == 1)
    }

    @Test func fractionIsZeroWhenNothingIsUsingEnergy() {
        #expect(EnergyMath.fraction(watts: 0, topWatts: 0) == 0)
    }

    @Test func fractionNeverExceedsOne() {
        #expect(EnergyMath.fraction(watts: 9, topWatts: 4) == 1)
    }

    // MARK: tier boundaries (provisional thresholds: 1 / 3 / 8 W)

    @Test func tierBoundaries() {
        #expect(EnergyMath.Tier(topWatts: 0) == .napping)
        #expect(EnergyMath.Tier(topWatts: 0.99) == .napping)
        #expect(EnergyMath.Tier(topWatts: 1) == .snack)
        #expect(EnergyMath.Tier(topWatts: 2.99) == .snack)
        #expect(EnergyMath.Tier(topWatts: 3) == .peckish)
        #expect(EnergyMath.Tier(topWatts: 7.99) == .peckish)
        #expect(EnergyMath.Tier(topWatts: 8) == .breakfast)
        #expect(EnergyMath.Tier(topWatts: 40) == .breakfast)
    }

    // MARK: copy

    @Test func verdictCopy() {
        #expect(EnergyMath.verdict(.napping, appName: "Safari") == "Everyone's napping. Enjoy the quiet.")
        #expect(EnergyMath.verdict(.snack, appName: "Safari") == "Safari is having a light snack.")
        #expect(EnergyMath.verdict(.peckish, appName: "Safari") == "Safari is getting peckish.")
        #expect(EnergyMath.verdict(.breakfast, appName: "Safari") == "Safari is eating your battery for breakfast.")
    }
}
