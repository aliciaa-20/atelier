# Battery Drain List Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an "Energy" segment to the System Monitor tab that lists the top energy-using apps as icon + name + relative bar (no numbers), with a funny one-line verdict, sampled only while that segment is on screen.

**Architecture:** A pure `EnergyMath` (Foundation only, unit-tested) turns two `ri_energy_nj` snapshots into per-app watts, groups helper processes under their parent app, and picks the verdict tier/copy. `EnergySource` (`@MainActor`, manual verification) reads `proc_pid_rusage` off the main thread on a ~3s `Task` loop that exists only between `start()`/`stop()`. `EnergyListView` + a `Gauges | Energy` toggle in `SystemMonitorPageView` present it.

**Tech Stack:** Swift 6 (strict concurrency), SwiftUI, Darwin `libproc` (`proc_listallpids`, `proc_pid_rusage`, `proc_pidinfo`), Swift Testing. No third-party dependencies.

**Spec:** `docs/superpowers/specs/2026-09-29-battery-drain-list-design.md`

## Global Constraints

- No third-party dependencies, no root, no entitlements, no network. App is not sandboxed (no `.entitlements` file), so `proc_pid_rusage` on other processes works.
- Lightweight by design: no sampling unless the Energy segment is on screen; the sampling `Task` is cancelled on `stop()`; poll interval 3s.
- `EnergyMath` imports only Foundation (Invariant 1 spirit: pure logic stays AppKit-free).
- Panel is fixed-size (Invariant 3): the list shares the tab via the toggle; nothing resizes the panel.
- Visual only: **no watts or any number is shown in the UI.** Watts stay internal (verdict tier, bar fraction).
- Layout/animation values go in `NotchLayout` / `NotchAnimations`, not inline. Honour Reduce Motion (`NotchAnimations` reads it live).
- Icon-only controls get `.help()`; rows get one combined VoiceOver label; decorative bars are hidden from VoiceOver.
- Copy is plain and friendly with a little wit, in the voice of System Monitor's status cards.
- Swift Testing (`import Testing`), not XCTest. New files under `Atelier/` and `AtelierTests/` are picked up automatically (Xcode synchronized root group) — no `.pbxproj` edits.
- Commands: build `xcodebuild -scheme Atelier -configuration Debug build`; tests `xcodebuild test -scheme Atelier -destination 'platform=macOS'`.
- Work on branch `feat/battery-drain-list`. Never commit to `main`. Don't push without asking.
- Commit trailer on every commit:
  `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>` and `Claude-Session: https://claude.ai/code/session_014VB2s2s2qWMvH86EeTqZdA`

## Review Focus

- Counter goes backwards (pid reuse / reset): watts clamp to 0, never negative or huge. (Task 1)
- Process exits or appears between samples: only pids present in both snapshots produce a reading. (Task 2)
- Mac sleeps between samples: a huge elapsed gap would dilute watts to ~0 and mislabel everything "napping"; discard such a sample as a new baseline. (Task 2)
- Parent-pid map with a cycle or very deep chain (helper trees): owner lookup terminates. (Task 2)
- Nothing using energy at all / no apps: top watts 0 → bar fraction 0 with no divide-by-zero, verdict "napping", and the view shows the napping card, not a blank page. (Tasks 1, 4)
- Very long app names: single line, truncated, never pushes the bar off the row. (Task 4)
- `proc_pid_rusage` fails for some pids (other users, exited): skipped silently. (Task 3, manual)
- Sampling keeps running after leaving the Energy segment, switching tabs, or the notch collapsing. (Tasks 3–4, manual check against Activity Monitor)

---

### Task 1: `EnergyMath` — watts, bar fraction, tier, verdict copy

**Files:**
- Create: `Atelier/Widgets/SystemMonitor/EnergyMath.swift`
- Test: `AtelierTests/EnergyMathTests.swift`

**Interfaces:**
- Produces:
  - `EnergyMath.watts(previousNJ: UInt64, currentNJ: UInt64, elapsed: TimeInterval) -> Double`
  - `EnergyMath.fraction(watts: Double, topWatts: Double) -> Double` (0...1)
  - `EnergyMath.Tier` (`.napping, .snack, .peckish, .breakfast`) with `init(topWatts: Double)`
  - `EnergyMath.verdict(_ tier: Tier, appName: String) -> String`

- [ ] **Step 1: Write the failing tests**

Create `AtelierTests/EnergyMathTests.swift`:

```swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme Atelier -destination 'platform=macOS' -only-testing:AtelierTests/EnergyMathTests 2>&1 | tail -15`
Expected: build FAIL — `cannot find 'EnergyMath' in scope`.

- [ ] **Step 3: Write minimal implementation**

Create `Atelier/Widgets/SystemMonitor/EnergyMath.swift`:

```swift
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme Atelier -destination 'platform=macOS' -only-testing:AtelierTests/EnergyMathTests 2>&1 | tail -15`
Expected: `** TEST SUCCEEDED **`, 8 tests in `EnergyMathTests` passing.

- [ ] **Step 5: Commit**

```bash
git add Atelier/Widgets/SystemMonitor/EnergyMath.swift AtelierTests/EnergyMathTests.swift
git commit -m "Energy list: EnergyMath watts, bar fraction, tier, verdict copy

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_014VB2s2s2qWMvH86EeTqZdA"
```

---

### Task 2: `EnergyMath` — per-process readings, owner resolution, top-app grouping

**Files:**
- Modify: `Atelier/Widgets/SystemMonitor/EnergyMath.swift` (append inside `enum EnergyMath`)
- Modify: `AtelierTests/EnergyMathTests.swift` (append a second test struct)

**Interfaces:**
- Consumes: `EnergyMath.watts(previousNJ:currentNJ:elapsed:)` from Task 1.
- Produces:
  - `EnergyMath.maxElapsed: TimeInterval` (= 10)
  - `EnergyMath.ProcessReading { pid: Int32; watts: Double }`
  - `EnergyMath.AppIdentity { id: String; name: String }`
  - `EnergyMath.AppEnergy: Identifiable { id: String; name: String; watts: Double }`
  - `EnergyMath.systemID: String` (= `"system"`)
  - `EnergyMath.readings(previous: [Int32: UInt64], current: [Int32: UInt64], elapsed: TimeInterval) -> [ProcessReading]`
  - `EnergyMath.owner(of pid: Int32, parents: [Int32: Int32], apps: Set<Int32>) -> Int32?`
  - `EnergyMath.topApps(readings: [ProcessReading], parents: [Int32: Int32], apps: [Int32: AppIdentity], limit: Int) -> [AppEnergy]`

- [ ] **Step 1: Write the failing tests**

Append to `AtelierTests/EnergyMathTests.swift`:

```swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme Atelier -destination 'platform=macOS' -only-testing:AtelierTests/EnergyMathGroupingTests 2>&1 | tail -15`
Expected: build FAIL — `type 'EnergyMath' has no member 'readings'` (and the other new symbols).

- [ ] **Step 3: Write minimal implementation**

Add inside `enum EnergyMath` in `Atelier/Widgets/SystemMonitor/EnergyMath.swift` (after `verdict`):

```swift
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
        return totals
            .map { AppEnergy(id: $0.key, name: $0.value.name, watts: $0.value.watts) }
            .filter { $0.watts > 0 }
            .sorted { $0.watts != $1.watts ? $0.watts > $1.watts : $0.name < $1.name }
            .prefix(limit)
            .map { $0 }
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme Atelier -destination 'platform=macOS' -only-testing:AtelierTests/EnergyMathTests -only-testing:AtelierTests/EnergyMathGroupingTests 2>&1 | tail -15`
Expected: `** TEST SUCCEEDED **`, both structs pass.

- [ ] **Step 5: Commit**

```bash
git add Atelier/Widgets/SystemMonitor/EnergyMath.swift AtelierTests/EnergyMathTests.swift
git commit -m "Energy list: per-process readings, owner resolution, top-app grouping

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_014VB2s2s2qWMvH86EeTqZdA"
```

---

### Task 3: `EnergySource` — libproc sampling loop, verified against `top`

Manual-verification only (system calls), like `SystemMonitorSource`.

**Files:**
- Create: `Atelier/Widgets/SystemMonitor/EnergySource.swift`

**Interfaces:**
- Consumes: `EnergyMath.readings`, `EnergyMath.topApps`, `EnergyMath.AppIdentity`, `EnergyMath.AppEnergy` (Tasks 1–2).
- Produces: `@MainActor final class EnergySource: ObservableObject` with
  - `@Published private(set) var rows: [EnergyMath.AppEnergy]`
  - `@Published private(set) var hasSample: Bool`
  - `func start()`, `func stop()`

