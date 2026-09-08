import Combine
import Foundation
import IOKit.ps

/// Watches `IOKit.ps` (public API, no entitlement) for charging state and
/// current capacity, republishing a `BatteryActivityContent?` whenever
/// `BatteryActivityState.evaluate` finds something worth surfacing.
/// Adapted from Clayton630/QuartzNotch's `BatteryActivityManager`, read
/// via `gh api` before designing (see check-reference-apps-first) --
/// uses the same `IOPSNotificationCreateRunLoopSource` push notification
/// QuartzNotch's own manager does, rather than a poll loop: a 2s poll
/// read as laggy on-device for something as immediate as plugging in a
/// charger.
final class BatterySource: LiveActivitySource {
    let id = "battery"
    let priority = NotchLiveActivityPriority.battery

    private let subject = CurrentValueSubject<LiveActivityContent?, Never>(nil)
    // `deinit` runs nonisolated regardless of this class's actor, and this
    // property is only ever touched from `init` (MainActor, constructed
    // once at app startup) and `deinit` at teardown -- same reasoning as
    // AirPodsSource's `nonisolated(unsafe)` properties.
    nonisolated(unsafe) private var runLoopSource: CFRunLoopSource?
    /// Tracks whether the last publish carried content, so `poll()` only
    /// sends `nil` on the content -> no-content transition rather than on
    /// every notification -- see Fix 5 in the final review pass.
    private var lastPublishWasContent = false
    private let notchHeight: CGFloat
    private var settleTask: Task<Void, Never>?
    /// macOS's own power-source data (`kIOPSIsChargingKey`) is known to
    /// lag behind the actual physical plug/unplug event by an amount that
    /// isn't consistent -- the push notification fires immediately, but
    /// `poll()` can read a stale "not charging" at that exact instant,
    /// and nothing re-checks it afterward unless some other change fires
    /// a second notification. On-device this showed up as "doesn't show
    /// up instantaneous, only after replugging" -- a genuine second
    /// notification (the replug) happened to land after the data had
    /// already settled, masking the first attempt's stale read. A single
    /// fixed re-poll delay (first tried at 2s) wasn't reliably long
    /// enough; staggered re-polls widen the window without a continuous
    /// poll loop -- each one cancels and no-ops once the state has
    /// actually changed from the initial read.
    private static let settleDelays: [Duration] = [.seconds(1), .seconds(3), .seconds(6)]

    var contentPublisher: AnyPublisher<LiveActivityContent?, Never> {
        subject.eraseToAnyPublisher()
    }

    init(notchHeight: CGFloat) {
        self.notchHeight = notchHeight
        poll()

        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            Unmanaged<BatterySource>.fromOpaque(context).takeUnretainedValue().handleNotification()
        }, context)?.takeRetainedValue() else { return }

        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
    }

    deinit {
        settleTask?.cancel()
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)
        }
    }

    /// Polls immediately, then schedules a few staggered delayed re-polls
    /// to catch a stale initial read -- see `settleDelays`'s doc comment.
    /// Only called from the notification callback, not from `init`'s own
    /// startup poll -- and `poll()` itself never re-schedules, so this
    /// can't chain into an unbounded polling loop.
    private func handleNotification() {
        poll()
        settleTask?.cancel()
        settleTask = Task { [weak self] in
            for delay in Self.settleDelays {
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }
                self?.poll()
            }
        }
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

        guard let state = BatteryActivityState.evaluate(percent: percent, isCharging: isCharging) else {
            if lastPublishWasContent {
                subject.send(nil)
                lastPublishWasContent = false
            }
            return
        }
        lastPublishWasContent = true

        // `kIOPSTimeToEmptyKey`/`kIOPSTimeToFullChargeKey` are documented
        // (IOPowerSources.h) as whole minutes, with `-1` meaning "still
        // calculating" -- converted to seconds here so
        // `BatteryActivityContent`/`TimeFormatting` share the same unit
        // the rest of the app already uses for durations.
        let minutesKey = isCharging ? kIOPSTimeToFullChargeKey : kIOPSTimeToEmptyKey
        let timeRemaining = (description[minutesKey] as? Int).flatMap { minutes -> TimeInterval? in
            minutes >= 0 ? TimeInterval(minutes * 60) : nil
        }

        subject.send(BatteryActivityContent(state: state, notchHeight: notchHeight, timeRemaining: timeRemaining))
    }
}
