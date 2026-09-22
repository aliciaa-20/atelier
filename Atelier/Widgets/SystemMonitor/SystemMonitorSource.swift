import Combine
import Darwin
import Foundation

/// Polls CPU load and memory pressure via public Mach `host_statistics`
/// APIs -- `HOST_CPU_LOAD_INFO`/`host_statistics` for CPU tick deltas,
/// `HOST_VM_INFO64`/`host_statistics64` for page counts. Both are
/// standard, documented Darwin APIs requiring no entitlement or private
/// symbol, unlike `ScreenRecordingSource`'s CGS calls -- and deliberately
/// scoped to just these two: SMC-based temperature and IOReport frequency
/// sampling (credited to the "Stats" project in docs/FEATURES.md §7) are
/// explicitly OUT of scope for this pass.
///
/// Polled, not push-driven, mirroring `NowPlayingCoordinator`'s
/// `Task { while !Task.isCancelled { ...; try await Task.sleep(...) } }`
/// loop shape -- there's no push API for CPU load the way `BatterySource`
/// gets one from `IOKit.ps`. Per this project's lightweight-by-design
/// principle (CLAUDE.md), this polls far slower than now-playing's own
/// loop: CPU/memory are ambient background numbers, not something that
/// needs sub-second freshness like a scrubber.
@MainActor
final class SystemMonitorSource: LiveActivitySource, ObservableObject {
    let id = "systemMonitor"
    let priority = NotchLiveActivityPriority.systemMonitor

    private let subject = CurrentValueSubject<LiveActivityContent?, Never>(nil)
    private let notchHeight: CGFloat
    private var previousTicks: SystemMonitorMath.CPUTicks?

    /// The always-current reading, independent of `subject`/priority --
    /// `subject` only exists to compete for the pill, so its content is
    /// visible exactly when this source is `topContent`. The
    /// `NotchPage.systemMonitor` tab needs the live numbers regardless of
    /// what else is on top of the stack, same reasoning `BatterySource`
    /// documents for its own `currentPercentPublisher`/`percentSubject`
    /// feeding `IdleHomeView` independent of its own pill-competing
    /// `subject`.
    @Published private(set) var cpuPercent: Double = 0
    /// `nil` until the second poll (~4s after launch) produces a real
    /// delta -- see `poll()`'s own comment on why the first sample can't
    /// yield a percentage. `SystemMonitorPageView` shows a loading state
    /// while this is `nil` rather than a misleading `0%`.
    @Published private(set) var hasCPUSample = false
    @Published private(set) var memoryPercent: Double = 0
    /// 4s, within the 3-5s idle-poll range the lightweight-by-design
    /// principle asks for -- this is ambient state, not something that
    /// needs now-playing-scrubber freshness.
    private static let pollInterval: Duration = .seconds(4)

    // Same reasoning as `AudioTap.consumerTask`/`BatterySource.settleTask`:
    // `deinit` runs nonisolated regardless of this class's `@MainActor`
    // isolation, and this property is only ever touched from `init`
    // (MainActor, constructed once at app startup) and `deinit` at
    // teardown.
    nonisolated(unsafe) private var pollTask: Task<Void, Never>?

    var contentPublisher: AnyPublisher<LiveActivityContent?, Never> {
        subject.eraseToAnyPublisher()
    }

    init(notchHeight: CGFloat) {
        self.notchHeight = notchHeight
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.poll()
                try? await Task.sleep(for: Self.pollInterval)
            }
        }
    }

    deinit {
        pollTask?.cancel()
    }

    private func poll() {
        // Skip the Mach syscalls entirely when the feature is off in
        // Settings, not just the tab's display -- matching how `AudioTap`'s
        // lifetime is already tied to `isPlaying` rather than merely
        // pausing its output (CLAUDE.md's lightweight-by-design principle).
        guard AtelierSettings.systemMonitorEnabled else { return }
        guard let memory = Self.readMemorySample() else { return }
        let memoryPercent = SystemMonitorMath.memoryUsedPercent(memory)
        self.memoryPercent = memoryPercent

        guard let ticks = Self.readCPUTicks() else { return }
        defer { previousTicks = ticks }

        // The first poll only establishes a baseline -- a single
        // cumulative tick sample can't produce a load percentage on its
        // own, same reasoning `SystemMonitorMath.cpuPercent` documents
        // for needing two samples. Nothing is published (to either the
        // pill stack or the always-current `@Published` reading) until
        // the second poll, ~4s after launch.
        guard let previousTicks else { return }
        let cpuPercent = SystemMonitorMath.cpuPercent(previous: previousTicks, current: ticks)
        self.cpuPercent = cpuPercent
        hasCPUSample = true

        subject.send(SystemMonitorActivityContent(cpuPercent: cpuPercent, memoryPercent: memoryPercent, notchHeight: notchHeight))
    }

    private static func readCPUTicks() -> SystemMonitorMath.CPUTicks? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) { pointer -> kern_return_t in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, reboundPointer, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        // `cpu_ticks` indices per CPU_STATE_MAX/CPU_STATE_USER/SYSTEM/
        // IDLE/NICE (mach/machine.h): 0 = user, 1 = system, 2 = idle,
        // 3 = nice.
        return SystemMonitorMath.CPUTicks(
            user: UInt64(info.cpu_ticks.0),
            system: UInt64(info.cpu_ticks.1),
            idle: UInt64(info.cpu_ticks.2),
            nice: UInt64(info.cpu_ticks.3)
        )
    }

    private static func readMemorySample() -> SystemMonitorMath.MemorySample? {
        var info = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) { pointer -> kern_return_t in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, reboundPointer, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        return SystemMonitorMath.MemorySample(
            free: UInt64(info.free_count),
            active: UInt64(info.active_count),
            inactive: UInt64(info.inactive_count),
            wired: UInt64(info.wire_count),
            compressed: UInt64(info.compressor_page_count)
        )
    }
}
