# Camera Mirror Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Camera tab in the expanded notch showing a live, mirrored self-view of the built-in camera, started by tap and stopped when the notch retracts (or optionally held open).

**Architecture:** New `NotchPage.camera` page. `CameraMirrorSource` (`@MainActor ObservableObject`) owns an `AVCaptureSession` driven from a private serial queue; `CameraPreviewView` (`NSViewRepresentable`) hosts an `AVCaptureVideoPreviewLayer`. Hold-open is a pure decision function called from `NotchRootView`'s hover handler; `NotchStateMachine` is not touched.

**Tech Stack:** Swift 6 (strict concurrency), SwiftUI + AppKit, AVFoundation, Swift Testing. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-09-24-camera-mirror-design.md`

## Global Constraints

- Swift 6 strict concurrency; deployment target macOS 26.0; no third-party dependencies.
- `NotchGeometry`/`NotchState`/`NotchPage` import only Foundation/CoreGraphics (Invariant 1).
- Panel is never resized per state (Invariant 3); non-interactive regions get `.allowsHitTesting(false)` (Invariant 4).
- Page horizontal inset is `NotchLayout.pageHorizontalInset` (26).
- Camera capture runs only while live: no polling, no timers, session stopped on tab change / collapse / app resign.
- Default preset `.medium`. State changes are fade-only (ADR 0014), no springs.
- Info.plist gets `NSCameraUsageDescription`; no entitlement (app is not sandboxed, hardened runtime off).
- The Xcode project uses file-system-synchronized groups: new files under `Atelier/` and `AtelierTests/` are picked up automatically, no pbxproj edit.
- Build: `xcodebuild -scheme Atelier -configuration Debug build`. Tests: `xcodebuild test -scheme Atelier -destination 'platform=macOS'`. Baseline: 139 tests pass.
- Commit trailer on every commit: `Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>`. Work on branch `feat/camera-mirror`; never commit to `main`; do not push without asking.

## Review Focus

- Camera unplugged / no camera (e.g. clamshell with external display): tab shows "No camera found", never crashes or hangs.
- Permission denied or restricted: tap shows the denied state with "Open Settings", never a silent no-op.
- Rapid tap on/off, or tap then immediate retract: session ends in a consistent stopped state (no orphaned running session, camera light off).
- Hold-open on, user swipes the notch closed or switches tab: mirror stops and the notch retracts (hold only suppresses hover-out).
- Setting `cameraEnabled` off while `currentPage == .camera`: tab disappears and page falls back to Home content.

---

### Task 1: Page plumbing, settings, and stages file

**Files:**
- Modify: `Atelier/Notch/NotchPage.swift` (add case)
- Modify: `Atelier/AtelierSettings.swift`
- Modify: `Atelier/UI/NotchTabBar.swift`
- Modify: `Atelier/AtelierApp.swift`
- Modify: `STAGES.md`
- Test: `AtelierTests/NotchPageTransitionTests.swift`

**Interfaces:**
- Produces: `NotchPage.camera`; `AtelierSettings.cameraEnabledKey`, `AtelierSettings.cameraHoldOpenKey`, `AtelierSettings.cameraEnabled: Bool`, `AtelierSettings.cameraHoldOpen: Bool`.

- [ ] **Step 1: Write the failing tests** — append to `NotchPageTransitionTests` (inside the struct):

```swift
    @Test func collapsedResetsToHomeEvenIfCameraWasSelected() {
        let result = NotchPageTransition.page(for: .collapsed, currentPage: .camera)

        #expect(result == .home)
    }

    @Test func expandedPreservesCameraPage() {
        let result = NotchPageTransition.page(for: .expanded, currentPage: .camera)

        #expect(result == .camera)
    }
```

- [ ] **Step 2: Run to verify it fails** — `xcodebuild test -scheme Atelier -destination 'platform=macOS' -only-testing:AtelierTests/NotchPageTransitionTests`. Expected: build FAIL, `type 'NotchPage' has no member 'camera'`.

- [ ] **Step 3: Implement**

`NotchPage.swift`: add `case camera` after `case calendar`.

`AtelierSettings.swift`: add keys and accessors, following the calendar pattern:

```swift
    static let cameraEnabledKey = "cameraEnabled"
    static let cameraHoldOpenKey = "cameraHoldOpen"
