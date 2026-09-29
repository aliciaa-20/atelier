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

    /// Below this the top app's bar is scaled against the floor instead of
    /// itself, so an idle Mac shows short bars that match "napping" rather
    /// than a full bar for an app using ~0.03 W. Equals the "peckish" tier
    /// boundary.
    static let barFloorWatts: Double = 3

    static func barFraction(watts: Double, topWatts: Double) -> Double {
        fraction(watts: watts, topWatts: max(topWatts, barFloorWatts))
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

    // MARK: Per-process readings and grouping

    /// A gap longer than this between two samples (the Mac slept, the loop
    /// stalled) would dilute every reading to ~0 and mislabel the whole
    /// list "napping", so such a sample is discarded and becomes the new
    /// baseline instead. Poll interval is 3s.
    static let maxElapsed: TimeInterval = 10

    struct ProcessReading: Equatable {
        let pid: Int32
        let watts: Double
    }

    /// A user-visible app (bundle id + display name). Helper processes are
    /// folded into one of these; anything else is "System".
    struct AppIdentity: Equatable {
        let id: String
        let name: String
    }

    struct AppEnergy: Equatable, Identifiable {
        let id: String
        let name: String
        let watts: Double
    }

    static let systemID = "system"

    /// Per-pid watts between two snapshots of `ri_energy_nj`. Only pids
    /// present in both produce a reading: a new pid has no baseline and an
    /// exited pid has no current value.
    static func readings(
        previous: [Int32: UInt64],
        current: [Int32: UInt64],
        elapsed: TimeInterval
    ) -> [ProcessReading] {
        guard elapsed > 0, elapsed <= maxElapsed else { return [] }
        return current.compactMap { pid, currentNJ in
            guard let previousNJ = previous[pid] else { return nil }
            return ProcessReading(
                pid: pid,
                watts: watts(previousNJ: previousNJ, currentNJ: currentNJ, elapsed: elapsed)
            )
        }
    }

    /// The app a process belongs to: itself if it is an app, otherwise the
    /// nearest ancestor that is (Chrome Helper -> Chrome). `nil` for
    /// daemons. Hop-capped so a cyclic or absurdly deep parent map can't
    /// loop forever.
    static func owner(of pid: Int32, parents: [Int32: Int32], apps: Set<Int32>) -> Int32? {
        var current = pid
        for _ in 0..<32 {
            if apps.contains(current) { return current }
            guard let parent = parents[current], parent > 1, parent != current else { return nil }
            current = parent
        }
        return nil
    }

    /// Sums watts per app (helpers folded in), rolls non-app processes into
    /// one "System" row, drops zero-watt entries, ranks descending and
    /// truncates to `limit`.
    static func topApps(
        readings: [ProcessReading],
        parents: [Int32: Int32],
        apps: [Int32: AppIdentity],
        limit: Int
    ) -> [AppEnergy] {
        let appPids = Set(apps.keys)
        var totals: [String: (name: String, watts: Double)] = [:]
        for reading in readings {
            if let ownerPid = owner(of: reading.pid, parents: parents, apps: appPids),
               let app = apps[ownerPid] {
                totals[app.id, default: (app.name, 0)].watts += reading.watts
            } else {
                totals[systemID, default: ("System", 0)].watts += reading.watts
            }
        }
        // Explicitly typed steps, not one chained expression: the chain
        // compiled on Xcode 27 but the CI runner's Xcode 26.6 gave up with
        // "unable to type-check this expression in reasonable time".
        let all: [AppEnergy] = totals.map { entry in
            AppEnergy(id: entry.key, name: entry.value.name, watts: entry.value.watts)
        }
        let active: [AppEnergy] = all.filter { $0.watts > 0 }
        let ranked: [AppEnergy] = active.sorted { (a: AppEnergy, b: AppEnergy) -> Bool in
            if a.watts != b.watts { return a.watts > b.watts }
            return a.name < b.name
        }
        return Array(ranked.prefix(limit))
    }
}
