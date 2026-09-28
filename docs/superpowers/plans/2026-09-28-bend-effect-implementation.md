# Desktop Bend Effect Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port IuCC123/BendMac's desktop-fold effect into Atelier as a new standalone `BendEffect/` subsystem, with full Appearance and Lid Behavior settings, matching the reference app (not a minimal slice).

**Architecture:** A new top-level `Atelier/BendEffect/` folder (sibling to `LockScreen/`, not `Notch/`): a pure `BendMath` (tested), an `IOHIDManager`-based `LidSensor`, a lock-guarded `FrameStore`, a `ScreenCaptureKit`-based `DesktopCapture`, a Metal shader + `BendRenderer`, a click-through `BendEffectOverlayWindow` covering only the built-in display, and a `BendEffectController` (`.shared` singleton, mirroring `TeleprompterModel`) that orchestrates all of them with a reconnect-on-failure state machine. Settings persist through `AtelierSettings` (existing convention) and surface in a new `Settings/Panes/BendEffectPane.swift`. A new `ScreenRecordingPermission` helper feeds a new `PermissionsPane` row.

**Tech Stack:** Swift 6 (strict concurrency), SwiftUI, AppKit, IOKit.hid, ScreenCaptureKit, MetalKit, Carbon.HIToolbox (Escape hotkey), Swift Testing.

**Spec:** `docs/superpowers/specs/2026-09-28-bend-effect-design.md`

## Global Constraints

- No third-party dependencies (CLAUDE.md Conventions).
- Deployment target stays `macos26.0` in the Xcode project even though the SDK is 27 (CLAUDE.md "What this is").
- Swift 6 strict concurrency throughout; non-`Sendable` AppKit/AV/Core types get `@unchecked Sendable` boxing confined to one queue/lock, matching `CameraMirrorSource.SessionBox`.
- The Xcode project uses `PBXFileSystemSynchronizedRootGroup` for both `Atelier/` and `AtelierTests/` — new files just need to be written to disk under those roots; no `.pbxproj` edits.
- Every ported file's header comment credits `IuCC123/BendMac (MIT)`, matching `ClickThroughHostingView.swift`'s existing attribution convention.
- Only `BendMath.swift` gets real unit tests (pure, deterministic). Everything else (HID sensor, `SCStream` capture, Metal rendering, the overlay window) is manual-verification only, like `LockScreen/*.swift` and `System/*.swift` — say so plainly rather than pretending coverage exists.
- Settings persist via `AtelierSettings` (existing `UserDefaults`-backed enum), not a private `defaults` instance inside the controller — this project's one settings-persistence convention, used by every other feature.
- "Only the built-in display is affected" ships as-is (per spec's open questions — this plan's call, since multi-monitor note-adding is a UI nicety, not a blocker).
- Menu-bar entry: this plan adds one `Toggle("Bend Effect", ...)` to `AtelierApp`'s menu, bound the same way `Ghost Mode` already is (via `@AppStorage` on the persisted key, not directly observing the controller) — resolving the spec's open question in favor of parity with the existing Ghost Mode toggle, since it costs one `Toggle` row.
- Open-at-login is **not** duplicated for this feature — `LaunchAtLogin`/`GeneralPane` already covers the whole app; `BendEffectPane`'s footer points there instead of adding a second per-feature toggle.

## Review Focus

- **Lid sensor absent on this exact hardware model** (a different MacBook, or a kernel/driver change removes it): `sensorAngle` stays `nil` forever. `targetProgress` must fall back to `clearAngle` (progress 0) when `followLid` is on and `sensorAngle` is `nil`, never crash or spin — covered by `settingsChanged()`'s explicit `sensorAngle == nil` branch (Task 7) and manually verified by disabling Follow Lid.
- **Screen Recording permission denied or revoked mid-session:** `connect()` must surface `needsAttention` and stop retrying forever (`requiresUserAction`), not hammer the OS with repeated failed `SCStream` starts — covered by Task 7's `requiresUserAction`/`needsUserAction` guard, manually verified via System Settings.
- **Lid reopened past `clearAngle` while mid-fold:** `progress` must animate back down to 0 and the overlay must hide and release the capture stream, not stay pinned open — covered by `tick()`'s `visible`/`overlay?.isVisible` toggling and the `target == 0 && progress <= 0.0005` teardown path (Task 7), manually verified by opening the lid during a bend.
- **Reduce Motion enabled:** the fold must jump straight to target progress with no smoothing tween, per this project's existing Reduce Motion convention (`NotchAnimations`) — covered by `tick()`'s `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` branch (Task 7), which BendMac's own code already had; explicitly called out here so it isn't dropped during the port.
- **`clearAngle` set at or below 13°** (user drags the calibrate slider to its extreme, or `calibrateOpenAngle` is called with a bogus sensor reading): `BendMath.progress`'s `max(1, clearAngle - 12)` denominator floor must prevent a divide-by-zero or negative-denominator blowup — this is the one input class that gets an explicit unit test (Task 1), since it's the one piece of this feature with real test coverage at all.

---

## Task 1: BendMath — pure fold math, unit tested

**Files:**
- Create: `Atelier/BendEffect/BendMath.swift`
- Test: `AtelierTests/BendMathTests.swift`

**Interfaces:**
- Produces: `enum BendMath { static func progress(angle: Double, clearAngle: Double) -> Double; static func smooth(current: Double, target: Double, dt: Double) -> Double }` — consumed by `BendEffectController` (Task 7) and `BendEffectPane`'s preview (Task 8).

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
@testable import Atelier

struct BendMathTests {
    // MARK: - progress

    @Test func progressAtClearAngleIsZero() {
        #expect(BendMath.progress(angle: 105, clearAngle: 105) == 0)
    }

    @Test func progressAboveClearAngleClampsToZero() {
        // Lid open wider than the clear angle must never produce a negative fold.
        #expect(BendMath.progress(angle: 130, clearAngle: 105) == 0)
    }

    @Test func progressAtTwelveDegreesClampsToOne() {
        // 12° is the reference app's practical fully-closed floor.
        #expect(BendMath.progress(angle: 12, clearAngle: 105) == 1)
    }

    @Test func progressBelowTwelveDegreesStillClampsToOne() {
        #expect(BendMath.progress(angle: 5, clearAngle: 105) == 1)
    }

    @Test func progressAtMidpointAngleIsExactlyOneHalf() {
        // Midpoint of the 12...clearAngle range smoothsteps to exactly 0.5
        // (t=0.5 -> t*t*(3-2t) = 0.25*2 = 0.5), a clean value to pin the curve to.
        let clearAngle = 105.0
        let midAngle = (clearAngle + 12) / 2
        #expect(BendMath.progress(angle: midAngle, clearAngle: clearAngle) == 0.5)
    }

    @Test func progressFloorsTinyClearAngleDenominatorRatherThanBlowingUp() {
        // clearAngle <= 13 makes (clearAngle - 12) <= 1; the denominator floors
        // at 1 so this stays a normal clamp instead of dividing by <= 0.
        #expect(BendMath.progress(angle: 5, clearAngle: 10) == 1)
        #expect(BendMath.progress(angle: 10, clearAngle: 10) == 0)
    }

    // MARK: - smooth

    @Test func smoothWithZeroDeltaTimeStaysAtCurrent() {
        #expect(BendMath.smooth(current: 0.3, target: 1.0, dt: 0) == 0.3)
    }

    @Test func smoothGlidesPartwayTowardTargetOverOneTimeConstant() {
        // dt equal to the 0.075s time constant covers exactly 1 - e^-1 of the gap.
        let result = BendMath.smooth(current: 0, target: 1, dt: 0.075)
        #expect(abs(result - (1 - exp(-1.0))) < 0.000001)
    }

    @Test func smoothClampsDeltaTimeAtOneTenthOfASecond() {
        // A stalled run loop (dt=5) must not overshoot -- it's clamped exactly
        // like a plausible dt of 0.1 would be.
        let clamped = BendMath.smooth(current: 0, target: 1, dt: 0.1)
        let stalled = BendMath.smooth(current: 0, target: 1, dt: 5)
        #expect(clamped == stalled)
    }