```
In `registerDefaults()` add `cameraEnabledKey: true,` (leave `cameraHoldOpenKey` unregistered; `bool(forKey:)` reads false). Add:

```swift
    static var cameraEnabled: Bool {
        UserDefaults.standard.bool(forKey: cameraEnabledKey)
    }

    static var cameraHoldOpen: Bool {
        UserDefaults.standard.bool(forKey: cameraHoldOpenKey)
    }
```

`NotchTabBar.swift`: in `activePages`, after the calendar block:

```swift
        if AtelierSettings.cameraEnabled {
            pages.append(.camera)
        }
```
and in `accessibilityName` add `case .camera: "Camera"`.

`AtelierApp.swift`: add `@AppStorage(AtelierSettings.cameraEnabledKey) private var cameraEnabled = true` and `@AppStorage(AtelierSettings.cameraHoldOpenKey) private var cameraHoldOpen = false` beside the other `@AppStorage` lines. In `Section("Widgets")`, after the Calendar block:

```swift
                    Toggle("Enable Camera Mirror", isOn: $cameraEnabled)
                    if cameraEnabled {
                        Toggle("Camera: keep notch open while mirror is on", isOn: $cameraHoldOpen)
                    }
```

`STAGES.md`: insert above the existing content a new section:

```markdown
# STAGES — Camera mirror (Phase 14)

Branch: `feat/camera-mirror`. Spec: `docs/superpowers/specs/2026-09-24-camera-mirror-design.md`.
Plan: `docs/superpowers/plans/2026-09-24-camera-mirror.md`.

- [ ] 1. Page plumbing — `NotchPage.camera`, tab dot, settings toggles
- [ ] 2. Hold-open decision (pure) + tests
- [ ] 3. Permission + capture source — `CameraPermission`, `CameraMirrorSource`, Info.plist key
- [ ] 4. Camera page UI + notch wiring (hold-open, stop on retract)
- [ ] 5. UI review pass (`ui-review-tahoe`) + on-device verification
- [ ] 6. Docs — ADR 0016, README, CLAUDE.md, FEATURES §2, ROADMAP Phase 14

---
```

- [ ] **Step 4: Build and run the full suite** — `xcodebuild test -scheme Atelier -destination 'platform=macOS'`. Expected: PASS (141 tests). The `.camera` tab shows a dot but falls through to `ExpandedPlayerView` until Task 4; that's expected.

- [ ] **Step 5: Commit**

```bash
git add Atelier STAGES.md AtelierTests
git commit -m "feat(camera): stage 1 - NotchPage.camera, settings, tab dot

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 2: Hold-open decision (pure)

**Files:**
- Create: `Atelier/Notch/CameraHoldOpen.swift`
- Test: `AtelierTests/CameraHoldOpenTests.swift`

**Interfaces:**
- Produces: `enum CameraHoldOpen { static func shouldSuppressRetract(holdOpenEnabled: Bool, mirrorLive: Bool, currentPage: NotchPage, state: NotchState) -> Bool }`. Foundation-only.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
@testable import Atelier

struct CameraHoldOpenTests {
    @Test func suppressesWhenEnabledLiveOnCameraPageAndExpanded() {
        #expect(CameraHoldOpen.shouldSuppressRetract(holdOpenEnabled: true, mirrorLive: true, currentPage: .camera, state: .expanded))
    }

    @Test func doesNotSuppressWhenSettingOff() {
        #expect(!CameraHoldOpen.shouldSuppressRetract(holdOpenEnabled: false, mirrorLive: true, currentPage: .camera, state: .expanded))
    }

    @Test func doesNotSuppressWhenMirrorNotLive() {
        #expect(!CameraHoldOpen.shouldSuppressRetract(holdOpenEnabled: true, mirrorLive: false, currentPage: .camera, state: .expanded))
    }

