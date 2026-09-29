import AppKit
import Combine
import Darwin
import Foundation

/// Samples per-process energy (`ri_energy_nj` from `proc_pid_rusage`) for the
/// System Monitor's Energy segment. No entitlement, root or private symbol.
///
/// Lightweight by design (CLAUDE.md): there is **no** timer until `start()`
/// and the `Task` is cancelled by `stop()`; the view calls those from
/// `onAppear`/`onDisappear`, so nothing runs unless the Energy list is on
/// screen. The syscall walk (~a few hundred pids) runs off the main actor;
/// only the small result is published on it.
///
/// The first sample is a baseline only -- a cumulative counter means nothing
/// without a previous reading -- so `hasSample` stays false until the second.
@MainActor
final class EnergySource: ObservableObject {
    @Published private(set) var rows: [EnergyMath.AppEnergy] = []
    @Published private(set) var hasSample = false

    private static let pollInterval: Duration = .seconds(3)
    private static let rowLimit = 3

    private struct Snapshot: Sendable {
        let energyNJ: [Int32: UInt64]
        let parents: [Int32: Int32]
        let date: Date
    }

    private var previous: Snapshot?
    // Same reasoning as `SystemMonitorSource.pollTask`: `deinit` is
    // nonisolated, and this is only touched from start/stop/deinit.
    nonisolated(unsafe) private var task: Task<Void, Never>?

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.sample()
                try? await Task.sleep(for: Self.pollInterval)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        previous = nil
        hasSample = false
        rows = []
    }

    deinit { task?.cancel() }

    private func sample() async {
        let current = await Task.detached(priority: .utility) { Self.readSnapshot() }.value
        guard !Task.isCancelled else { return }
        defer { previous = current }
        guard let previous else { return }   // baseline only

        let readings = EnergyMath.readings(
            previous: previous.energyNJ,
            current: current.energyNJ,
            elapsed: current.date.timeIntervalSince(previous.date)
        )
        // A discarded sample (sleep gap) leaves us without a valid delta;
        // keep whatever we last showed rather than flashing "napping".
        guard !readings.isEmpty else { return }

        var apps: [Int32: EnergyMath.AppIdentity] = [:]
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            let name = app.localizedName ?? app.bundleIdentifier ?? "App"
            apps[app.processIdentifier] = EnergyMath.AppIdentity(
                id: app.bundleIdentifier ?? "pid\(app.processIdentifier)",
                name: name
            )
        }
        // Only real apps: daemons and background agents roll into the
        // "System" row, which is plumbing rather than something to act on,
        // so it's dropped here (the math keeps it for testability).
        rows = EnergyMath.topApps(
            readings: readings, parents: current.parents, apps: apps, limit: .max
        )
        .filter { $0.id != EnergyMath.systemID }
        .prefix(Self.rowLimit)
        .map { $0 }
        hasSample = true
    }

    /// One pass over every pid: cumulative energy plus parent pid. Pids we
    /// can't read (exited mid-walk, not ours) are skipped silently.
    private nonisolated static func readSnapshot() -> Snapshot {
        let date = Date()
        let expected = Int(proc_listallpids(nil, 0))
        var pids = [pid_t](repeating: 0, count: max(expected, 0) + 64)
        let listed = Int(proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.stride)))
        let count = min(max(listed, 0), pids.count)

        var energy: [Int32: UInt64] = [:]
        var parents: [Int32: Int32] = [:]
        for pid in pids.prefix(count) where pid > 0 {
            var info = rusage_info_v6()
            let ok = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(pid, RUSAGE_INFO_V6, $0)
                }
            }
            guard ok == 0 else { continue }
            energy[pid] = info.ri_energy_nj

            var bsd = proc_bsdinfo()
            let size = Int32(MemoryLayout<proc_bsdinfo>.size)
            if proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsd, size) == size {
                parents[pid] = Int32(bsd.pbi_ppid)
            }
        }
        return Snapshot(energyNJ: energy, parents: parents, date: date)
    }
}