    @Test func smoothSnapsToTargetWithinEpsilonRatherThanCrawlingForever() {
        // Within 0.0003 of target, one 0.1s step lands within the 0.0001
        // snap threshold and returns the target exactly.
        let result = BendMath.smooth(current: 0.9997, target: 1.0, dt: 0.1)
        #expect(result == 1.0)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme Atelier -destination 'platform=macOS' -only-testing:AtelierTests/BendMathTests`
Expected: FAIL — `BendMath` does not exist yet (build error, not a test assertion failure).

- [ ] **Step 3: Write the implementation**

```swift
import Foundation

/// Adapted from IuCC123/BendMac's `BendMath.swift` (MIT). Blur-led motion:
/// the physical lid supplies most of the rotation. Works in screen-height
/// units so Retina scaling never alters the fold.
enum BendMath {
    /// Smoothstep-eased fold amount: 0 at `clearAngle`, ramping to 1 as the
    /// lid closes down toward 12° (its practical fully-closed floor).
    /// `max(1, clearAngle - 12)` keeps the denominator sane even if
    /// `clearAngle` is set at or below 13°.
    static func progress(angle: Double, clearAngle: Double) -> Double {
        let t = min(1, max(0, (clearAngle - angle) / max(1, clearAngle - 12)))
        return t * t * (3 - 2 * t)
    }

    /// Exponential glide from `current` toward `target` over `dt` seconds
    /// (clamped to 0.1s so a stalled run loop can't overshoot), snapping to
    /// `target` once within 0.0001 so the animation settles instead of
    /// crawling asymptotically forever.
    static func smooth(current: Double, target: Double, dt: Double) -> Double {
        let next = current + (target - current) * (1 - exp(-min(dt, 0.1) / 0.075))
        return abs(next - target) < 0.0001 ? target : next
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme Atelier -destination 'platform=macOS' -only-testing:AtelierTests/BendMathTests`
Expected: PASS, all 10 tests.

- [ ] **Step 5: Commit**

```bash
git add Atelier/BendEffect/BendMath.swift AtelierTests/BendMathTests.swift
git commit -m "feat: add BendMath, ported pure fold/glide math from BendMac"
```

---

## Task 2: Settings keys + ScreenRecordingPermission

**Files:**
- Modify: `Atelier/AtelierSettings.swift`
- Create: `Atelier/System/ScreenRecordingPermission.swift`

**Interfaces:**
- Consumes: nothing new.
- Produces: `AtelierSettings.bendEffectEnabled/bendEffectStyle/bendEffectPerspective/bendEffectBlur/bendEffectShadow/bendEffectClearAngle/bendEffectFollowLid/bendEffectManualAngle/bendEffectSound: { get set }` (all backed by `UserDefaults.standard`); `AtelierSettings.bendEffectEnabledKey` (needed by `AtelierApp`'s `@AppStorage` in Task 9); `enum ScreenRecordingPermission { static var isGranted: Bool; static func requestPrompt(); static func openSystemSettings() }` — consumed by `BendEffectController` (Task 7, indirectly via the `SCStream` prompt) and `PermissionsPane` (Task 8).

- [ ] **Step 1: Add the keys**

In `Atelier/AtelierSettings.swift`, add alongside the existing key list (after `nowPlayingSwipeSkipKey`):

```swift
    static let bendEffectEnabledKey = "bendEffectEnabled"
    static let bendEffectStyleKey = "bendEffectStyle"
    static let bendEffectPerspectiveKey = "bendEffectPerspective"
    static let bendEffectBlurKey = "bendEffectBlur"
    static let bendEffectShadowKey = "bendEffectShadow"
    static let bendEffectClearAngleKey = "bendEffectClearAngle"
    static let bendEffectFollowLidKey = "bendEffectFollowLid"
    static let bendEffectManualAngleKey = "bendEffectManualAngle"
    static let bendEffectSoundKey = "bendEffectSound"
```

- [ ] **Step 2: Register defaults**

In `registerDefaults()`'s dictionary, add (after `nowPlayingSwipeSkipKey: true`, note the trailing comma on that line needs adding):

```swift
            nowPlayingSwipeSkipKey: true,
            // Off by default -- Screen Recording is a materially broader
            // grant than anything else Atelier asks for, same reasoning as
            // glassEffectEnabledKey shipping conservatively.
            bendEffectStyleKey: 0,
            bendEffectPerspectiveKey: 1.0,
            bendEffectBlurKey: 0.9,
            bendEffectShadowKey: 0.35,
            bendEffectClearAngleKey: 105.0,
            bendEffectFollowLidKey: true,
            bendEffectManualAngleKey: 115.0
```

(`bendEffectEnabledKey` and `bendEffectSoundKey` are left unregistered -- `UserDefaults.standard.bool(forKey:)` already reads `false` for an unset key, matching how `shelfEnabledKey`'s sibling `colorPickerEnabledKey` pattern is handled elsewhere for off-by-default bools... actually check: register explicit `false` for clarity matching `glassEffectEnabledKey`'s own explicit-false precedent. Add both:)

```swift
            bendEffectEnabledKey: false,
            bendEffectSoundKey: false,
```

- [ ] **Step 3: Add computed accessors**

At the end of the enum, after `nowPlayingSwipeSkipEnabled`:

```swift
    /// Whether the desktop-bend overlay should run. Off by default --
    /// Screen Recording is a materially broader grant than anything else
    /// Atelier asks for, so this ships opt-in.
    static var bendEffectEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: bendEffectEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: bendEffectEnabledKey) }
    }

    /// 0 = Silk, 1 = Shade, 2 = Frost -- matches `Bend.metal`'s `p.style` bands.
    static var bendEffectStyle: Int {
        get { UserDefaults.standard.integer(forKey: bendEffectStyleKey) }
        set { UserDefaults.standard.set(newValue, forKey: bendEffectStyleKey) }
    }

    static var bendEffectPerspective: Double {
        get { UserDefaults.standard.double(forKey: bendEffectPerspectiveKey) }
        set { UserDefaults.standard.set(newValue, forKey: bendEffectPerspectiveKey) }
    }

    static var bendEffectBlur: Double {
        get { UserDefaults.standard.double(forKey: bendEffectBlurKey) }
        set { UserDefaults.standard.set(newValue, forKey: bendEffectBlurKey) }
    }

    static var bendEffectShadow: Double {
        get { UserDefaults.standard.double(forKey: bendEffectShadowKey) }
        set { UserDefaults.standard.set(newValue, forKey: bendEffectShadowKey) }
    }

    /// The lid angle (degrees) above which the desktop is undistorted.
    static var bendEffectClearAngle: Double {
        get { UserDefaults.standard.double(forKey: bendEffectClearAngleKey) }
        set { UserDefaults.standard.set(newValue, forKey: bendEffectClearAngleKey) }
    }

    static var bendEffectFollowLid: Bool {
        get { UserDefaults.standard.bool(forKey: bendEffectFollowLidKey) }
        set { UserDefaults.standard.set(newValue, forKey: bendEffectFollowLidKey) }
    }

    static var bendEffectManualAngle: Double {
        get { UserDefaults.standard.double(forKey: bendEffectManualAngleKey) }
        set { UserDefaults.standard.set(newValue, forKey: bendEffectManualAngleKey) }
    }

    /// Plays a soft sound once the desktop finishes unfolding back flat.
    static var bendEffectSound: Bool {
        get { UserDefaults.standard.bool(forKey: bendEffectSoundKey) }
        set { UserDefaults.standard.set(newValue, forKey: bendEffectSoundKey) }
    }
```

- [ ] **Step 4: Create `ScreenRecordingPermission`**

```swift
import AppKit
import CoreGraphics

/// Screen Recording TCC helper -- same thin shape as `AccessibilityPermission`:
/// a live, uncached status read plus a deep link to the right pane. Binary
/// like Accessibility (macOS doesn't distinguish "not asked yet" from
/// "denied" for `CGPreflightScreenCaptureAccess`), so it can't be requested
/// with a completion handler the way Camera/Microphone can -- the real
/// prompt appears the first time `BendEffectController` actually starts an
/// `SCStream`.
enum ScreenRecordingPermission {
    static var isGranted: Bool {
        CGPreflightScreenCaptureAccess()
    }

    static func requestPrompt() {
        _ = CGRequestScreenCaptureAccess()
    }

    static func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else { return }
        NSWorkspace.shared.open(url)
    }
}
```

- [ ] **Step 5: Build to verify no regressions**

Run: `xcodebuild -scheme Atelier -configuration Debug build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 6: Commit**

```bash
git add Atelier/AtelierSettings.swift Atelier/System/ScreenRecordingPermission.swift
git commit -m "feat: add BendEffect settings keys and ScreenRecordingPermission helper"
```

---

## Task 3: LidSensor — HID lid-angle polling

**Files:**
- Create: `Atelier/BendEffect/LidSensor.swift`

**Interfaces:**
- Produces: `final class LidSensor { enum PollingMode { case idle, watching, active }; var onAngle: ((Double?) -> Void)?; func start(); func reconnect(); func setMode(_ mode: PollingMode); func setSuspended(_ suspended: Bool) }` — consumed by `BendEffectController` (Task 7).

- [ ] **Step 1: Port the file near-verbatim**

```swift
import Foundation
import IOKit.hid

/// Adapted from IuCC123/BendMac's `LidSensor.swift` (MIT). Public IOKit
/// transport; Apple's lid report itself is undocumented. Read-only,
/// non-exclusive, no driver installation or root access. Confirmed live on
/// this machine (MacBook Pro M3, Mac15,3) -- see the design spec.
final class LidSensor {
    private let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    private var device: IOHIDDevice?
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "atelier.bendEffect.lid", qos: .userInteractive)
    enum PollingMode { case idle, watching, active }
    private var mode: PollingMode = .idle
    private var suspended = false
    private var lastDiscovery = Date.distantPast
    var onAngle: ((Double?) -> Void)?

    init() {
        let match: [String: Any] = [
            kIOHIDVendorIDKey: 0x05AC, kIOHIDPrimaryUsagePageKey: 0x20, kIOHIDPrimaryUsageKey: 0x8A,
        ]
        IOHIDManagerSetDeviceMatching(manager, match as CFDictionary)
        IOHIDManagerOpen(manager, 0)
        if let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> {
            device = devices.first { IOHIDDeviceOpen($0, 0) == kIOReturnSuccess }
        }
    }
    func read() -> Double? {
        guard let device else { return nil }
        var bytes = [UInt8](repeating: 0, count: 8)
        var count = bytes.count
        guard IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 1, &bytes, &count) == kIOReturnSuccess,
            count >= 3
        else { return nil }
        let value = Int(bytes[1]) | Int(bytes[2]) << 8
        guard (0...180).contains(value) else { return nil }
        return Double(value)
    }
    func start() {
        guard timer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(250), leeway: .milliseconds(10))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            var angle = self.read()
            // Devices can appear after login or disappear during sleep. Keep discovery alive
            // even after the app's bounded capture retry loop has stopped.
            if angle == nil && Date().timeIntervalSince(self.lastDiscovery) >= 1 {
                self.findDevice()
                angle = self.read()
            }
            DispatchQueue.main.async { [weak self] in self?.onAngle?(angle) }
        }
        self.timer = timer
        timer.resume()
    }
    private func findDevice() {
        lastDiscovery = Date()
        if let device { IOHIDDeviceClose(device, 0) }
        device = nil
        if let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> {
            device = devices.first { IOHIDDeviceOpen($0, 0) == kIOReturnSuccess }
        }
    }
    func reconnect() {
        queue.async { [weak self] in self?.findDevice() }
    }
    func setMode(_ mode: PollingMode) {
        guard self.mode != mode else { return }
        self.mode = mode
        updateSchedule()
    }
    func setSuspended(_ suspended: Bool) {
        self.suspended = suspended
        updateSchedule()
    }
    private func updateSchedule() {
        let milliseconds = mode == .active ? 16 : mode == .watching ? 100 : 250
        timer?.schedule(
            deadline: suspended ? .distantFuture : .now(), repeating: .milliseconds(milliseconds),
            leeway: .milliseconds(mode == .active ? 2 : 10))
    }
    deinit {
        timer?.cancel()
        if let device { IOHIDDeviceClose(device, 0) }
        IOHIDManagerClose(manager, 0)
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `xcodebuild -scheme Atelier -configuration Debug build`
Expected: BUILD SUCCEEDED. This is manual-verification only from here — no unit test, per Global Constraints (needs real HID hardware).

- [ ] **Step 3: Commit**

```bash
git add Atelier/BendEffect/LidSensor.swift
git commit -m "feat: port LidSensor from BendMac"
```

---

## Task 4: FrameStore + DesktopCapture

**Files:**
- Create: `Atelier/BendEffect/FrameStore.swift`
- Create: `Atelier/BendEffect/DesktopCapture.swift`

**Interfaces:**
- Produces: `final class FrameStore: @unchecked Sendable { func put(_:displayTime:); func get() -> CVPixelBuffer?; var hasFrame: Bool; func clear() }`; `final class DesktopCapture: NSObject, SCStreamOutput, SCStreamDelegate { init(frames: FrameStore); var onError: ((Error) -> Void)?; var onFirstFrame: (() -> Void)?; var frameCount: Int { get }; func start(displayID: CGDirectDisplayID) async throws; func setBending(_ active: Bool) async; func stop() async }` — both consumed by `BendRenderer` (Task 5) and `BendEffectController` (Task 7).

- [ ] **Step 1: Create `FrameStore.swift`**

```swift
import CoreVideo
import Foundation

/// Adapted from IuCC123/BendMac's `Renderer.swift` (MIT), extracted into
/// its own file since both `DesktopCapture` and `BendRenderer` depend on
/// it. Latest-frame mailbox between the capture-queue callback and the
/// Metal draw callback -- `CVPixelBuffer` isn't `Sendable`, so this is a
/// lock-guarded box, same reasoning as `CameraMirrorSource.SessionBox`.
final class FrameStore: @unchecked Sendable {
    private let lock = NSLock()
    private var latest: CVPixelBuffer?
    private var displayTime: UInt64 = 0

    func put(_ frame: CVPixelBuffer, displayTime: UInt64 = 0) {
        lock.lock()
        latest = frame
        self.displayTime = displayTime
        lock.unlock()
    }

    func get() -> CVPixelBuffer? {
        lock.lock()
        defer { lock.unlock() }
        return latest
    }

    var hasFrame: Bool {
        lock.lock()
        defer { lock.unlock() }
        return latest != nil
    }

    func clear() {
        lock.lock()
        latest = nil
        displayTime = 0
        lock.unlock()
    }
}
```

- [ ] **Step 2: Create `DesktopCapture.swift`**

```swift
import CoreMedia
import ScreenCaptureKit

enum CaptureError: LocalizedError {
    case applicationUnavailable

    var errorDescription: String? {
        "Atelier could not safely exclude its own windows from screen capture. Try enabling the bend effect again."
    }
}

/// Adapted from IuCC123/BendMac's `DesktopCapture.swift` (MIT). Invariant 2
/// from CLAUDE.md doesn't apply here (there's no other app to avoid
/// launching), but the same "don't act until the OS has actually caught up
/// with us" caution does: never start an unfiltered stream before
/// ScreenCaptureKit has discovered this process's own windows, or the
/// filter below excludes nothing.
final class DesktopCapture: NSObject, SCStreamOutput, SCStreamDelegate {
    let frames: FrameStore
    @MainActor private var stream: SCStream?
    @MainActor private var config: SCStreamConfiguration?
    private let queue = DispatchQueue(label: "atelier.bendEffect.capture", qos: .userInteractive)
    var onError: ((Error) -> Void)?
    var onFirstFrame: (() -> Void)?
    private let countLock = NSLock()
    private var count = 0
    private var outputStream: SCStream?
    @MainActor private var generation = 0
    @MainActor private var desiredBending = false
    @MainActor private var updatingRate = false
    var frameCount: Int {
        countLock.lock()
        defer { countLock.unlock() }
        return count
    }
    init(frames: FrameStore) { self.frames = frames }

    @MainActor func start(displayID: CGDirectDisplayID) async throws {
        generation += 1
        let request = generation
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard request == generation else { throw CancellationError() }
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw NSError(domain: "The built-in display is unavailable.", code: 1)
        }
        let ownApp = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        // A login launch may have no on-screen windows. Never start an unfiltered
        // stream if ScreenCaptureKit has not discovered this process yet.
        guard !ownApp.isEmpty else { throw CaptureError.applicationUnavailable }
        // Exclude our entire process, including windows shown after capture starts.
        let filter = SCContentFilter(display: display, excludingApplications: ownApp, exceptingWindows: [])
        let config = SCStreamConfiguration()
        // Use the display mode's backing resolution for Retina capture.
        let mode = CGDisplayCopyDisplayMode(displayID)
        config.width = mode?.pixelWidth ?? CGDisplayPixelsWide(displayID)
        config.height = mode?.pixelHeight ?? CGDisplayPixelsHigh(displayID)
        config.minimumFrameInterval = CMTime(value: 1, timescale: 5)
        config.queueDepth = 3
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = false
        config.capturesAudio = false
        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        self.stream = stream
        self.config = config
        desiredBending = false
        acceptOutput(from: stream)
        do {
            try await stream.startCapture()
            guard request == generation else {
                try? await stream.stopCapture()
                throw CancellationError()
            }
        } catch {
            if self.stream === stream {
                self.stream = nil
                self.config = nil
                acceptOutput(from: nil)
            }
            throw error
        }
    }
    @MainActor func setBending(_ active: Bool) async {
        desiredBending = active
        guard !updatingRate else { return }
        updatingRate = true
        defer { updatingRate = false }
        while let stream, let config {
            let requested = desiredBending
            config.minimumFrameInterval = CMTime(value: 1, timescale: requested ? 60 : 5)
            do { try await stream.updateConfiguration(config) } catch {
                if self.stream === stream {
                    onError?(error)
                    return
                }
                // An obsolete stream must not discard a newer stream's pending rate change.
                continue
            }
            if self.stream === stream && requested == desiredBending { return }
        }
    }
    @MainActor func stop() async {
        generation += 1
        let old = stream
        stream = nil
        config = nil
        acceptOutput(from: nil)
        try? await old?.stopCapture()
    }
    private func acceptOutput(from stream: SCStream?) {
        countLock.lock()
        defer { countLock.unlock() }
        outputStream = stream
        frames.clear()
    }
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor [weak self] in
            guard let self, self.stream === stream else { return }
            self.onError?(error)
        }
    }
    func stream(
        _ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType
    ) {
        guard type == .screen, sampleBuffer.isValid,
            let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
            let raw = attachments.first?[.status] as? Int,
            SCFrameStatus(rawValue: raw) == .complete,
            let pixelBuffer = sampleBuffer.imageBuffer
        else { return }
        countLock.lock()
        defer { countLock.unlock() }
        guard outputStream === stream else { return }
        let firstFrame = frames.get() == nil
        frames.put(pixelBuffer, displayTime: attachments.first?[.displayTime] as? UInt64 ?? 0)
        if firstFrame {
            Task { @MainActor [weak self] in
                guard let self, self.stream === stream else { return }
                self.onFirstFrame?()
            }
        }
        count += 1
    }
}
```

- [ ] **Step 3: Build; fix any Swift 6 strict-concurrency diagnostics**

Run: `xcodebuild -scheme Atelier -configuration Debug build`
Expected: BUILD SUCCEEDED. If the compiler flags `onError`/`onFirstFrame` for crossing isolation, they are only ever assigned once (from `BendEffectController.init`, on the main actor, before `capture.start` is ever called) and read from a `Task { @MainActor in ... }` hop — matching the original's already-Swift-6-clean design. If it still complains, mark the two closures `nonisolated(unsafe)` with a one-line comment citing this same reasoning (same pattern `LockScreenManager`'s observers use), rather than restructuring the class.

