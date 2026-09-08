import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// Installs a global `CGEventTap` on `kCGEventSystemDefined` events to
/// intercept the physical volume/brightness/mute function keys, apply the
/// change ourselves via `VolumeSource`/`BrightnessSource`, and suppress the
/// stock macOS HUD by returning `nil` from the tap callback -- that single
/// `nil` return is the entire suppression mechanism, matching
/// monuk7735/mew-notch's `MediaKeyManager.swift` (structurally adapted from
/// it, credited here per check-reference-apps-first).
///
/// Requires Accessibility permission (`AXIsProcessTrusted()`). If it isn't
/// granted yet at launch, polls once a second until it is (the common
/// case: the app is already running when the user clicks "Grant
/// Accessibility Access..." in the menu bar) rather than requiring a
/// relaunch. Stops cleanly if permission is revoked while running (the tap
/// disables itself, surfaced as `.tapDisabledByUserInput`).
///
/// Manual-verification only, like `NotchGestureModifier` and
/// `AppleScriptRunner` -- a real `CGEventTap` and real hardware keys aren't
/// something a unit test can exercise. The key-code -> action mapping and
/// the fail-open decision live in `MediaKeyMapping`, which is unit-tested.
final class MediaKeyInterceptor {
    private let volumeSource: VolumeSource
    private let brightnessSource: BrightnessSource
    // The run loop source is only ever added to the main run loop
    // (`install()` below), so the C tap callback only ever fires on the
    // main thread in practice -- these are only touched from `init`
    // (main-thread construction), the callback (main thread, per above),
    // and `deinit` at teardown, same reasoning as `BatterySource`'s/
    // `AirPodsSource`'s own `nonisolated(unsafe)` callback-touched state.
    nonisolated(unsafe) private var eventTap: CFMachPort?
    nonisolated(unsafe) private var runLoopSource: CFRunLoopSource?
    /// Retries `install()` while waiting for the user to grant
    /// Accessibility access -- launching before the grant (the common
    /// case: the app is already running when "Grant Accessibility
    /// Access..." is clicked) must not leave the tap permanently
    /// un-installed for the rest of the session. Stops itself once
    /// `install()` succeeds.
    nonisolated(unsafe) private var permissionPollTimer: Timer?

    init(volumeSource: VolumeSource, brightnessSource: BrightnessSource) {
        self.volumeSource = volumeSource
        self.brightnessSource = brightnessSource
        install()
        if eventTap == nil {
            startPollingForPermission()
        }
    }

    deinit {
        permissionPollTimer?.invalidate()
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
    }

    private func startPollingForPermission() {
        permissionPollTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            self.install()
            if self.eventTap != nil {
                timer.invalidate()
                self.permissionPollTimer = nil
            }
        }
    }

    /// `kCGEventSystemDefined`/`NSEvent.EventType.systemDefined`'s raw
    /// value -- not exposed as a `CGEventType` case in Swift's CoreGraphics
    /// overlay (unlike e.g. `.tapDisabledByTimeout`), so it's referenced by
    /// number, matching `NSEvent.EventType.systemDefined.rawValue`.
    private static let systemDefinedRawValue: UInt32 = 14

    private func install() {
        guard AccessibilityPermission.isGranted else { return }

        let mask = CGEventMask(1 << Self.systemDefinedRawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: CGEventTapOptions(rawValue: 0)!,
            eventsOfInterest: mask,
            callback: MediaKeyInterceptor.tapCallback,
            userInfo: refcon
        ) else { return }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    /// Free function, not a method: `CGEvent.tapCreate`'s callback is a
    /// plain C function pointer and can't capture `self` -- `userInfo`
    /// carries the instance instead, matching the `Unmanaged`-via-context
    /// pattern `BatterySource`/`AirPodsSource` already use for their own
    /// C-callback APIs.
    private static let tapCallback: CGEventTapCallBack = { _, type, cgEvent, refcon in
        guard let refcon else { return Unmanaged.passUnretained(cgEvent) }
        let interceptor = Unmanaged<MediaKeyInterceptor>.fromOpaque(refcon).takeUnretainedValue()
        return interceptor.handle(type: type, cgEvent: cgEvent)
    }

    private func handle(type: CGEventType, cgEvent: CGEvent) -> Unmanaged<CGEvent>? {
        // macOS disables a tap that's too slow to respond, or one the user
        // toggled off in System Settings -- re-enable it, matching
        // mew-notch's own handling of this event class, rather than
        // leaving media keys permanently uncaptured for the rest of the
        // session.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(cgEvent)
        }

        guard type.rawValue == Self.systemDefinedRawValue,
              let nsEvent = NSEvent(cgEvent: cgEvent),
              nsEvent.subtype.rawValue == 8 // NX_SUBTYPE_AUX_CONTROL_BUTTONS
        else {
            return Unmanaged.passUnretained(cgEvent)
        }

        let keyCode = Int32((nsEvent.data1 & 0xFFFF_0000) >> 16)
        let isKeyDown = ((nsEvent.data1 & 0x0000_FF00) >> 8) == 0x0A

        guard isKeyDown, let action = MediaKeyMapping.action(forKeyCode: keyCode) else {
            return Unmanaged.passUnretained(cgEvent)
        }

        let applied = apply(action)
        if MediaKeyMapping.shouldSuppressEvent(for: action, applySucceeded: applied) {
            return nil
        }
        return Unmanaged.passUnretained(cgEvent)
    }

    private func apply(_ action: MediaKeyAction) -> Bool {
        switch action {
        case .volumeUp: volumeSource.step(by: 1)
        case .volumeDown: volumeSource.step(by: -1)
        case .mute: volumeSource.toggleMute()
        case .brightnessUp: brightnessSource.step(by: 1)
        case .brightnessDown: brightnessSource.step(by: -1)
        }
    }
}
