import Foundation

/// Pure math for the system resource monitor -- no Darwin/Mach imports, so
/// the percent-from-tick-deltas calculation is unit-testable without a real
/// `host_statistics` call. Mirrors how `AudioLevels.swift`/
/// `TimeFormatting.swift` keep pure math separate from the system-call
/// boundary (`SystemMonitorSource`).
enum SystemMonitorMath {
    /// One `host_cpu_load_info` sample's cumulative tick counts.
    /// `UInt64` rather than the Mach API's own `integer_t` (`Int32`) --
    /// ticks only ever increase, and widening here keeps subtraction safe
    /// regardless of how the underlying counter is represented.
    struct CPUTicks: Equatable {
        let user: UInt64
        let system: UInt64
        let idle: UInt64
        let nice: UInt64

        init(user: UInt64, system: UInt64, idle: UInt64, nice: UInt64) {
            self.user = user
            self.system = system
            self.idle = idle
            self.nice = nice
        }
    }

    /// Percent of CPU busy (user + system + nice against user + system +
    /// nice + idle) between two samples of the same running counter, per
    /// the standard `host_cpu_load_info` delta technique -- a single
    /// sample is a cumulative tick count since boot, not an instantaneous
    /// load, so it's meaningless without a previous sample to diff
    /// against. `0` when the two samples carry no elapsed ticks at all,
    /// or when `current` has gone backwards relative to `previous` (which
    /// shouldn't happen, but is guarded rather than trusted), instead of
    /// dividing by zero or reporting nonsensical load from an
    /// underflowed delta.
    static func cpuPercent(previous: CPUTicks, current: CPUTicks) -> Double {
        guard current.user >= previous.user, current.system >= previous.system,
              current.nice >= previous.nice, current.idle >= previous.idle
        else {
            return 0
        }

        let deltaUser = current.user - previous.user
        let deltaSystem = current.system - previous.system
        let deltaNice = current.nice - previous.nice
        let deltaIdle = current.idle - previous.idle

        let busy = deltaUser + deltaSystem + deltaNice
        let total = busy + deltaIdle
        guard total > 0 else { return 0 }
        return min(100, max(0, Double(busy) / Double(total) * 100))
    }

    /// Percent of memory "in use", as the complement of the system's own
    /// free-memory percentage (`kern.memorystatus_level`, the number
    /// `memory_pressure` prints as "System-wide memory free percentage").
    ///
    /// Not summed from raw Mach page counts: counting inactive (cache-like)
    /// and compressor pages as "used" made every Mac read ~95-99% and the
    /// ring sat permanently red -- on an 8 GB machine reporting 46% free it
    /// showed 99%. The OS's own figure already accounts for reclaimable
    /// pages, so it tracks real memory pressure. See ADR 0017.
    static func memoryUsedPercent(freePercentage: Int) -> Double {
        100 - Double(min(100, max(0, freePercentage)))
    }
}