- [ ] **Step 4: Commit**

```bash
git add Atelier/BendEffect/FrameStore.swift Atelier/BendEffect/DesktopCapture.swift
git commit -m "feat: port FrameStore and DesktopCapture from BendMac"
```

---

## Task 5: Bend.metal + BendRenderer

**Files:**
- Create: `Atelier/BendEffect/Bend.metal`
- Create: `Atelier/BendEffect/BendRenderer.swift`

**Interfaces:**
- Consumes: `FrameStore` (Task 4).
- Produces: `struct BendParameters { var progress, perspective, blur, shadow, style: Float }`; `final class BendRenderer: NSObject, MTKViewDelegate { init(frames: FrameStore, preview: CGImage? = nil) throws; var parameters: @MainActor () -> BendParameters; func makeView() -> MTKView }` — consumed by `BendEffectOverlayWindow` (Task 6), `BendEffectController` (Task 7), and `BendEffectPane`'s live preview (Task 8).

- [ ] **Step 1: Port `Bend.metal` verbatim**

```metal
// Adapted from IuCC123/BendMac's Bend.metal (MIT).
#include <metal_stdlib>
using namespace metal;
struct VertexOut { float4 position [[position]]; float2 uv; };
struct Params { float progress; float perspective; float blur; float shadow; float style; };
vertex VertexOut bendVertex(uint id [[vertex_id]]) {
    float2 p[3] = {float2(-1,-1), float2(3,-1), float2(-1,3)};
    VertexOut out; out.position=float4(p[id],0,1); out.uv=float2((p[id].x+1)*0.5,(1-p[id].y)*0.5); return out;
}
fragment float4 bendFragment(VertexOut in [[stage_in]], texture2d<float> desktop [[texture(0)]], texture2d<float> fine [[texture(1)]], texture2d<float> soft [[texture(2)]], texture2d<float> medium [[texture(3)]], texture2d<float> strong [[texture(4)]], constant Params &p [[buffer(0)]]) {
    constexpr sampler s(coord::normalized,address::clamp_to_edge,filter::linear);
    float fold=clamp(p.progress,0.0,1.0);
    if (fold < 0.00001) return desktop.sample(s,in.uv);
    float height=1.0-in.uv.y;
    // Inverse projective mapping. The lower edge stays anchored at the hinge,
    // while the upper corners draw inward like the reference's folding sheet.
    // A single homography keeps straight desktop lines straight throughout.
    float taper=0.24*fold*p.perspective;
    float depth=(2.0*taper)/max(0.1,1.0-2.0*taper);
    float sourceHeight=height/(1.0+depth*(1.0-height));
    float width=1.0/(1.0+depth*sourceHeight);
    float inset=(1.0-width)*0.5;
    float2 uv=float2((in.uv.x-0.5)/width+0.5,1.0-sourceHeight);
    float hingeWeight=smoothstep(0.0,0.22,height);
    // Concentrate defocus at the upper edge, including the menu bar. Keeping
    // the centre readable avoids making the whole desktop look out of focus.
    float radius=48.0*fold*pow(height,3.5)*(p.style>1.5 ? 1.25 : 1.0);
    float3 color;
    if (p.blur<0.001) color=desktop.sample(s,uv).rgb;
    else if(radius<4.0) color=mix(desktop.sample(s,uv).rgb,fine.sample(s,uv).rgb,smoothstep(0.0,4.0,radius));
    else if(radius<10.0) color=mix(fine.sample(s,uv).rgb,soft.sample(s,uv).rgb,smoothstep(4.0,10.0,radius));
    else if(radius<28.0) color=mix(soft.sample(s,uv).rgb,medium.sample(s,uv).rgb,smoothstep(10.0,28.0,radius));
    else color=mix(medium.sample(s,uv).rgb,strong.sample(s,uv).rgb,smoothstep(28.0,64.0,radius));
    // Feather the sides, not a horizontal black strip across the top.
    float feather=max(fwidth(in.uv.x),0.0025*fold*height);
    float edge=min(in.uv.x-inset,1.0-inset-in.uv.x);
    float coverage=smoothstep(-feather,feather,edge);
    float sideShade=exp(-max(edge,0.0)/0.035)*fold*p.shadow*0.22*height*hingeWeight;
    if(p.style>0.5 && p.style<1.5) sideShade*=1.6;
    color*=1.0-sideShade;
    if(p.style>1.5) color=mix(color,float3(0.86,0.9,0.94),fold*pow(height,2.3)*0.08);
    return float4(color*coverage,1);
}
```