- [ ] **Step 1: Write `EnergySource`**

```swift
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
    private static let rowLimit = 5

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
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy != .prohibited {
            let name = app.localizedName ?? app.bundleIdentifier ?? "App"
            apps[app.processIdentifier] = EnergyMath.AppIdentity(
                id: app.bundleIdentifier ?? "pid\(app.processIdentifier)",
                name: name
            )
        }
        rows = EnergyMath.topApps(
            readings: readings, parents: current.parents, apps: apps, limit: Self.rowLimit
        )
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
```

- [ ] **Step 2: Build**

Run: `xcodebuild -scheme Atelier -configuration Debug build 2>&1 | tail -20`
Expected: `** BUILD SUCCEEDED **`. If `RUSAGE_INFO_V6` is not imported as a constant, use the literal `6`; if `proc_listallpids` returns bytes rather than a pid count on this OS, divide by `MemoryLayout<pid_t>.stride` (the next step tells you which).

- [ ] **Step 3: Verify the counter against `top` (required by the spec — do not skip)**

Temporarily add a `print` of `rows` names at the end of `sample()` **and** of `listed` vs `pids.count` inside `readSnapshot()` (remove both before committing). Wire nothing else yet: call `EnergySource().start()` from a throwaway spot (e.g. `NotchController` init), run the app, and in a terminal run:

`top -l 2 -s 3 -n 8 -o power -stats pid,command,power | tail -9`

Expected: the same handful of apps lead in both, in a similar order, and `listed` ≈ `ps -A | wc -l`. Note the watts-vs-`top` ratio; if it's off by a constant factor, record it (this is the input for tuning the 1/3/8 W tiers) and mention it in the ADR in Task 5. Then delete the temporary prints and the throwaway call site.

- [ ] **Step 4: Verify idle cost**

Run the app with `start()` **not** called: Activity Monitor → Atelier CPU should be unchanged from before this branch. (Sampling-while-visible is checked in Task 4.)

- [ ] **Step 5: Commit**

```bash
git add Atelier/Widgets/SystemMonitor/EnergySource.swift
git commit -m "Energy list: EnergySource libproc sampling loop (start/stop gated)

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_014VB2s2s2qWMvH86EeTqZdA"
```

---

### Task 4: `EnergyListView` + `Gauges | Energy` toggle + wiring

**Files:**
- Create: `Atelier/UI/EnergyListView.swift`
- Modify: `Atelier/UI/NotchLayout.swift` (add energy row tokens)
- Modify: `Atelier/UI/SystemMonitorPageView.swift` (segment toggle; gauges body unchanged)
- Modify: `Atelier/UI/NotchRootView.swift:339` (pass the energy source)
- Modify: `Atelier/Notch/NotchController.swift:185-221` (construct/hold `EnergySource`, pass into `NotchRootView`)

**Interfaces:**
- Consumes: `EnergySource` (`rows`, `hasSample`, `start()`, `stop()`), `EnergyMath.fraction/Tier/verdict`.
- Produces: `EnergyListView(source: EnergySource)`; `SystemMonitorPageView(source:energy:)`.

- [ ] **Step 1: Add layout tokens**

In `Atelier/UI/NotchLayout.swift`, inside `enum NotchLayout`, add:

```swift
    /// System Monitor > Energy list rows.
    static let energyRowSpacing: CGFloat = 7
    static let energyIconSize: CGFloat = 18
    static let energyBarHeight: CGFloat = 5
    static let energyNameWidth: CGFloat = 96
```

- [ ] **Step 2: Create the view**

`Atelier/UI/EnergyListView.swift`:

```swift
import AppKit
import SwiftUI

/// The System Monitor's Energy segment: a funny one-line verdict, then the
/// top energy-using apps as icon + name + relative bar. Deliberately no
/// numbers -- the bar length *is* the information (spec 2026-09-29).
/// Sampling is tied to this view being on screen (`onAppear`/`onDisappear`).
struct EnergyListView: View {
    @ObservedObject var source: EnergySource
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: NotchLayout.energyRowSpacing) {
            if !source.hasSample {
                message("Watching who's thirsty…", symbol: "eyes")
            } else if source.rows.isEmpty {
                message(EnergyMath.verdict(.napping, appName: ""), symbol: "moon.zzz")
            } else {
                let top = source.rows[0]
                Text(EnergyMath.verdict(EnergyMath.Tier(topWatts: top.watts), appName: top.name))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                ForEach(source.rows) { row in
                    EnergyRow(row: row, fraction: EnergyMath.fraction(watts: row.watts, topWatts: top.watts))
                }
            }
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.15) : NotchAnimations.standard, value: source.rows)
        .onAppear { source.start() }
        .onDisappear { source.stop() }
    }

    /// Shared empty-state style: soft card, one SF Symbol, one short line.
    private func message(_ text: String, symbol: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: NotchLayout.cardCornerRadius))
        .accessibilityElement(children: .combine)
    }
}

private struct EnergyRow: View {
    let row: EnergyMath.AppEnergy
    let fraction: Double

    private var isAtelier: Bool { row.id == Bundle.main.bundleIdentifier }

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: AppIconCache.icon(forBundleID: row.id))
                .resizable()
                .frame(width: NotchLayout.energyIconSize, height: NotchLayout.energyIconSize)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(row.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                if isAtelier {
                    Text("that's me, hi")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: NotchLayout.energyNameWidth, alignment: .leading)
            GeometryReader { geo in
                Capsule().fill(.white.opacity(0.10))
                    .overlay(alignment: .leading) {
                        Capsule().fill(.tint)
                            .frame(width: max(geo.size.width * fraction, NotchLayout.energyBarHeight))
                    }
            }
            .frame(height: NotchLayout.energyBarHeight)
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        switch fraction {
        case 1...: "\(row.name), highest energy use"
        case 0.66...: "\(row.name), nearly as much"
        case 0.33...: "\(row.name), about half as much"
        default: "\(row.name), a little"
        }
    }
}

/// Tiny cache so we don't hit `NSWorkspace` for the same 5 icons every
/// 3-second refresh.
@MainActor
private enum AppIconCache {
    private static var cache: [String: NSImage] = [:]

    static func icon(forBundleID id: String) -> NSImage {
        if let cached = cache[id] { return cached }
        let image: NSImage
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            image = NSWorkspace.shared.icon(forFile: url.path)
        } else {
            image = NSImage(systemSymbolName: "gearshape.2", accessibilityDescription: nil) ?? NSImage()
        }
        cache[id] = image
        return image
    }
}
```

- [ ] **Step 3: Add the toggle to `SystemMonitorPageView`**

In `Atelier/UI/SystemMonitorPageView.swift`:

1. Add the property and enum: `let energy: EnergySource` and `@State private var segment: Segment = .gauges` with
   ```swift
   private enum Segment: String, CaseIterable { case gauges = "Gauges", energy = "Energy" }
   ```
