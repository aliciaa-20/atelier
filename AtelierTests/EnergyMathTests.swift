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

struct EnergyMathGroupingTests {
    // MARK: readings

    @Test func readingsOnlyIncludePidsPresentInBothSnapshots() {
        let previous: [Int32: UInt64] = [1: 0, 2: 0]        // pid 2 exits
        let current: [Int32: UInt64] = [1: 3_000_000_000, 3: 9_000_000_000]  // pid 3 is new, no baseline
        let readings = EnergyMath.readings(previous: previous, current: current, elapsed: 3)
        #expect(readings.count == 1)
        #expect(readings[0].pid == 1)
        #expect(abs(readings[0].watts - 1.0) < 0.0001)
    }

    @Test func readingsAreDiscardedAfterALongGapSuchAsSleep() {
        // A Mac that slept between samples would dilute every value to ~0.
        let previous: [Int32: UInt64] = [1: 0]
        let current: [Int32: UInt64] = [1: 3_000_000_000]
        #expect(EnergyMath.readings(previous: previous, current: current, elapsed: 600).isEmpty)
        #expect(EnergyMath.readings(previous: previous, current: current, elapsed: 0).isEmpty)
    }

    // MARK: owner

    @Test func ownerIsTheProcessItselfWhenItIsAnApp() {
        #expect(EnergyMath.owner(of: 10, parents: [10: 1], apps: [10]) == 10)
    }

    @Test func ownerWalksUpToTheParentApp() {
        // Chrome Helper (30) -> Chrome Helper (Renderer) (20) -> Chrome (10)
        let parents: [Int32: Int32] = [30: 20, 20: 10, 10: 1]
        #expect(EnergyMath.owner(of: 30, parents: parents, apps: [10]) == 10)
    }

    @Test func ownerIsNilForDaemonsWithNoAppAncestor() {
        #expect(EnergyMath.owner(of: 50, parents: [50: 1], apps: [10]) == nil)
    }

    @Test func ownerTerminatesOnParentCycles() {
        #expect(EnergyMath.owner(of: 1000, parents: [1000: 2000, 2000: 1000], apps: [10]) == nil)
        #expect(EnergyMath.owner(of: 5, parents: [5: 5], apps: [10]) == nil)
    }

    @Test func ownerTerminatesOnVeryDeepChains() {
        var parents: [Int32: Int32] = [:]
        for pid in Int32(100)..<Int32(200) { parents[pid] = pid + 1 }
        #expect(EnergyMath.owner(of: 100, parents: parents, apps: [10]) == nil)
    }

    // MARK: topApps

    private let safari = EnergyMath.AppIdentity(id: "com.apple.Safari", name: "Safari")
    private let chrome = EnergyMath.AppIdentity(id: "com.google.Chrome", name: "Google Chrome")

    @Test func helpersFoldIntoTheirParentAppAndSumTheirWatts() {
        let parents: [Int32: Int32] = [11: 10, 12: 10]
        let readings = [
            EnergyMath.ProcessReading(pid: 10, watts: 1.0),
            EnergyMath.ProcessReading(pid: 11, watts: 2.0),
            EnergyMath.ProcessReading(pid: 12, watts: 0.5),
        ]
        let top = EnergyMath.topApps(readings: readings, parents: parents, apps: [10: chrome], limit: 5)
        #expect(top.count == 1)
        #expect(top[0].id == "com.google.Chrome")
        #expect(abs(top[0].watts - 3.5) < 0.0001)
    }

    @Test func daemonsRollUpIntoOneSystemRow() {
        let readings = [
            EnergyMath.ProcessReading(pid: 50, watts: 1.0),
            EnergyMath.ProcessReading(pid: 51, watts: 0.5),
        ]
        let top = EnergyMath.topApps(readings: readings, parents: [50: 1, 51: 1], apps: [10: safari], limit: 5)
        #expect(top.count == 1)
        #expect(top[0].id == EnergyMath.systemID)
        #expect(top[0].name == "System")
        #expect(abs(top[0].watts - 1.5) < 0.0001)
    }

    @Test func rankedDescendingAndTruncatedToTheLimit() {
        var apps: [Int32: EnergyMath.AppIdentity] = [:]
        var readings: [EnergyMath.ProcessReading] = []
        for i in 1...7 {
            let pid = Int32(i)
            apps[pid] = EnergyMath.AppIdentity(id: "app\(i)", name: "App \(i)")
            readings.append(EnergyMath.ProcessReading(pid: pid, watts: Double(i)))
        }
        let top = EnergyMath.topApps(readings: readings, parents: [:], apps: apps, limit: 5)
        #expect(top.map(\.id) == ["app7", "app6", "app5", "app4", "app3"])
    }

    @Test func zeroWattAppsAreDropped() {
        let readings = [EnergyMath.ProcessReading(pid: 10, watts: 0)]
        #expect(EnergyMath.topApps(readings: readings, parents: [:], apps: [10: safari], limit: 5).isEmpty)
    }

    @Test func emptyInputGivesEmptyList() {
        #expect(EnergyMath.topApps(readings: [], parents: [:], apps: [:], limit: 5).isEmpty)
    }
}