- [ ] **Step 2: Port `BendRenderer.swift`**

```swift
import AppKit
import CoreVideo
import MetalKit
import MetalPerformanceShaders

struct BendParameters {
    var progress: Float = 0
    var perspective: Float = 1
    var blur: Float = 0.9
    var shadow: Float = 0.35
    var style: Float = 0
}

private enum RenderError: LocalizedError {
    case allocation(String)
    case encoding

    var errorDescription: String? {
        switch self {
        case .allocation(let resource): return "Could not allocate \(resource) for rendering."
        case .encoding: return "Could not create the render encoder."
        }
    }
}

/// Adapted from IuCC123/BendMac's `Renderer.swift` (MIT). First `MTKView`/
/// Metal pipeline in Atelier -- establishes the pattern for anything that
/// comes after it.
final class BendRenderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private var cache: CVMetalTextureCache!
    private let fallback: MTLTexture
    private var blurTextures = [MTLTexture]()
    private var blurKernels = [MPSImageGaussianBlur]()
    private var blurStrength: Float = -1
    private lazy var scaleKernel = MPSImageBilinearScale(device: device)
    private var blurredSource: MTLTexture?
    let frames: FrameStore
    var parameters: @MainActor () -> BendParameters = { BendParameters() }

    init(frames: FrameStore, preview: CGImage? = nil) throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue(),
            let library = device.makeDefaultLibrary()
        else { throw NSError(domain: "Metal unavailable", code: 1) }
        self.device = device
        self.queue = queue
        self.frames = frames
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "bendVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "bendFragment")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        let cg = preview ?? Self.fallbackImage()
        let td = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: cg.width, height: cg.height, mipmapped: false)
        guard let texture = device.makeTexture(descriptor: td) else {
            throw RenderError.allocation("the fallback texture")
        }
        var pixels = [UInt8](repeating: 0, count: cg.width * cg.height * 4)
        pixels.withUnsafeMutableBytes { bytes in
            let context = CGContext(
                data: bytes.baseAddress, width: cg.width, height: cg.height, bitsPerComponent: 8,
                bytesPerRow: cg.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
            texture.replace(
                region: MTLRegionMake2D(0, 0, cg.width, cg.height), mipmapLevel: 0,
                withBytes: bytes.baseAddress!, bytesPerRow: cg.width * 4)
        }
        fallback = texture
        super.init()
        CVMetalTextureCacheCreate(nil, nil, device, nil, &cache)
    }
    func makeView() -> MTKView {
        let view = MTKView(frame: .zero, device: device)
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColorMake(0, 0, 0, 0)
        view.preferredFramesPerSecond = 60
        view.framebufferOnly = true
        view.delegate = self
        return view
    }
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable, let pass = view.currentRenderPassDescriptor,
            let command = queue.makeCommandBuffer()
        else { return }
        var retained: CVMetalTexture?
        var texture = fallback
        let sourceFrame = frames.get()
        if let frame = sourceFrame {
            CVMetalTextureCacheCreateTextureFromImage(
                nil, cache, frame, nil, .bgra8Unorm, CVPixelBufferGetWidth(frame),
                CVPixelBufferGetHeight(frame), 0, &retained)
            if let retained, let live = CVMetalTextureGetTexture(retained) { texture = live }
        }
        var p = MainActor.assumeIsolated { parameters() }
        // The live effect can omit blur under memory pressure; that's an
        // acceptable degrade -- the fold shape itself must never fail to draw.
        let unblurred = [texture, texture, texture, texture]
        let blurred =
            p.progress < 0.0001
            ? unblurred
            : (try? encodeBlur(texture, command: command, strength: p.blur)) ?? unblurred
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else {
            blurredSource = nil
            return
        }
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(texture, index: 0)
        for (i, t) in blurred.enumerated() { encoder.setFragmentTexture(t, index: i + 1) }
        encoder.setFragmentBytes(&p, length: MemoryLayout<BendParameters>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        command.present(drawable)
        // Retain the CV-backed texture until GPU completion.
        let held = (retained, sourceFrame)
        command.addCompletedHandler { _ in withExtendedLifetime(held) {} }
        command.commit()
    }
    private func encodeBlur(_ source: MTLTexture, command: MTLCommandBuffer, strength: Float) throws
        -> [MTLTexture]
    {
        if strength < 0.001 { return [source, source, source, source] }
        // Cap the blur working resolution independently of the Retina capture.
        // Sigma scales with this width to preserve the intended blur radius.
        let w = max(1, min(source.width / 4, 480))
        let h = max(1, source.height * w / source.width)
        if blurTextures.count != 5 || blurTextures.first?.width != w || blurTextures.first?.height != h {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba8Unorm, width: w, height: h, mipmapped: false)
            descriptor.usage = [.shaderRead, .shaderWrite]
            descriptor.storageMode = .private
            blurTextures = (0..<5).compactMap { _ in device.makeTexture(descriptor: descriptor) }
            blurStrength = -1
            blurredSource = nil
        }
        guard blurTextures.count == 5 else { throw RenderError.allocation("blur textures") }
        if abs(blurStrength - strength) > 0.001 {
            blurredSource = nil
            blurKernels = [4.0, 10.0, 28.0, 64.0].map {
                let kernel = MPSImageGaussianBlur(
                    device: device, sigma: Float($0) * Float(w) / 880 * strength / 0.9)
                kernel.edgeMode = .clamp
                return kernel
            }
            blurStrength = strength
        }
        // The static fallback wallpaper needs new blur passes only when strength changes.
        if source === fallback && blurredSource === fallback && abs(blurStrength - strength) <= 0.001 {
            return Array(blurTextures.dropFirst())
        }
        scaleKernel.encode(
            commandBuffer: command, sourceTexture: source, destinationTexture: blurTextures[0])
        for i in 0..<4 {
            blurKernels[i].encode(
                commandBuffer: command, sourceTexture: blurTextures[0],
                destinationTexture: blurTextures[i + 1])
        }
        blurredSource = source
        return Array(blurTextures.dropFirst())
    }
    /// Shown until the first real capture frame arrives, and behind the
    /// live preview in Settings before a real desktop frame is available.
    static func fallbackImage() -> CGImage {
        let size = NSSize(width: 1280, height: 800)
        let image = NSImage(size: size, flipped: false) { rect in
            NSGradient(colors: [
                NSColor(red: 0.16, green: 0.23, blue: 0.34, alpha: 1),
                NSColor(red: 0.57, green: 0.65, blue: 0.75, alpha: 1),
            ])!.draw(in: rect, angle: 90)
            for layer in stride(from: 4, through: 0, by: -1) {
                let path = NSBezierPath()
                path.move(to: .zero)
                for i in 0...100 {
                    let x = Double(i) / 100 * 1280
                    let y =
                        130 + Double(layer) * 65 + sin(x / 210 + Double(layer) * 1.1) * 45 + sin(
                            x / 95 + Double(layer)) * 15
                    path.line(to: NSPoint(x: x, y: y))
                }
                path.line(to: NSPoint(x: 1280, y: 0))
                path.close()
                NSColor(
                    calibratedRed: 0.15 + Double(layer) * 0.09, green: 0.2 + Double(layer) * 0.09,
                    blue: 0.28 + Double(layer) * 0.09, alpha: 1
                ).setFill()
                path.fill()
            }
            return true
        }
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
    }
}
```