2. Rename the current `body` to `private var gauges: some View` and move **only** its trailing `.padding(.horizontal…)`, `.padding(.top, 6)`, `.padding(.bottom…)` and `.frame(maxWidth:…)` modifiers (and their comment) onto the new `body` below. The `Button { … }` chain through `.help(...)` stays in `gauges`, untouched.
3. New `body`:
   ```swift
   var body: some View {
       VStack(spacing: 8) {
           Picker("View", selection: $segment) {
               ForEach(Segment.allCases, id: \.self) { Text($0.rawValue).tag($0) }
           }
           .pickerStyle(.segmented)
           .labelsHidden()
           .controlSize(.small)
           .frame(width: 150)
           .help("Switch between gauges and top energy users")

           switch segment {
           case .gauges: gauges
           case .energy: EnergyListView(source: energy)
           }
       }
       .padding(.horizontal, NotchLayout.pageHorizontalInset)
       .padding(.top, 6)
       .padding(.bottom, NotchLayout.pageBottomInset)
       .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
   }
   ```
   (Because `switch` swaps the views, `EnergyListView`'s `onDisappear` fires when you flip back to Gauges, which stops sampling.)

- [ ] **Step 4: Wire the source**

- `NotchController.swift`: next to `systemMonitorSource` (line ~185) create `let energySource = EnergySource()`, store it in a `private let energySource: EnergySource`, and pass `energy: energySource` wherever `systemMonitor: systemMonitorSource` is passed to `NotchRootView` (line ~221).
- `NotchRootView.swift`: add `let energy: EnergySource` next to the existing `systemMonitor` property/initialiser parameter, and change line 339 to `SystemMonitorPageView(source: systemMonitor, energy: energy)`.

- [ ] **Step 5: Build and run the full test suite**

Run: `xcodebuild -scheme Atelier -configuration Debug build 2>&1 | tail -20` then `xcodebuild test -scheme Atelier -destination 'platform=macOS' 2>&1 | tail -20`
Expected: `** BUILD SUCCEEDED **` and `** TEST SUCCEEDED **` (all existing suites plus 8 + 12 new tests).

- [ ] **Step 6: Verify on-device (build + relaunch with `/build`, say which branch is running)**

Manual checks, one at a time:
1. System Monitor tab opens on **Gauges**, unchanged.
2. Switch to **Energy**: "Watching who's thirsty…" for ~3s, then verdict + up to 5 rows; icons load; long names truncate; Atelier row (if present) shows "that's me, hi".
3. Start something heavy (Xcode build, a video) — that app rises to the top; verdict changes tier.
4. Activity Monitor → Atelier CPU: sampling blips only while Energy is on screen. Switch back to Gauges, switch tabs, and collapse the notch: CPU returns to baseline each time. **If collapsing the notch does not stop it** (the page view stays alive under the collapsed panel), gate `start()` on the notch's expanded state in `NotchRootView` (call `energy.stop()` when `viewModel.state` is not expanded) and re-check.
5. Sleep the Mac 30s and wake: no "everyone's napping" flash; list recovers within ~6s.
6. Send screenshots of **both segments and every other tab** (unchanged tabs included) for review.

- [ ] **Step 7: Commit**

```bash
git add Atelier/UI/EnergyListView.swift Atelier/UI/NotchLayout.swift Atelier/UI/SystemMonitorPageView.swift Atelier/UI/NotchRootView.swift Atelier/Notch/NotchController.swift
git commit -m "Energy list: Gauges | Energy toggle and EnergyListView

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_014VB2s2s2qWMvH86EeTqZdA"
```

---

### Task 5: UI review, tier tuning, docs

**Files:**
- Modify (as findings dictate): `Atelier/UI/EnergyListView.swift`, `Atelier/Widgets/SystemMonitor/EnergyMath.swift` (thresholds), `AtelierTests/EnergyMathTests.swift` (only if thresholds change)
- Create (only if `ri_energy_nj` needed caveats in Task 3): `docs/decisions/0029-energy-list-ri-energy-nj.md`
- Modify: `docs/ROADMAP.md` (queue item #2 → ✅, "Where we are" line), `README.md` (feature list), `CLAUDE.md` (Widgets row: `SystemMonitor` now includes Energy list; `EnergyMath` pure/tested, `EnergySource` manual), `docs/FEATURES.md` if it lists System Monitor

- [ ] **Step 1: Run the `ui-review-tahoe` skill** on `EnergyListView` and the toggle (VoiceOver labels, keyboard focus, depth, hover/press feedback, Reduce Motion, Increase Contrast). Fix everything in one batch; rebuild and re-check the Energy segment.

- [ ] **Step 2: Tune tiers** from the Task 3 comparison with `top`. If the 1/3/8 W thresholds feel wrong on your machine, change them in `EnergyMath.Tier.init` and update `tierBoundaries` to match. Run `xcodebuild test -scheme Atelier -destination 'platform=macOS' -only-testing:AtelierTests/EnergyMathTests 2>&1 | tail -5` — expected `** TEST SUCCEEDED **`.

- [ ] **Step 3: Record the decision.** Use the `recording-architecture-decisions` skill: `ri_energy_nj` over `top` shell-out and over CPU time, plus any counter caveats found in Task 3. Number the ADR after the current highest in `docs/decisions/`.

- [ ] **Step 4: Run `phase-completion-checklist`**, then update the docs listed above so they say what actually shipped (tests: manual vs unit-tested split stated plainly).

- [ ] **Step 5: Final verification.** Run `xcodebuild -scheme Atelier -configuration Debug build 2>&1 | tail -3` and `xcodebuild test -scheme Atelier -destination 'platform=macOS' 2>&1 | tail -5` — both must succeed. Grep for leftover debug: `git diff main --stat` and `git diff main | grep -n "print("` must show no `print(` additions.

- [ ] **Step 6: Commit**

```bash
git add -A docs README.md CLAUDE.md Atelier AtelierTests
git commit -m "Energy list: UI review fixes, tier tuning, docs

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_014VB2s2s2qWMvH86EeTqZdA"
```

- [ ] **Step 7: Stop and ask before pushing.** Run `pre-push-docs-sync`, post its summary, then ask whether to push and open a PR (she merges PRs herself; never push without asking).