    @Test func doesNotSuppressOnOtherPages() {
        #expect(!CameraHoldOpen.shouldSuppressRetract(holdOpenEnabled: true, mirrorLive: true, currentPage: .home, state: .expanded))
    }

    @Test func doesNotSuppressOutsideExpanded() {
        #expect(!CameraHoldOpen.shouldSuppressRetract(holdOpenEnabled: true, mirrorLive: true, currentPage: .camera, state: .peeking))
    }
}
```

- [ ] **Step 2: Run to verify it fails** — `... -only-testing:AtelierTests/CameraHoldOpenTests`. Expected: FAIL, `cannot find 'CameraHoldOpen' in scope`.

- [ ] **Step 3: Implement**

```swift
import Foundation

/// Whether a hover-out should be ignored so the camera mirror stays up.
/// Pure and Foundation-only on purpose, like `NotchPageTransition`:
/// `NotchStateMachine` doesn't learn about the camera, and the decision
/// is testable without a camera. Only hover-out consults this; an
/// explicit swipe-close or tab change still closes/stops.
enum CameraHoldOpen {
    static func shouldSuppressRetract(
        holdOpenEnabled: Bool,
        mirrorLive: Bool,
        currentPage: NotchPage,
        state: NotchState
    ) -> Bool {
        holdOpenEnabled && mirrorLive && currentPage == .camera && state == .expanded
    }
}
```

- [ ] **Step 4: Run the tests** — expected PASS.

- [ ] **Step 5: Commit**

```bash
git add Atelier/Notch/CameraHoldOpen.swift AtelierTests/CameraHoldOpenTests.swift STAGES.md
git commit -m "feat(camera): stage 2 - pure hold-open decision + tests

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```
(Tick stages 1 and 2 in `STAGES.md` before committing.)

---

### Task 3: Permission + capture source (manual verification)

**Files:**
- Create: `Atelier/System/CameraPermission.swift`
- Create: `Atelier/Widgets/Camera/CameraMirrorSource.swift`
- Modify: `Atelier/Info.plist`

**Interfaces:**
- Produces:
  - `enum CameraPermission { static var status: AVAuthorizationStatus; static func requestAccess() async -> Bool; static func openSystemSettings() }`
  - `@MainActor final class CameraMirrorSource: ObservableObject` with:
    - `enum Phase: Equatable { case idle, starting, live, denied, noCamera }`
    - `@Published private(set) var phase: Phase`
    - `var isLive: Bool { phase == .live || phase == .starting }`
    - `var previewLayer: AVCaptureVideoPreviewLayer` (created once, lazily attached)
    - `func toggle()` (idle→start, live/starting→stop, denied→open Settings)
    - `func start()`, `func stop()`

- [ ] **Step 1: Info.plist** — add next to the other usage descriptions:

```xml
	<key>NSCameraUsageDescription</key>
	<string>Atelier shows a live mirror of your camera in the notch. The camera is only on while the mirror is showing, and nothing is recorded or saved.</string>
```

- [ ] **Step 2: `CameraPermission.swift`**

```swift
import AppKit
import AVFoundation

/// Camera TCC helper -- same thin shape as `CalendarPermission`: a live
/// status read (never cached) plus a deep link to the right pane.
enum CameraPermission {
    static var status: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .video)
    }

    static func requestAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }

    static func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") else { return }
        NSWorkspace.shared.open(url)
    }
}
```

- [ ] **Step 3: `CameraMirrorSource.swift`**

```swift
import AVFoundation
import Combine

/// Owns the camera capture session for the Camera tab. Battery/privacy
/// rule (see CLAUDE.md "Performance"): the session exists only between
/// `start()` and `stop()`; nothing polls. Adapted in spirit from
/// boring.notch's `WebcamManager` (auth states, device availability),
/// minus its singleton shape.
///
/// `AVCaptureSession.startRunning()` blocks, so the session is only
/// touched on `sessionQueue`; `phase` is only touched on the main actor.
@MainActor
final class CameraMirrorSource: ObservableObject {
    enum Phase: Equatable {
        case idle, starting, live, denied, noCamera
    }

    @Published private(set) var phase: Phase = .idle

