import Foundation

/// Pure math for the Energy list -- Foundation only, so it's unit-testable
/// without a real `proc_pid_rusage` call. Mirrors `SystemMonitorMath`: the
/// system-call boundary lives in `EnergySource`, everything decidable lives
/// here.
enum EnergyMath {
    /// Watts from two readings of a process's cumulative `ri_energy_nj`
    /// counter (nanojoules). `0` when no time elapsed or the counter went
    /// backwards (pid reuse / reset) rather than reporting a negative or
    /// underflowed value.
    static func watts(previousNJ: UInt64, currentNJ: UInt64, elapsed: TimeInterval) -> Double {
        guard elapsed > 0, currentNJ >= previousNJ else { return 0 }
        return Double(currentNJ - previousNJ) / 1_000_000_000 / elapsed
    }

    /// Bar length relative to the top app, 0...1. `0` when nothing is using
    /// energy, so an idle Mac shows empty bars instead of dividing by zero.
    static func fraction(watts: Double, topWatts: Double) -> Double {
        guard topWatts > 0, watts > 0 else { return 0 }
        return min(watts / topWatts, 1)
    }

    /// How hungry the top app is. Thresholds are provisional -- tune them
    /// after comparing against `top -o power` on the target machine. Watts
    /// are never shown; they only pick the line of copy.
    enum Tier: Equatable {
        case napping, snack, peckish, breakfast

        init(topWatts: Double) {
            switch topWatts {
            case ..<1: self = .napping
            case ..<3: self = .snack
            case ..<8: self = .peckish
            default: self = .breakfast
            }
        }
    }

    static func verdict(_ tier: Tier, appName: String) -> String {
        switch tier {
        case .napping: "Everyone's napping. Enjoy the quiet."
        case .snack: "\(appName) is having a light snack."
        case .peckish: "\(appName) is getting peckish."
        case .breakfast: "\(appName) is eating your battery for breakfast."
        }
    }
}
