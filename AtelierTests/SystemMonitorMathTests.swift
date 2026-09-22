import Testing
@testable import Atelier

struct SystemMonitorMathTests {
    @Test func fullyIdleProducesZeroPercent() {
        let previous = SystemMonitorMath.CPUTicks(user: 100, system: 50, idle: 1000, nice: 0)
        let current = SystemMonitorMath.CPUTicks(user: 100, system: 50, idle: 1400, nice: 0)
        let percent = SystemMonitorMath.cpuPercent(previous: previous, current: current)
        #expect(percent == 0)
    }

    @Test func fullyBusyProducesHundredPercent() {
        let previous = SystemMonitorMath.CPUTicks(user: 100, system: 50, idle: 1000, nice: 0)
        let current = SystemMonitorMath.CPUTicks(user: 500, system: 250, idle: 1000, nice: 0)
        let percent = SystemMonitorMath.cpuPercent(previous: previous, current: current)
        #expect(percent == 100)
    }

    @Test func mixedLoadProducesExpectedRatio() {
        // 50 busy ticks (30 user + 20 system) against 50 idle ticks in the
        // same window -- exactly half busy.
        let previous = SystemMonitorMath.CPUTicks(user: 0, system: 0, idle: 0, nice: 0)
        let current = SystemMonitorMath.CPUTicks(user: 30, system: 20, idle: 50, nice: 0)
        let percent = SystemMonitorMath.cpuPercent(previous: previous, current: current)
        #expect(percent == 50)
    }

    @Test func niceTicksCountAsBusy() {
        let previous = SystemMonitorMath.CPUTicks(user: 0, system: 0, idle: 0, nice: 0)
        let current = SystemMonitorMath.CPUTicks(user: 0, system: 0, idle: 100, nice: 100)
        let percent = SystemMonitorMath.cpuPercent(previous: previous, current: current)
        #expect(percent == 50)
    }

    @Test func identicalSamplesProduceZeroPercentRatherThanDividingByZero() {
        let sample = SystemMonitorMath.CPUTicks(user: 10, system: 10, idle: 10, nice: 0)
        let percent = SystemMonitorMath.cpuPercent(previous: sample, current: sample)
        #expect(percent == 0)
    }

    @Test func regressedCurrentSampleProducesZeroRatherThanUnderflowing() {
        // `current` behind `previous` shouldn't happen in practice, but
        // must not read as an enormous busy percentage via an
        // underflowed unsigned subtraction.
        let previous = SystemMonitorMath.CPUTicks(user: 100, system: 100, idle: 100, nice: 0)
        let current = SystemMonitorMath.CPUTicks(user: 50, system: 50, idle: 50, nice: 0)
        let percent = SystemMonitorMath.cpuPercent(previous: previous, current: current)
        #expect(percent == 0)
    }

    @Test func memoryUsedPercentExcludesOnlyFreePages() {
        let sample = SystemMonitorMath.MemorySample(free: 100, active: 200, inactive: 50, wired: 50, compressed: 0)
        // used = 300, total = 400 -> 75%
        let percent = SystemMonitorMath.memoryUsedPercent(sample)
        #expect(percent == 75)
    }

    @Test func memoryUsedPercentIncludesCompressedPages() {
        let sample = SystemMonitorMath.MemorySample(free: 0, active: 50, inactive: 0, wired: 0, compressed: 50)
        let percent = SystemMonitorMath.memoryUsedPercent(sample)
        #expect(percent == 100)
    }

    @Test func memoryUsedPercentHandlesAllZeroSampleWithoutDividingByZero() {
        let sample = SystemMonitorMath.MemorySample(free: 0, active: 0, inactive: 0, wired: 0, compressed: 0)
        let percent = SystemMonitorMath.memoryUsedPercent(sample)
        #expect(percent == 0)
    }
}