    var isLive: Bool { phase == .live || phase == .starting }

    /// `AVCaptureSession` isn't `Sendable`; it's confined to `sessionQueue`
    /// by convention, hence the unchecked box.
    private final class SessionBox: @unchecked Sendable {
        let session = AVCaptureSession()
    }

    private let box = SessionBox()
    private let sessionQueue = DispatchQueue(label: "atelier.camera.session")
    /// Bumped on every start/stop so a slow `startRunning` that finishes
    /// after a `stop()` can tell it's stale and shut itself down.
    private var generation = 0

    /// One layer for the life of the source; the view just hosts it.
    let previewLayer: AVCaptureVideoPreviewLayer

    init() {
        previewLayer = AVCaptureVideoPreviewLayer(session: box.session)
        previewLayer.videoGravity = .resizeAspectFill
    }

    func toggle() {
        switch phase {
        case .idle, .noCamera: start()
        case .starting, .live: stop()
        case .denied: CameraPermission.openSystemSettings()
        }
    }

    func start() {
        guard phase == .idle || phase == .noCamera || phase == .denied else { return }
        generation += 1
        let myGeneration = generation
        phase = .starting

        Task { @MainActor in
            switch CameraPermission.status {
            case .authorized:
                break
            case .notDetermined:
                guard await CameraPermission.requestAccess() else {
                    if myGeneration == generation { phase = .denied }
                    return
                }
            default:
                if myGeneration == generation { phase = .denied }
                return
            }
            // The user may have tapped off / retracted during the prompt.
            guard myGeneration == generation else { return }

            let box = self.box
            let queue = sessionQueue
            let started: Bool = await withCheckedContinuation { continuation in
                queue.async {
                    continuation.resume(returning: Self.configureAndRun(box.session))
                }
            }
            guard myGeneration == generation else {
                // Stale: a stop() came in while we were starting.
                queue.async { box.session.stopRunning() }
                return
            }
            phase = started ? .live : .noCamera
        }
    }

    func stop() {
        generation += 1
        if phase != .denied { phase = .idle }
        let box = self.box
        sessionQueue.async {
            box.session.stopRunning()
        }
    }

    /// Runs on `sessionQueue`. Returns false if there's no usable camera.
    private nonisolated static func configureAndRun(_ session: AVCaptureSession) -> Bool {
        session.beginConfiguration()
        session.sessionPreset = .medium
        for input in session.inputs { session.removeInput(input) }
        guard
            let device = AVCaptureDevice.default(for: .video),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else {
            session.commitConfiguration()
            return false
        }
        session.addInput(input)
        session.commitConfiguration()
        session.startRunning()
        return session.isRunning
    }
}
```

Note for the implementer: mirroring is set in the view (Task 4) on the layer's connection once it exists (`connection?.automaticallyAdjustsVideoMirroring = false; connection?.isVideoMirrored = true`). If Swift 6 flags any isolation error above, fix it in the smallest way (e.g. `nonisolated(unsafe)`), don't restructure.

- [ ] **Step 4: Build** — `xcodebuild -scheme Atelier -configuration Debug build`. Expected: BUILD SUCCEEDED. Then run the full suite; expected 146 pass (139 + 2 + 5).

- [ ] **Step 5: Commit**

```bash
git add Atelier/System/CameraPermission.swift Atelier/Widgets/Camera Atelier/Info.plist STAGES.md
git commit -m "feat(camera): stage 3 - CameraPermission, CameraMirrorSource, Info.plist key

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```
(Tick stage 3.) Manual-verification only; nothing here is unit-testable without a camera. Say so in the summary.

---

### Task 4: Camera page UI + notch wiring

**Files:**
- Create: `Atelier/UI/CameraMirrorPageView.swift`
- Modify: `Atelier/UI/NotchRootView.swift` (owned source, page branch, hover, stop-on-leave)

**Interfaces:**
- Consumes: `CameraMirrorSource` (Task 3), `CameraHoldOpen.shouldSuppressRetract` (Task 2), `AtelierSettings.cameraEnabled/cameraHoldOpen` (Task 1).
- Produces: `struct CameraMirrorPageView: View { @ObservedObject var source: CameraMirrorSource }`.

- [ ] **Step 1: `CameraMirrorPageView.swift`**

```swift
import AppKit
import AVFoundation
import SwiftUI