(Note: `previewImage()`'s clock/date drawing and `exportPreview` offline-QA export from the reference app are dropped -- Atelier has no equivalent QA-screenshot pipeline to wire them into, and the fallback texture only needs to look like *a* desktop, not a specific one. If a future session wants the offline PNG export for visual regression checks, it can be added back verbatim from the reference app's `Renderer.swift`.)

- [ ] **Step 3: Build to verify the Metal shader compiles and links**

Run: `xcodebuild -scheme Atelier -configuration Debug build`
Expected: BUILD SUCCEEDED, including the `.metal` file compiling into the default Metal library (picked up automatically by the synchronized file group).

- [ ] **Step 4: Commit**

```bash
git add Atelier/BendEffect/Bend.metal Atelier/BendEffect/BendRenderer.swift
git commit -m "feat: port Bend.metal and BendRenderer from BendMac"
```

---

## Task 6: BendEffectOverlayWindow

**Files:**
- Create: `Atelier/BendEffect/BendEffectOverlayWindow.swift`

**Interfaces:**
- Consumes: `BendRenderer.makeView() -> MTKView` (Task 5).
- Produces: `@MainActor final class BendEffectOverlayWindow: NSPanel { init(screenFrame: CGRect, renderer: BendRenderer); func show(); func hide() }` — consumed by `BendEffectController` (Task 7).

- [ ] **Step 1: Write the new file**

```swift
import AppKit
import MetalKit

/// New file, not a port (per the design spec) -- covers only the built-in
/// display while the fold is visible. Non-key, non-main, click-through, and
/// sits just above the menu bar, same "never intercept input" posture as
/// `NotchPanel`. Window construction adapted from IuCC123/BendMac's
/// `AppModel.OverlayWindow` and the inline setup in `AppModel.connect()`
/// (MIT), consolidated here since Atelier's window-lifecycle conventions
/// differ enough from BendMac's own `AppModel` that adapting beats porting
/// line-for-line.
@MainActor
final class BendEffectOverlayWindow: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    let metalView: MTKView

    init(screenFrame: CGRect, renderer: BendRenderer) {
        let view = renderer.makeView()
        view.layer?.isOpaque = false
        view.isPaused = true
        self.metalView = view
        super.init(
            contentRect: screenFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        // Transparent until Metal has drawn: an undrawn frame then shows the
        // real desktop underneath, not black.
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        contentView = view
        setFrame(screenFrame, display: true)
    }

    func show() {
        metalView.isPaused = false
        orderFrontRegardless()
    }

    func hide() {
        orderOut(nil)
        metalView.isPaused = true
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `xcodebuild -scheme Atelier -configuration Debug build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add Atelier/BendEffect/BendEffectOverlayWindow.swift
git commit -m "feat: add BendEffectOverlayWindow"
```

---

## Task 7: BendEffectController — the state machine

**Files:**
- Create: `Atelier/BendEffect/BendEffectController.swift`

**Interfaces:**
- Consumes: `LidSensor` (Task 3), `FrameStore`/`DesktopCapture` (Task 4), `BendRenderer`/`BendParameters` (Task 5), `BendEffectOverlayWindow` (Task 6), `BendMath` (Task 1), `AtelierSettings.bendEffect*` (Task 2).
- Produces: `@MainActor final class BendEffectController: ObservableObject { static let shared: BendEffectController; @Published private(set) var wantsEnabled, enabled, starting: Bool; @Published private(set) var status: String; @Published private(set) var sensorAngle: Double?; @Published var previewAngle, previewPlaying, previewFollowsLid; let previewFrames: FrameStore; func enable(); func disable(message:preserveIntent:); func playPreview(); func calibrateOpenAngle(); func resetAppearance(); func parameters(preview:) -> BendParameters; var displayedPreviewAngle: Double }` — consumed by `BendEffectPane` (Task 8) and `AtelierApp` (Task 9).

- [ ] **Step 1: Write the controller**

```swift
import AppKit
import Carbon.HIToolbox
import MetalKit
import ScreenCaptureKit

/// Orchestrates sensor -> capture -> renderer -> overlay for the desktop
/// bend effect. State-machine shape ported from IuCC123/BendMac's
/// `AppModel.swift` (MIT) -- reconnect-on-failure, capture only starts once
/// actually bending -- minus the Settings-window/menu-bar/Sparkle-updater
/// concerns that file mixed in, which stay in Atelier's own conventional
/// places (`BendEffectPane`, `AtelierSettings`, the app-wide `LaunchAtLogin`).
@MainActor
final class BendEffectController: ObservableObject {
    static let shared = BendEffectController()

    @Published private(set) var wantsEnabled: Bool {
        didSet { AtelierSettings.bendEffectEnabled = wantsEnabled }
    }
    @Published private(set) var enabled = false
    @Published private(set) var starting = false
    @Published private(set) var status = "Ready to preview. Enable to bend your desktop."
    @Published private(set) var sensorAngle: Double?
    @Published var previewAngle = 105.0
    @Published var previewPlaying = false
    @Published var previewFollowsLid = false

