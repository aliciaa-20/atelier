import Combine
import Foundation
import IOKit.ps

/// Polls `IOKit.ps` (public API, no entitlement) for charging state and
/// current capacity, republishing a `BatteryActivityContent?` whenever
/// `BatteryActivityState.evaluate` finds something worth surfacing.
/// Adapted from Clayton630/QuartzNotch's `BatteryActivityManager`, read
/// via `gh api` before designing (see check-reference-apps-first) --
/// simplified to a single poll loop instead of its
/// `IOPSNotificationCreateRunLoopSource` run-loop source + event
/// coalescing, since a 2s poll is more than fast enough for a battery
/// alert (unlike now-playing's scrubber, nothing here needs sub-second
/// latency).
final class BatterySource: LiveActivitySource {
    let id = "battery"
    let priority = NotchLiveActivityPriority.battery

    private let subject = CurrentValueSubject<LiveActivityContent?, Never>(nil)
    private var pollTask: Task<Void, Never>?
    private var wasCharging = false

    var contentPublisher: AnyPublisher<LiveActivityContent?, Never> {
        subject.eraseToAnyPublisher()
    }

    init() {
        pollTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                self.poll()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    deinit {
        pollTask?.cancel()
    }

    private func poll() {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
              let source = sources.first,
              let description = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any],
              let currentCapacity = description[kIOPSCurrentCapacityKey] as? Int,
              let maxCapacity = description[kIOPSMaxCapacityKey] as? Int, maxCapacity > 0,
              let isCharging = description["Is Charging"] as? Bool
        else { return }

        let percent = Int((Double(currentCapacity) / Double(maxCapacity) * 100).rounded())

        guard let state = BatteryActivityState.evaluate(percent: percent, isCharging: isCharging, wasCharging: wasCharging) else {
            wasCharging = isCharging
            subject.send(nil)
            return
        }
        wasCharging = isCharging
        subject.send(BatteryActivityContent(state: state))
    }
}