/// The Camera tab. One fixed frame for every state so nothing jumps
/// (spec: "keep it clean"). The live state is video only; tap to stop.
struct CameraMirrorPageView: View {
    @ObservedObject var source: CameraMirrorSource

    private static let cornerRadius: CGFloat = 16

    var body: some View {
        Button {
            source.toggle()
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.06))

                CameraPreviewView(layer: source.previewLayer)
                    .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
                    .opacity(source.phase == .live ? 1 : 0)
                    .allowsHitTesting(false)

                if source.phase != .live {
                    placeholder
                        .transition(.opacity)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(CameraPressStyle())
        .focusEffectDisabled()
        .padding(.horizontal, NotchLayout.pageHorizontalInset)
        .padding(.bottom, 12)
        .animation(.easeInOut(duration: 0.2), value: source.phase)
        .accessibilityLabel(source.isLive ? "Camera mirror, on" : "Camera mirror, off")
        .accessibilityHint(source.phase == .denied ? "Opens System Settings" : "Toggles the camera mirror")
        .onDisappear { source.stop() }
    }

    @ViewBuilder
    private var placeholder: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .regular))
            Text(caption)
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(.white.opacity(0.5))
        .allowsHitTesting(false)
    }

    private var symbol: String {
        switch source.phase {
        case .denied: "exclamationmark.triangle"
        case .noCamera: "video.slash"
        default: "web.camera"
        }
    }

    private var caption: String {
        switch source.phase {
        case .idle: "Tap to mirror"
        case .starting: "Starting…"
        case .denied: "Camera access is off — tap to open Settings"
        case .noCamera: "No camera found"
        case .live: ""
        }
    }
}

/// Subtle press feedback (polish rule): a slight dim, no bounce.
private struct CameraPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

/// Hosts the source's single `AVCaptureVideoPreviewLayer`, mirrored.
private struct CameraPreviewView: NSViewRepresentable {
    let layer: AVCaptureVideoPreviewLayer

    /// Resizes the hosted layer whenever AppKit lays the view out, so the
    /// preview tracks the page's frame without manual bookkeeping.
    private final class HostView: NSView {
        var previewLayer: AVCaptureVideoPreviewLayer?

        override func layout() {
            super.layout()
            previewLayer?.frame = bounds
        }
    }