    let frames = FrameStore()
    let previewFrames = FrameStore()
    let sensor = LidSensor()
    lazy var capture = DesktopCapture(frames: frames)
    private var overlay: BendEffectOverlayWindow?
    private var renderer: BendRenderer?

    private var timer: Timer?
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var generation = 0
    private var stopping = false
    private var sleeping = false
    private var needsUserAction = false
    private var reconnectTask: Task<Void, Never>?
    private var progress = 0.0
    private var lastTime = CACurrentMediaTime()
    private var playStart = 0.0
    private var wasFolded = false

    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    private init() {
        wantsEnabled = AtelierSettings.bendEffectEnabled
        sensor.onAngle = { [weak self] angle in
            guard let self, !self.sleeping else { return }
            guard self.sensorAngle != angle else { return }
            let becameAvailable = self.sensorAngle == nil && angle != nil
            self.sensorAngle = angle
            if self.enabled || self.starting || becameAvailable { self.settingsChanged() }
        }
        sensor.start()
        capture.onError = { [weak self] error in
            guard let self else { return }
            if Self.requiresUserAction(error) {
                self.disable(message: "Screen capture stopped. Enable the bend effect again when you are ready.")
            } else {
                self.interrupt(message: "Capture interrupted: \(error.localizedDescription)")
            }
        }
        capture.onFirstFrame = { [weak self] in
            if self?.enabled == true { self?.startTicking() }
        }
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        observers.append((workspaceCenter, workspaceCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.sleeping = true
                self.sensor.setSuspended(true)
                self.interrupt(message: "Paused until your Mac wakes.")
            }
        }))
        observers.append((workspaceCenter, workspaceCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.sleeping = false
                self.sensorAngle = nil
                self.sensor.setSuspended(false)
                self.sensor.reconnect()
                self.scheduleReconnect()
            }
        }))
        observers.append((NotificationCenter.default, NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                if self?.wantsEnabled == true {
                    self?.interrupt(message: "Reconnecting to your display…")
                }
            }
        }))
        observers.append((NotificationCenter.default, NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.settingsChanged() }
        }))
        scheduleReconnect()
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, context in
                guard let context else { return OSStatus(eventNotHandledErr) }
                let controller = Unmanaged<BendEffectController>.fromOpaque(context).takeUnretainedValue()
                MainActor.assumeIsolated { controller.disable(message: "Paused with Escape.") }
                return noErr
            }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    deinit {
        reconnectTask?.cancel()
        timer?.invalidate()
        for (center, observer) in observers { center.removeObserver(observer) }
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }

    func parameters(preview: Bool = false) -> BendParameters {
        var p = BendParameters()
        p.progress = Float(
            preview ? BendMath.progress(angle: displayedPreviewAngle, clearAngle: AtelierSettings.bendEffectClearAngle) : progress)
        p.perspective = Float(AtelierSettings.bendEffectPerspective)
        p.blur = Float(AtelierSettings.bendEffectBlur)
        p.shadow = Float(AtelierSettings.bendEffectShadow)
        p.style = Float(AtelierSettings.bendEffectStyle)
        return p
    }

    var displayedPreviewAngle: Double {
        previewFollowsLid ? (sensorAngle ?? AtelierSettings.bendEffectClearAngle) : previewAngle
    }

    func calibrateOpenAngle() {
        guard let sensorAngle else { return }
        AtelierSettings.bendEffectClearAngle = min(135, max(80, sensorAngle))
    }

    func resetAppearance() {
        AtelierSettings.bendEffectPerspective = 1
        AtelierSettings.bendEffectBlur = 0.9
        AtelierSettings.bendEffectShadow = 0.35
        AtelierSettings.bendEffectStyle = 0
    }

    func enable() {
        needsUserAction = false
        wantsEnabled = true
        scheduleReconnect(immediate: true)
    }

    func disable(message: String = "Paused. Your desktop is back to normal.", preserveIntent: Bool = false) {
        stopEffect(message: message, preserveIntent: preserveIntent, keepReady: false)
    }

    func playPreview() {
        previewFollowsLid = false
        playStart = CACurrentMediaTime()
        previewPlaying = true
        startTicking()
    }

    // Match the visibility threshold so imperceptible lid jitter never starts capture.
    private var targetProgress: Double {
        let angle = AtelierSettings.bendEffectFollowLid ? (sensorAngle ?? AtelierSettings.bendEffectClearAngle) : AtelierSettings.bendEffectManualAngle
        let target = BendMath.progress(angle: angle, clearAngle: AtelierSettings.bendEffectClearAngle)
        return target > 0.0005 ? target : 0
    }

    private var readyStatus: String { "Ready. Screen capture is off until the desktop bends." }

    private func settingsChanged() {
        let followLid = AtelierSettings.bendEffectFollowLid
        if followLid && sensorAngle == nil && (enabled || starting) {
            interrupt(message: "Waiting for the lid sensor… Turn off Follow lid to use a manual angle.")
        } else if starting && targetProgress == 0 {
            // Opening during SCStream startup must drain that attempt before another can begin.
            stopEffect(message: readyStatus, preserveIntent: true, keepReady: true)
        } else if enabled {
            if overlay != nil {
                startTicking()
            } else {
                sensor.setMode(followLid ? .watching : .idle)
                scheduleReconnect(immediate: true)
            }
        } else if wantsEnabled {
            scheduleReconnect(immediate: true)
        }
    }

    private enum ConnectionResult { case connected, retry, needsAttention }

    private static func requiresUserAction(_ error: Error) -> Bool {
        let error = error as NSError
        return error.domain == SCStreamErrorDomain
            && [
                SCStreamError.Code.userDeclined.rawValue,
                SCStreamError.Code.userStopped.rawValue,
                SCStreamError.Code.missingEntitlements.rawValue,
            ].contains(error.code)
    }

    /// One complete attempt, including asynchronous capture startup and cleanup.
    private func connect(generation request: Int) async -> ConnectionResult {
        let followLid = AtelierSettings.bendEffectFollowLid
        guard !followLid || sensorAngle != nil else {
            status = "Waiting for the lid sensor… Turn off Follow lid to use a manual angle."
            sensor.reconnect()
            return .retry
        }
        guard
            let screen = NSScreen.screens.first(where: {
                CGDisplayIsBuiltin(
                    ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
                        ?? 0
                ) != 0
            }),
            let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?
                .uint32Value
        else {
            status = "Connect the built-in display to use the desktop effect."
            return .retry
        }
        // Enabling arms the lid sensor. An open desktop must have no capture session:
        // even a hidden, low-frame-rate stream can blank protected video in other apps.
        guard targetProgress > 0 else {
            enabled = true
            starting = false
            sensor.setMode(followLid ? .watching : .idle)
            status = readyStatus
            return .connected
        }
        enabled = false
        starting = true
        sensor.setMode(followLid ? .active : .idle)
        status = "Connecting to your desktop…"
        var captureAttempted = false
        do {
            let renderer = try BendRenderer(frames: frames)
            renderer.parameters = { [weak self] in self?.parameters() ?? BendParameters() }
            let window = BendEffectOverlayWindow(screenFrame: screen.frame, renderer: renderer)
            self.renderer = renderer
            overlay = window
            // Register the hidden overlay before querying shareable content, including at login.
            captureAttempted = true
            try await capture.start(displayID: displayID)
            guard generation == request, !Task.isCancelled else { return .needsAttention }
            enabled = true
            starting = false
            progress = 0
            startTicking()
            status =
                followLid
                ? "Live desktop connected. Close the lid gently to bend it."
                : "Live desktop connected. Use the manual angle to bend it."
            return .connected
        } catch {
            guard generation == request, !Task.isCancelled else { return .needsAttention }
            await capture.stop()
            guard generation == request, !Task.isCancelled else { return .needsAttention }
            clearOverlay()
            starting = false
            if Self.requiresUserAction(error) {
                status =
                    "Allow the bend effect in System Settings → Privacy & Security → Screen & System Audio Recording, then try again."
                return .needsAttention
            }
            status = "Could not connect: \(error.localizedDescription)"
            // Hardware/Metal initialization errors need attention; capture can recover after login or wake.
            return captureAttempted ? .retry : .needsAttention
        }
    }
    private func interrupt(message: String) {
        guard wantsEnabled else { return }
        disable(message: message, preserveIntent: true)
    }
    private func scheduleReconnect(immediate: Bool = false) {
        guard reconnectTask == nil, wantsEnabled, !enabled || (overlay == nil && targetProgress > 0),
            !starting, !stopping, !sleeping, !needsUserAction
        else { return }
        generation += 1
        let request = generation
        reconnectTask = Task { [weak self] in
            defer {
                if self?.generation == request { self?.reconnectTask = nil }
            }
            // Await the actual result; a temporary capture failure consumes an attempt, not the whole loop.
            for attempt in 0..<15 {
                if attempt > 0 || !immediate {
                    do { try await Task.sleep(for: .seconds(1)) } catch { return }
                }
                guard let self, self.generation == request, self.wantsEnabled,
                    !self.sleeping, !Task.isCancelled
                else { return }
                switch await self.connect(generation: request) {
                case .connected: return
                case .needsAttention:
                    if self.generation == request { self.needsUserAction = true }
                    return
                case .retry: break
                }
            }
            if let self, self.generation == request {
                self.status += " Try connecting again."
            }
        }
    }
    private func clearOverlay() {
        overlay?.hide()
        overlay = nil
        renderer = nil
        if let hotKey {
            UnregisterEventHotKey(hotKey)
            self.hotKey = nil
        }
    }
    private func stopEffect(message: String, preserveIntent: Bool, keepReady: Bool) {
        if !preserveIntent { wantsEnabled = false }
        let pendingConnection = reconnectTask
        pendingConnection?.cancel()
        reconnectTask = nil
        generation += 1
        enabled = keepReady
        progress = 0
        wasFolded = false
        sensor.setMode(keepReady && AtelierSettings.bendEffectFollowLid ? .watching : .idle)
        clearOverlay()
        if !previewPlaying { stopTicking() }
        status = message
        guard !stopping else { return }
        stopping = true
        Task {
            await capture.stop()
            // A canceled start may still be inside ScreenCaptureKit. Drain it before opening another stream.
            await pendingConnection?.value
            stopping = false
            starting = false
            scheduleReconnect(immediate: enabled)
        }
    }
    private func stopTicking() {
        timer?.invalidate()
        timer = nil
    }
    /// Sensor/input changes restart smoothing; a settled effect needs no model timer.
    private func startTicking() {
        guard timer == nil else { return }
        lastTime = CACurrentMediaTime()
        let timer = Timer(timeInterval: 1 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    private func tick() {
        guard enabled || previewPlaying else {
            stopTicking()
            return
        }
        let now = CACurrentMediaTime()
        let dt = now - lastTime
        lastTime = now
        if previewPlaying {
            let clearAngle = AtelierSettings.bendEffectClearAngle
            let t = (now - playStart) / 4.2
            if t >= 1 {
                previewPlaying = false
                previewAngle = clearAngle
            } else {
                previewAngle = clearAngle - (clearAngle - 18) * pow(sin(t * .pi), 2)
            }
        }
        guard enabled, overlay != nil else {
            if !previewPlaying { stopTicking() }
            return
        }
        let target = targetProgress
        let hasFrame = frames.hasFrame
        // Capture startup can return before ScreenCaptureKit delivers its first frame.
        // Keep the undrawn overlay aligned with the real desktop instead of letting the
        // fold advance invisibly and then appearing partway through the animation.
        progress =
            !hasFrame
            ? 0
            : NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                ? target : BendMath.smooth(current: progress, target: target, dt: dt)
        let followLid = AtelierSettings.bendEffectFollowLid
        sensor.setMode(!followLid ? .idle : (target > 0 || progress > 0 ? .active : .watching))
        let visible = progress > 0.0005 && hasFrame
        if visible && overlay?.isVisible == false {
            overlay?.show()
            Task { await capture.setBending(true) }
            RegisterEventHotKey(
                UInt32(kVK_Escape), 0, EventHotKeyID(signature: 0x41544C42, id: 1),
                GetApplicationEventTarget(), 0, &hotKey)
        } else if !visible && overlay?.isVisible == true {
            overlay?.hide()
            Task { await capture.setBending(false) }
            if let hotKey {
                UnregisterEventHotKey(hotKey)
                self.hotKey = nil
            }
        }
        if !previewPlaying && progress == target { stopTicking() }
        if progress > 0.15 { wasFolded = true }
        if target == 0 && progress <= 0.0005 && wasFolded {
            wasFolded = false
            if AtelierSettings.bendEffectSound { NSSound(named: "Tink")?.play() }
        }
        if target == 0 && progress <= 0.0005 {
            // Hiding the overlay or lowering FPS is insufficient: release SCStream too.
            stopEffect(message: readyStatus, preserveIntent: true, keepReady: true)
        }
    }
}
```

- [ ] **Step 2: Build; fix any Swift 6 strict-concurrency diagnostics**

Run: `xcodebuild -scheme Atelier -configuration Debug build`
Expected: BUILD SUCCEEDED. The signature `0x41544C42` is `'ATLB'`, replacing BendMac's own `'BEND'` -- distinct from `GlobalHotkeys`'s existing `'ATLR'` signature so the two hotkey systems can never collide even though both use Carbon `RegisterEventHotKey`.

- [ ] **Step 3: Manually verify on-device**

With a real lid: enable the effect via a temporary debug call (or wait for Task 9's Settings pane), close the lid partway, confirm `status` messages advance through "Connecting…" to "Live desktop connected", and that closing further deepens the effect. This is manual-verification only, per Global Constraints.

- [ ] **Step 4: Commit**

```bash
git add Atelier/BendEffect/BendEffectController.swift
git commit -m "feat: add BendEffectController orchestrating the bend effect state machine"
```

---

## Task 8: BendEffectPane + PermissionsPane row + SettingsView registration

**Files:**
- Create: `Atelier/Settings/Panes/BendEffectPane.swift`
- Modify: `Atelier/Settings/SettingsView.swift`
- Modify: `Atelier/Settings/Panes/PermissionsPane.swift`

**Interfaces:**
- Consumes: `BendEffectController.shared` (Task 7), `AtelierSettings.bendEffect*` (Task 2), `ScreenRecordingPermission` (Task 2).

- [ ] **Step 1: Create `BendEffectPane.swift`**

```swift
import MetalKit
import SwiftUI

/// Adapted from IuCC123/BendMac's `SettingsView.swift` `MetalPreview` (MIT),
/// pointed at the controller's `previewFrames` box instead of the live one
/// so scrubbing the preview angle never touches the real desktop capture.
private struct BendEffectMetalPreview: NSViewRepresentable {
    @ObservedObject var controller: BendEffectController

    func makeCoordinator() -> Coordinator { Coordinator(controller: controller) }

    func makeNSView(context: Context) -> MTKView {
        let view = context.coordinator.renderer?.makeView() ?? MTKView()
        view.isPaused = true
        view.enableSetNeedsDisplay = true
        return view
    }

    func updateNSView(_ view: MTKView, context: Context) {
        view.setNeedsDisplay(view.bounds)
    }

    static func dismantleNSView(_ view: MTKView, coordinator: Coordinator) {
        view.isPaused = true
        view.delegate = nil
    }

    @MainActor final class Coordinator {
        let renderer: BendRenderer?
        init(controller: BendEffectController) {
            renderer = try? BendRenderer(frames: controller.previewFrames)
            renderer?.parameters = { [weak controller] in
                controller?.parameters(preview: true) ?? BendParameters()
            }
        }
    }
}

/// Settings/Appearance controls adapted from BendMac's own bespoke Settings
/// window into Atelier's grouped-`Form` pane convention (see
/// `AppearancePane`) -- same controls (enable, style/perspective/blur/
/// shadow, follow-lid vs. manual angle, calibrate, sound), different chrome.
struct BendEffectPane: View {
    @ObservedObject private var controller = BendEffectController.shared
    @AppStorage(AtelierSettings.bendEffectStyleKey) private var style = 0
    @AppStorage(AtelierSettings.bendEffectPerspectiveKey) private var perspective = 1.0
    @AppStorage(AtelierSettings.bendEffectBlurKey) private var blur = 0.9
    @AppStorage(AtelierSettings.bendEffectShadowKey) private var shadow = 0.35
    @AppStorage(AtelierSettings.bendEffectClearAngleKey) private var clearAngle = 105.0
    @AppStorage(AtelierSettings.bendEffectFollowLidKey) private var followLid = true
    @AppStorage(AtelierSettings.bendEffectManualAngleKey) private var manualAngle = 115.0
    @AppStorage(AtelierSettings.bendEffectSoundKey) private var sound = false

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(
                    get: { controller.wantsEnabled },
                    set: { $0 ? controller.enable() : controller.disable() }
                )) {
                    Text(controller.starting ? "Connecting…" : "Bend the desktop as the lid closes")
                }
                Text(controller.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } footer: {
                Text("Needs Screen Recording permission -- see the Permissions pane. Press Escape anytime to pause instantly. Open at login is in the General pane.")
            }

            Section("Preview") {
                BendEffectMetalPreview(controller: controller)
                    .aspectRatio(1.6, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .accessibilityLabel("Animated desktop fold preview")
                HStack {
                    Button {
                        if controller.previewPlaying {
                            controller.previewPlaying = false
                        } else {
                            controller.playPreview()
                        }
                    } label: {
                        Image(systemName: controller.previewPlaying ? "pause.fill" : "play.fill")
                    }
                    .help(controller.previewPlaying ? "Pause preview" : "Play fold preview")
                    .accessibilityLabel(controller.previewPlaying ? "Pause fold preview" : "Play fold preview")
                    Slider(value: $controller.previewAngle, in: 12...135, onEditingChanged: { _ in
                        controller.previewPlaying = false
                    })
                    .disabled(controller.previewFollowsLid)
                    .accessibilityLabel("Preview lid angle")
                    Text("\(Int(controller.displayedPreviewAngle))°")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 36, alignment: .trailing)
                }
                Toggle("Use live lid angle", isOn: $controller.previewFollowsLid)
                    .disabled(controller.sensorAngle == nil)
            }

            Section("Appearance") {
                Picker("Style", selection: $style) {
                    Text("Silk").tag(0)
                    Text("Shade").tag(1)
                    Text("Frost").tag(2)
                }
                .pickerStyle(.segmented)
                LabeledContent("Perspective") {
                    Slider(value: $perspective, in: 0...1) { Text("Perspective") }
                        .labelsHidden()
                        .frame(maxWidth: 200)
                }
                LabeledContent("Blur") {
                    Slider(value: $blur, in: 0...1) { Text("Blur") }
                        .labelsHidden()
                        .frame(maxWidth: 200)
                }
                LabeledContent("Shadow") {
                    Slider(value: $shadow, in: 0...1) { Text("Shadow") }
                        .labelsHidden()
                        .frame(maxWidth: 200)
                }
                Button("Reset appearance") { controller.resetAppearance() }
            }

            Section {
                LabeledContent("Lid sensor") {
                    Text(controller.sensorAngle.map { "\(Int($0))°" } ?? "Unavailable")
                        .foregroundStyle(.secondary)
                }
                Toggle("Follow physical lid", isOn: $followLid)
                if !followLid {
                    LabeledContent("Desktop angle") {
                        HStack {
                            Slider(value: $manualAngle, in: 12...135) { Text("Desktop angle") }
                                .labelsHidden()
                                .frame(maxWidth: 200)
                            Text("\(Int(manualAngle))°").monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                }
                LabeledContent("Clear at") {
                    HStack {
                        Slider(value: $clearAngle, in: 80...135) { Text("Clear at") }
                            .labelsHidden()
                            .frame(maxWidth: 200)
                        Text("\(Int(clearAngle))°").monospacedDigit().foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Text("Use your comfortable viewing position.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Use current angle") { controller.calibrateOpenAngle() }
                        .disabled(controller.sensorAngle == nil)
                        .help("Sets the clear angle to your current lid angle, between 80° and 135°.")
                }
                Toggle("Play a soft sound when unfolding finishes", isOn: $sound)
            } header: {
                Text("Lid Behavior")
            } footer: {
                Text("Lid sensor support varies by MacBook model and macOS version. You can always try the preview above.")
            }
        }
        .formStyle(.grouped)
        .onDisappear { controller.previewPlaying = false }
    }
}
```

- [ ] **Step 2: Register the pane in `SettingsView.swift`**

Add a case to `SettingsPane`:

```swift
    case bendEffect = "Bend Effect"
```

Add to `systemImage`:

```swift
        case .bendEffect: "macbook"
```

Add to the pane switch in `SettingsView.body`:

```swift
                case .bendEffect: BendEffectPane()
```

- [ ] **Step 3: Add the Permissions row**

In `PermissionsPane.swift`'s `PermissionSnapshot`, add a field and its `current()` computation:

```swift
    let screenRecording: PermissionState
```

```swift
            screenRecording: ScreenRecordingPermission.isGranted ? .granted : .denied,
```

In `PermissionsPane.body`'s `Section`, add a row (after the Accessibility row, since both are binary/System-Settings-only, no `grant` closure):

```swift
                PermissionRow(
                    title: "Screen Recording",
                    detail: "Renders the desktop bend effect",
                    state: snapshot.screenRecording,
                    openSettings: ScreenRecordingPermission.openSystemSettings
                )
```

Screen Recording is excluded from `needsAnything`/`grantAll()` for the same reason Accessibility already is (it can't be requested with a completion handler in-app) -- no change needed to those, since the new field simply isn't referenced there.

- [ ] **Step 4: Build**

Run: `xcodebuild -scheme Atelier -configuration Debug build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Manually verify in the running app**

Run `/build`, open Settings, confirm "Bend Effect" appears in the sidebar with a working preview player, sliders, and Lid Behavior section; confirm "Screen Recording" appears in the Permissions pane.

- [ ] **Step 6: Commit**

```bash
git add Atelier/Settings/Panes/BendEffectPane.swift Atelier/Settings/SettingsView.swift Atelier/Settings/Panes/PermissionsPane.swift
git commit -m "feat: add BendEffectPane and Screen Recording permissions row"
```

---

## Task 9: Wire into AtelierApp + docs sync

**Files:**
- Modify: `Atelier/AtelierApp.swift`
- Modify: `README.md`
- Modify: `docs/ROADMAP.md`

**Interfaces:**
- Consumes: `BendEffectController.shared` (Task 7).

- [ ] **Step 1: Instantiate the controller and add the menu toggle**

In `AtelierApp`, add a stored property alongside `notchController`:

```swift
    /// Held for the app's lifetime so the lid sensor starts polling at
    /// launch, the same eager-creation reasoning as `notchController`.
    private let bendEffectController: BendEffectController?

    @AppStorage(AtelierSettings.bendEffectEnabledKey) private var bendEffectEnabled = false
```

In `init()`, alongside `notchController`'s assignment:

```swift
        bendEffectController = Self.isRunningTests ? nil : .shared
```

In the `MenuBarExtra` body, add a toggle after the `Ghost Mode` toggle (before its `Divider()`), bound the same way Ghost Mode is:

```swift
            Toggle("Bend Effect", isOn: Binding(
                get: { bendEffectEnabled },
                set: { newValue in
                    newValue ? bendEffectController?.enable() : bendEffectController?.disable()
                }
            ))
```

- [ ] **Step 2: Build**

Run: `xcodebuild -scheme Atelier -configuration Debug build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Update README's permissions table**

In `README.md`, add a row after "System Audio Recording Only":

```markdown
| Screen & System Audio Recording | Renders the desktop bend effect as the lid closes. Only runs while actively bending; nothing is recorded or saved |
```

- [ ] **Step 4: Add a ROADMAP entry**

In `docs/ROADMAP.md`'s `## Upcoming` section, add:

```markdown
### ⬜ Phase 19 — Desktop bend effect (spec approved, not started)

Full port of [IuCC123/BendMac](https://github.com/IuCC123/BendMac) (MIT):
the desktop visibly bends and blurs as the lid closes. Whole-built-in-
display overlay, structurally separate from the notch -- see
`docs/superpowers/specs/2026-09-28-bend-effect-design.md` and
`docs/superpowers/plans/2026-09-28-bend-effect-implementation.md`.
Needs Screen & System Audio Recording permission (ScreenCaptureKit).
```

- [ ] **Step 5: Run the full test suite to confirm no regressions**

Run: `xcodebuild test -scheme Atelier -destination 'platform=macOS'`
Expected: all tests pass (existing count plus the 10 new `BendMathTests`).

- [ ] **Step 6: Commit**

```bash
git add Atelier/AtelierApp.swift README.md docs/ROADMAP.md
git commit -m "feat: wire BendEffectController into AtelierApp, sync docs"
```

---

## Task 10: Architecture decision record

**Files:**
- Create: `docs/decisions/0025-bend-effect-standalone-subsystem.md`

- [ ] **Step 1: Write the ADR**

Follow the existing ADR format (see `docs/decisions/0024-glass-mode-click-through-public-glasseffect-limitation.md` for structure: Status/Context/Decision/Consequences). Record: why `BendEffect/` is a standalone top-level folder rather than living under `Notch/` or `Widgets/` (it has nothing to do with the notch panel -- it's a whole-built-in-display overlay); why settings route through `AtelierSettings` instead of a private `UserDefaults` instance inside the controller (project-wide convention, unlike BendMac's own self-contained `AppModel`); why the Escape hotkey is registered directly in `BendEffectController` rather than through `GlobalHotkeys` (that class is scoped to Teleprompter's fixed three-action, modifier-based key set; a bare, unmodified Escape used only transiently while the overlay is visible doesn't fit its shape without distorting it); and the decision to add a menu-bar toggle (parity with the existing Ghost Mode toggle) rather than leaving this Settings-only.

- [ ] **Step 2: Commit**

```bash
git add docs/decisions/0025-bend-effect-standalone-subsystem.md
git commit -m "docs: record BendEffect architecture decisions"
```

---

## After all tasks

Run `/build` and manually verify on-device per the design spec's Testing section (HID sensor reads, `SCStream` capture, and Metal rendering all need real hardware). Consider running the `ui-review-tahoe` skill on `BendEffectPane.swift` per CLAUDE.md's UI/UX polish section, since it's a new SwiftUI view under a Settings pane touching sliders, toggles, and an animated preview.
