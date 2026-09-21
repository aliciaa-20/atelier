import Combine
import Foundation

/// Private SkyLight/CGS symbols -- not public API, no entitlement exists for
/// this either way. Same tolerance as ADR 0006's DisplayServices call for
/// brightness: acceptable on this project's single personal machine, distinct
/// from Invariant 6's `MediaRemote` ban (that one is entitlement-gated and
/// returns nil outright; this one has no entitlement story at all and just
/// works). Adapted from Ebullioscopic/Atoll's `ScreenRecordingManager` and
/// jackson-storm/dynamicnotch's `SystemScreenRecordingMonitor`, both read via
/// `gh api` before designing (see check-reference-apps-first) -- neither
/// app's remote-stop-recording feature (simulated keystroke injection) is
/// adopted here, since this source is a status indicator, not a controller.
@_silgen_name("CGSIsScreenWatcherPresent")
private func CGSIsScreenWatcherPresent() -> Bool

@_silgen_name("CGSRegisterNotifyProc")
private func CGSRegisterNotifyProc(
    _ callback: (@convention(c) (Int32, Int32, Int32, UnsafeMutableRawPointer?) -> Void)?,
    _ event: Int32,
    _ context: UnsafeMutableRawPointer?
) -> Bool

/// CGS screen-watcher connect/disconnect event codes, per both reference
/// implementations -- undocumented, but stable across the apps checked.
private let screenWatcherConnected: Int32 = 1502
private let screenWatcherDisconnected: Int32 = 1503

private func screenRecordingEventCallback(_ eventType: Int32, _: Int32, _: Int32, _ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    let source = Unmanaged<ScreenRecordingSource>.fromOpaque(context).takeUnretainedValue()
    Task { @MainActor in
        source.poll()
    }
}

/// Watches for an active screen recording via a push notification rather
/// than polling -- same reasoning as `BatterySource`'s `IOKit.ps` source.
@MainActor
final class ScreenRecordingSource: LiveActivitySource {
    let id = "screenRecording"
    let priority = NotchLiveActivityPriority.screenRecording
    // A privacy indicator, not a competing surface -- it should never hide
    // now-playing's pill (confirmed on-device: it was taking over the whole
    // pill, artwork and all) or block hover-expand/skip while recording.
    let isBadge = true

    private let subject = CurrentValueSubject<LiveActivityContent?, Never>(nil)
    private let notchHeight: CGFloat
    private var isRecording = false

    var contentPublisher: AnyPublisher<LiveActivityContent?, Never> {
        subject.eraseToAnyPublisher()
    }

    init(notchHeight: CGFloat) {
        self.notchHeight = notchHeight
        // A named top-level function is implicitly @MainActor under this
        // project's default isolation, which a C function pointer can't be
        // formed from -- a bare closure literal at the call site sidesteps
        // that, same fix jackson-storm/dynamicnotch's own registration uses.
        let context = Unmanaged.passUnretained(self).toOpaque()
        _ = CGSRegisterNotifyProc({ screenRecordingEventCallback($0, $1, $2, $3) }, screenWatcherConnected, context)
        _ = CGSRegisterNotifyProc({ screenRecordingEventCallback($0, $1, $2, $3) }, screenWatcherDisconnected, context)
        poll()
    }

    fileprivate func poll() {
        let recording = CGSIsScreenWatcherPresent()
        guard recording != isRecording else { return }
        isRecording = recording
        subject.send(recording ? ScreenRecordingActivityContent(notchHeight: notchHeight) : nil)
    }
}
