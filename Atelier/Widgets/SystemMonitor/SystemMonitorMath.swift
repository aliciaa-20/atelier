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

    /// Page counts from one `host_statistics64`/`HOST_VM_INFO64` sample.
    /// Counts, not bytes -- `memoryUsedPercent` only needs their ratio, so
    /// the page size never has to cross this pure boundary either.
    struct MemorySample: Equatable {
        let free: UInt64
        let active: UInt64
        let inactive: UInt64
        let wired: UInt64
        let compressed: UInt64

        init(free: UInt64, active: UInt64, inactive: UInt64, wired: UInt64, compressed: UInt64 = 0) {
            self.free = free
            self.active = active
            self.inactive = inactive
            self.wired = wired
            self.compressed = compressed
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

    /// Percent of physical memory in active use. Free pages are the only
    /// ones excluded from "used" -- inactive pages are still resident and
    /// reclaimable, but until actually reclaimed they represent real
    /// memory pressure, matching how Activity Monitor's own "Memory Used"
    /// figure reads (not just wired+active). Compressed pages count as
    /// used for the same reason.
    static func memoryUsedPercent(_ sample: MemorySample) -> Double {
        let used = sample.active + sample.inactive + sample.wired + sample.compressed
        let total = used + sample.free
        guard total > 0 else { return 0 }
        return min(100, max(0, Double(used) / Double(total) * 100))
    }
}