    func makeNSView(context: Context) -> NSView {
        let view = HostView()
        view.wantsLayer = true
        view.previewLayer = layer
        view.layer?.addSublayer(layer)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        // The connection only exists once the session has an input, so
        // (re)apply mirroring on every update rather than once in make.
        if let connection = layer.connection {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
    }
}
```

`CameraMirrorPageView` passes `source.previewLayer`. Add `import AVFoundation` to the top of this file alongside `AppKit`/`SwiftUI`.

- [ ] **Step 2: Wire into `NotchRootView.swift`**
  1. Add `@StateObject private var camera = CameraMirrorSource()` beside `@StateObject private var artworkColor`.
  2. In the page `if/else if` chain (around the `CalendarPageView(source: calendar)` branch) add before the final `else`:

```swift
                        } else if AtelierSettings.cameraEnabled, viewModel.currentPage == .camera {
                            CameraMirrorPageView(source: camera)
```
  3. `frameSize` needs no change: Camera uses `viewModel.currentSize` (the standard expanded footprint).
  4. In `.onHover`, in the `else` (hover-out) branch, add a guard as the first statement:

```swift
                    if CameraHoldOpen.shouldSuppressRetract(
                        holdOpenEnabled: AtelierSettings.cameraHoldOpen,
                        mirrorLive: camera.isLive,
                        currentPage: viewModel.currentPage,
                        state: viewModel.state
                    ) { return }
```
  (Only hover-out; the gesture `onClose` and tab taps are unchanged.)
  5. Stop the camera whenever the notch leaves `.expanded` or the page changes, and when the app resigns. After the `.onHover` modifier add:

```swift
            .onChange(of: viewModel.state) { _, newState in
                if newState != .expanded { camera.stop() }
            }
            .onChange(of: viewModel.currentPage) { _, page in
                if page != .camera { camera.stop() }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
                camera.stop()
            }
```
  6. Deferred retract when hold-open ends while the pointer is outside. Add `@State private var pointerInside = false`, set it in `.onHover` (`pointerInside = hovering` as the first line), and add:

```swift
            .onChange(of: camera.isLive) { _, live in
                guard !live, !pointerInside, viewModel.state == .expanded else { return }
                withAnimation(NotchAnimations.close) {
                    viewModel.handle(.hoverEnded(isPlaying: liveActivity.hasContent))
                }
            }
```
  7. If `cameraEnabled` is turned off while on the camera page, `viewModel.currentPage` stays `.camera` but the chain falls through to `ExpandedPlayerView` (same as the other pages today); also call `camera.stop()` via the `onChange(of: viewModel.currentPage)`; verify on-device that nothing is stranded.

- [ ] **Step 3: Build and run the full suite** — expected BUILD SUCCEEDED and 146 tests pass.

- [ ] **Step 4: Manual on-device check (Alicia)** — `/build`, then: open notch, swipe to Camera tab, confirm placeholder and that the camera light is OFF; tap → permission prompt → live mirrored video; retract → light off; tap while live → stops; deny in System Settings → denied state → tap opens Settings; hold-open setting on → mirror stays open on hover-out and retracts when stopped.

- [ ] **Step 5: Commit**

```bash
git add Atelier STAGES.md
git commit -m "feat(camera): stage 4 - camera page UI, hold-open wiring, stop on retract

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```
(Tick stage 4.)

---

### Task 5: UI review pass

**Files:** as findings dictate (`Atelier/UI/CameraMirrorPageView.swift`).

- [ ] **Step 1:** Run the `ui-review-tahoe` skill on `CameraMirrorPageView.swift` and the tab-bar change. Collect all findings in one batch.
- [ ] **Step 2:** Apply accessibility/press/depth fixes that don't change the agreed look; list anything that would (e.g. adding chrome) for Alicia instead of applying.
- [ ] **Step 3:** Preview height check on-device: the preview area is the page content height minus the tab bar; if 16:9 video crops too aggressively, adjust `.padding(.bottom)` only, not the panel size (Invariant 3).
- [ ] **Step 4:** Build + full suite. Commit `feat(camera): stage 5 - UI review fixes` (tick stage 5).

---

### Task 6: Docs and phase completion

**Files:**
- Create: `docs/decisions/0016-camera-mirror-preview-layer-tap-to-start.md`
- Modify: `README.md`, `CLAUDE.md`, `docs/FEATURES.md`, `docs/ROADMAP.md`, `STAGES.md`

- [ ] **Step 1: ADR 0016** — record: preview-layer over data-output (why), tap-to-start (privacy/light), hold-open as opt-in setting with hover-out-only suppression and the pure `CameraHoldOpen` (why the state machine is untouched), no entitlement needed (unsandboxed). Follow the format of `docs/decisions/0015-weather-open-meteo-corelocation.md`.
- [ ] **Step 2:** README: Camera permission (Privacy → Camera), what the tab does, the two settings. CLAUDE.md: add `Widgets/Camera/CameraMirrorSource`, `System/CameraPermission` to the architecture table (manual-verification only) and `Notch/CameraHoldOpen` to the pure/tested list. FEATURES §2: mark Camera mirror shipped. ROADMAP: Phase 14 ✅ and update the "Where we are" line.
- [ ] **Step 3:** Run the `phase-completion-checklist` skill; fix what it flags.
- [ ] **Step 4:** Full suite green; tick stage 6 in `STAGES.md`; commit `docs(camera): stage 6 - ADR 0016, README, CLAUDE.md, FEATURES, ROADMAP`.
- [ ] **Step 5:** Ask Alicia before pushing or opening the PR (`pre-push-docs-sync` runs first, then `/pr`).
