# Lock-Screen Now-Playing Widget Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show Atelier's now-playing info (artwork, title/artist, real scrubber, transport) as an Atelier-styled card on the lock screen, collapsed by default with parallax artwork, expanding on hover to a full scrubber + transport view.

**Architecture:** A vendored, hardened private-API wrapper (`SkyLightSpaceOperator`) delegates a standalone `NSWindow` into the exact CGS space level Notification Center uses to draw over the lock screen. A `LockScreenManager` detects lock/unlock via `DistributedNotificationCenter`. A `LockScreenPanelController` combines both signals with the existing `NowPlayingCoordinator` (no new data source) to show/hide/position the window. The window's SwiftUI content directly observes `NowPlayingCoordinator`, so it stays live without any manual re-render plumbing.

**Tech Stack:** Swift 6, AppKit, SwiftUI, Combine, `os.Logger`. One vendored private-API file (not a SwiftPM dependency).

**Spec:** `docs/superpowers/specs/2026-09-19-lockscreen-nowplaying-widget-design.md`

## Global Constraints

- Swift 6, strict concurrency; `@MainActor` on every new type (all AppKit/UI-facing, matching the project's `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` setting).
- No third-party dependencies — `SkyLightSpaceOperator` is vendored with credit, not added via SwiftPM.
- `SkyLightSpaceOperator`'s private-symbol resolution must never crash: every `dlsym` result is checked, and `isAvailable == false` on any failure disables the feature entirely rather than crashing.
- No new `NowPlayingSource`/poller — reuse the existing `NowPlayingCoordinator` instance already owned by `NotchController`.
- This feature is entirely separate from `NotchState`/`NotchStateMachine` — no changes to either.
- Manual verification only (private API, real screen-lock state, a real AppKit window) — say so plainly in `docs/ROADMAP.md`, no unit tests claimed for this feature.

---

### Task 1: `SkyLightSpaceOperator`

**Files:**
- Create: `Atelier/System/SkyLightSpaceOperator.swift`

**Interfaces:**
- Produces: `SkyLightSpaceOperator.shared: SkyLightSpaceOperator`, `.isAvailable: Bool`, `.delegateWindow(_ window: NSWindow)`, used by Task 5.

- [ ] **Step 1: Write the file**

```swift
import AppKit
import os

/// Delegates a window into a private CGS "space" at the exact level
/// Notification Center uses to draw over the lock screen, letting it
/// render above the lock/login screen shield -- a private, undocumented
/// mechanism with no Apple guarantee across OS versions.
///
/// Adapted from Lakr233/SkyLightWindow's `SkyLightOperator` (read via
/// `gh api` per check-reference-apps-first) -- vendored rather than added
/// as a SwiftPM dependency (see the design spec), and hardened against a
/// real crash risk in the original: it force-unwraps every `dlsym`
/// result, so a renamed/removed private symbol on some future macOS
/// crashes at first use. This version checks every symbol and exposes
/// `isAvailable`, so a broken symbol silently disables the feature
/// instead of crashing the app.
@MainActor
final class SkyLightSpaceOperator {
    static let shared = SkyLightSpaceOperator()

    private static let log = Logger(subsystem: "com.atelier.app", category: "SkyLightSpaceOperator")

    /// The level Notification Center itself uses to draw over the lock
    /// screen -- see Lakr233/SkyLightWindow's own `SKL_CGSSpaceLevel`
    /// (`kSLSSpaceAbsoluteLevelNotificationCenterAtScreenLock`).
    private static let screenLockNotificationLevel: Int32 = 400

    private typealias F_SLSSpaceAddWindowsAndRemoveFromSpaces = @convention(c) (Int32, Int32, CFArray, Int32) -> Int32

    private let connection: Int32
    private let space: Int32
    private let addWindows: F_SLSSpaceAddWindowsAndRemoveFromSpaces

    /// `false` if any private symbol failed to resolve. `delegateWindow`
    /// is a no-op when this is `false`; `LockScreenPanelController` also
    /// checks it directly before ever attempting to show its window.
    private(set) var isAvailable: Bool

    private init() {
        typealias F_SLSMainConnectionID = @convention(c) () -> Int32
        typealias F_SLSSpaceCreate = @convention(c) (Int32, Int32, Int32) -> Int32
        typealias F_SLSSpaceSetAbsoluteLevel = @convention(c) (Int32, Int32, Int32) -> Int32
        typealias F_SLSShowSpaces = @convention(c) (Int32, CFArray) -> Int32

        guard
            let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight", RTLD_NOW),
            let mainConnectionIDSym = dlsym(handle, "SLSMainConnectionID"),
            let spaceCreateSym = dlsym(handle, "SLSSpaceCreate"),
            let setAbsoluteLevelSym = dlsym(handle, "SLSSpaceSetAbsoluteLevel"),
            let showSpacesSym = dlsym(handle, "SLSShowSpaces"),
            let addWindowsSym = dlsym(handle, "SLSSpaceAddWindowsAndRemoveFromSpaces")
        else {
            Self.log.error("SkyLight private symbol resolution failed -- lock-screen widget disabled")
            connection = 0
            space = 0
            addWindows = { _, _, _, _ in 0 }
            isAvailable = false
            return
        }

        let mainConnectionID = unsafeBitCast(mainConnectionIDSym, to: F_SLSMainConnectionID.self)
        let spaceCreate = unsafeBitCast(spaceCreateSym, to: F_SLSSpaceCreate.self)
        let setAbsoluteLevel = unsafeBitCast(setAbsoluteLevelSym, to: F_SLSSpaceSetAbsoluteLevel.self)
        let showSpaces = unsafeBitCast(showSpacesSym, to: F_SLSShowSpaces.self)

        let resolvedConnection = mainConnectionID()
        let resolvedSpace = spaceCreate(resolvedConnection, 1, 0)
        connection = resolvedConnection
        space = resolvedSpace
        addWindows = unsafeBitCast(addWindowsSym, to: F_SLSSpaceAddWindowsAndRemoveFromSpaces.self)

        _ = setAbsoluteLevel(resolvedConnection, resolvedSpace, Self.screenLockNotificationLevel)
        _ = showSpaces(resolvedConnection, [resolvedSpace] as CFArray)
        isAvailable = true
    }

    /// Moves `window` into the private lock-screen-level space. No-op if
    /// `isAvailable` is `false`.
    func delegateWindow(_ window: NSWindow) {
        guard isAvailable else { return }
        _ = addWindows(connection, space, [window.windowNumber] as CFArray, 7)
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `xcodebuild -scheme Atelier -configuration Debug build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add Atelier/System/SkyLightSpaceOperator.swift
git commit -m "feat: add SkyLightSpaceOperator, vendored and hardened against dlsym crash"
```

---

### Task 2: `LockScreenManager`

**Files:**
- Create: `Atelier/LockScreen/LockScreenManager.swift`

**Interfaces:**
- Produces: `LockScreenManager` (an `ObservableObject`), `.isLocked: Bool` (published), used by Task 5.

- [ ] **Step 1: Write the file**

```swift
import Foundation

/// Detects the screen lock/unlock transition via the same
/// `DistributedNotificationCenter` notification names every other
/// lock-screen-aware macOS app relies on. These are undocumented
/// notification *names*, but a long-standing, widely-used mechanism --
/// much lower risk than `SkyLightSpaceOperator`'s private-framework
/// symbol calls, which is why the two live in separate files.
@MainActor
final class LockScreenManager: ObservableObject {
    @Published private(set) var isLocked = false

    private var lockObserver: NSObjectProtocol?
    private var unlockObserver: NSObjectProtocol?

    init() {
        let center = DistributedNotificationCenter.default()
        lockObserver = center.addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.isLocked = true
        }
        unlockObserver = center.addObserver(
            forName: Notification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.isLocked = false
        }
    }

    deinit {
        let center = DistributedNotificationCenter.default()
        if let lockObserver { center.removeObserver(lockObserver) }
        if let unlockObserver { center.removeObserver(unlockObserver) }
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `xcodebuild -scheme Atelier -configuration Debug build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add Atelier/LockScreen/LockScreenManager.swift
git commit -m "feat: add LockScreenManager for lock/unlock detection"
```

---

### Task 3: `Parallax3DModifier`

**Files:**
- Create: `Atelier/UI/Parallax3DModifier.swift`

**Interfaces:**
- Produces: `View.parallax3D()`, used by Task 4.

- [ ] **Step 1: Write the file**

```swift
import SwiftUI

/// Subtle hover-driven 3D tilt + scale, applied to the lock-screen card's
/// collapsed artwork. Adapted from Ebullioscopic/Atoll's
/// `View+Parallax3D.swift` (read via `gh api` per
/// check-reference-apps-first) -- simplified to a fixed intensity instead
/// of a user-configurable setting (this app has no settings surface for
/// this kind of thing, per the design spec's YAGNI note).
private struct Parallax3DModifier: ViewModifier {
    private static let intensity: Double = 6

    @State private var offset: CGSize = .zero
    @State private var isHovering = false
    @State private var viewSize: CGSize = .zero

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .overlay(
                GeometryReader { proxy in
                    Color.clear
                        .allowsHitTesting(false)
                        .onAppear { viewSize = proxy.size }
                        .onChange(of: proxy.size) { _, newSize in viewSize = newSize }
                }
            )
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    guard viewSize.width > 0, viewSize.height > 0 else { return }
                    let x = (location.x / viewSize.width) * 2 - 1
                    let y = (location.y / viewSize.height) * 2 - 1
                    withAnimation(.interactiveSpring(response: 0.1, dampingFraction: 0.5)) {
                        offset = CGSize(width: x, height: y)
                        isHovering = true
                    }
                case .ended:
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
                        offset = .zero
                        isHovering = false
                    }
                }
            }
            .rotation3DEffect(.degrees(offset.height * Self.intensity), axis: (x: 1, y: 0, z: 0))
            .rotation3DEffect(.degrees(offset.width * -Self.intensity), axis: (x: 0, y: 1, z: 0))
            .scaleEffect(isHovering ? 1.04 : 1.0)
    }
}

extension View {
    func parallax3D() -> some View {
        modifier(Parallax3DModifier())
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `xcodebuild -scheme Atelier -configuration Debug build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add Atelier/UI/Parallax3DModifier.swift
git commit -m "feat: add Parallax3DModifier for lock-screen card artwork"
```

---

### Task 4: `LockScreenMusicCardView`, reusing `ScrubberView`

**Files:**
- Create: `Atelier/UI/LockScreenMusicCardView.swift`
- Modify: `Atelier/UI/ExpandedPlayerView.swift`

**Interfaces:**
- Consumes: `NowPlayingCoordinator` (existing), `ArtworkView` (existing, already internal), `ScrubberView` (made internal by this task), `View.parallax3D()` from Task 3.
- Produces: `LockScreenMusicCardView(nowPlaying:onPlayPause:onNext:onPrevious:onSeek:)`, `.collapsedSize`, `.expandedSize` (static), used by Task 5.

- [ ] **Step 1: Drop `private` from `ScrubberView`**

In `Atelier/UI/ExpandedPlayerView.swift`, find:

```swift
private struct ScrubberView: View {
```

Change to:

```swift
struct ScrubberView: View {
```

(No other change to this struct — same file, same behavior for `ExpandedPlayerView`'s own use of it.)

- [ ] **Step 2: Write `LockScreenMusicCardView`**

```swift
import SwiftUI

/// Atelier's own now-playing card for the lock screen (see the design
/// spec) -- collapsed by default (artwork + title/artist, with parallax),
/// expands on hover to a larger view with a real scrubber and transport
/// controls. Local `@State`, not `NotchStateMachine` -- this window is
/// entirely separate from the notch. Observes `NowPlayingCoordinator`
/// directly (not a snapshot `NowPlayingInfo`) so the card stays live for
/// as long as the window exists, the same way any other SwiftUI subtree
/// reacts to a `@Published` change.
struct LockScreenMusicCardView: View {
    @ObservedObject var nowPlaying: NowPlayingCoordinator
    let onPlayPause: () -> Void
    let onNext: () -> Void
    let onPrevious: () -> Void
    let onSeek: (TimeInterval) -> Void

    @State private var isExpanded = false

    static let collapsedSize = CGSize(width: 280, height: 72)
    static let expandedSize = CGSize(width: 340, height: 200)

    var body: some View {
        Group {
            if let info = nowPlaying.current {
                content(for: info)
            } else {
                Color.clear
            }
        }
        .frame(width: Self.expandedSize.width, height: Self.expandedSize.height, alignment: .bottom)
        .onHover { hovering in
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                isExpanded = hovering
            }
        }
    }

    @ViewBuilder
    private func content(for info: NowPlayingInfo) -> some View {
        Group {
            if isExpanded {
                expandedContent(for: info)
                    .frame(width: Self.expandedSize.width, height: Self.expandedSize.height)
            } else {
                collapsedContent(for: info)
                    .frame(width: Self.collapsedSize.width, height: Self.collapsedSize.height)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.black.opacity(0.55))
        )
    }

    private func collapsedContent(for info: NowPlayingInfo) -> some View {
        HStack(spacing: 12) {
            ArtworkView(url: info.artworkURL, cornerRadius: 12)
                .frame(width: 40, height: 40)
                .parallax3D()
            VStack(alignment: .leading, spacing: 2) {
                Text(info.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(info.artist)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    private func expandedContent(for info: NowPlayingInfo) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                ArtworkView(url: info.artworkURL, cornerRadius: 12)
                    .frame(width: 64, height: 64)
                    .parallax3D()
                VStack(alignment: .leading, spacing: 4) {
                    Text(info.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(info.artist)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            ScrubberView(duration: info.duration, elapsed: info.elapsed, onSeek: onSeek)
            HStack(spacing: 28) {
                Button(action: onPrevious) {
                    Image(systemName: "backward.fill")
                }
                Button(action: onPlayPause) {
                    Image(systemName: info.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 20))
                }
                Button(action: onNext) {
                    Image(systemName: "forward.fill")
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
        }
    }
}
```

- [ ] **Step 3: Build to verify it compiles**

Run: `xcodebuild -scheme Atelier -configuration Debug build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Run the full unit suite to confirm no regression**

Run: `xcodebuild test -scheme Atelier -destination 'platform=macOS'`
Expected: `** TEST SUCCEEDED **`, same 114 tests as before (dropping `private` from `ScrubberView` changes no behavior).

- [ ] **Step 5: Commit**

```bash
git add Atelier/UI/LockScreenMusicCardView.swift Atelier/UI/ExpandedPlayerView.swift
git commit -m "feat: add LockScreenMusicCardView, reusing ScrubberView"
```

---

### Task 5: `LockScreenPanelController`

**Files:**
- Create: `Atelier/LockScreen/LockScreenPanelController.swift`

**Interfaces:**
- Consumes: `SkyLightSpaceOperator.shared` (Task 1), `LockScreenManager` (Task 2), `LockScreenMusicCardView` (Task 4), existing `NowPlayingCoordinator`.
- Produces: `LockScreenPanelController(nowPlayingCoordinator:lockScreenManager:)`, used by Task 6.

- [ ] **Step 1: Write the file**

```swift
import AppKit
import Combine
import SwiftUI

/// Owns the lock-screen now-playing card's window -- entirely separate
/// from `NotchPanel` (different lifecycle, level, and screen position).
/// See the design spec for why an ordinary window level isn't enough:
/// macOS hides ordinary user-session windows the moment the screen locks,
/// so this delegates into a private CGS space via `SkyLightSpaceOperator`
/// instead.
@MainActor
final class LockScreenPanelController {
    private let nowPlayingCoordinator: NowPlayingCoordinator
    private var window: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    init(nowPlayingCoordinator: NowPlayingCoordinator, lockScreenManager: LockScreenManager) {
        self.nowPlayingCoordinator = nowPlayingCoordinator

        Publishers.CombineLatest(lockScreenManager.$isLocked, nowPlayingCoordinator.$current)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isLocked, current in
                self?.updateVisibility(isLocked: isLocked, info: current)
            }
            .store(in: &cancellables)
    }

    private func updateVisibility(isLocked: Bool, info: NowPlayingInfo?) {
        guard SkyLightSpaceOperator.shared.isAvailable, isLocked, info != nil else {
            window?.orderOut(nil)
            return
        }
        showWindow()
    }

    private func showWindow() {
        let window = window ?? makeWindow()
        self.window = window
        positionWindow(window)
        window.orderFrontRegardless()
    }

    private func makeWindow() -> NSWindow {
        let newWindow = NSWindow(
            contentRect: NSRect(origin: .zero, size: LockScreenMusicCardView.expandedSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        newWindow.isReleasedWhenClosed = false
        newWindow.isOpaque = false
        newWindow.backgroundColor = .clear
        newWindow.hasShadow = false
        newWindow.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        newWindow.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        newWindow.isMovable = false

        let hosting = NSHostingView(rootView: LockScreenMusicCardView(
            nowPlaying: nowPlayingCoordinator,
            onPlayPause: { [weak self] in Task { await self?.nowPlayingCoordinator.playPause() } },
            onNext: { [weak self] in Task { await self?.nowPlayingCoordinator.next() } },
            onPrevious: { [weak self] in Task { await self?.nowPlayingCoordinator.previous() } },
            onSeek: { [weak self] time in Task { await self?.nowPlayingCoordinator.seek(to: time) } }
        ))
        newWindow.contentView = hosting

        SkyLightSpaceOperator.shared.delegateWindow(newWindow)
        return newWindow
    }

    /// Bottom-center of the screen, clear of the password/Touch ID entry
    /// area (which sits center-screen). 60pt up from the bottom edge --
    /// a starting value, expected to be tuned on-device.
    private func positionWindow(_ window: NSWindow) {
        guard let screen = NSScreen.notchedOrMain else { return }
        let size = LockScreenMusicCardView.expandedSize
        let origin = CGPoint(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.minY + 60
        )
        window.setFrame(CGRect(origin: origin, size: size), display: true)
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `xcodebuild -scheme Atelier -configuration Debug build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add Atelier/LockScreen/LockScreenPanelController.swift
git commit -m "feat: add LockScreenPanelController"
```

---

### Task 6: Final wiring — `NotchController`

**Files:**
- Modify: `Atelier/Notch/NotchController.swift`

**Interfaces:**
- Consumes: `LockScreenManager` (Task 2), `LockScreenPanelController` (Task 5), existing `nowPlayingCoordinator`.

- [ ] **Step 1: Add stored properties**

In `Atelier/Notch/NotchController.swift`, add two new stored properties next to the existing ones (near `private let batterySource: BatterySource`):

```swift
private let lockScreenManager: LockScreenManager
private let lockScreenPanelController: LockScreenPanelController
```

- [ ] **Step 2: Construct them in the no-notch-screen fallback path**

In the fallback path (the `guard let screen = NSScreen.notchedOrMain else { ... }` block), after `self.batterySource = batterySource` and before `mediaKeyInterceptor = ...`, add:

```swift
let lockScreenManager = LockScreenManager()
self.lockScreenManager = lockScreenManager
self.lockScreenPanelController = LockScreenPanelController(
    nowPlayingCoordinator: nowPlayingCoordinator,
    lockScreenManager: lockScreenManager
)
```

- [ ] **Step 3: Construct them in the real (notched-screen) path**

In the real path, in the same relative spot (after `self.batterySource = batterySource`, before `mediaKeyInterceptor = ...`), add the identical four lines as Step 2.

- [ ] **Step 4: Build to verify it compiles**

Run: `xcodebuild -scheme Atelier -configuration Debug build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Run the full unit suite**

Run: `xcodebuild test -scheme Atelier -destination 'platform=macOS'`
Expected: `** TEST SUCCEEDED **`, 114 tests (no new pure logic in this feature, so no new tests).

- [ ] **Step 6: Commit**

```bash
git add Atelier/Notch/NotchController.swift
git commit -m "feat: wire LockScreenManager and LockScreenPanelController into NotchController"
```

- [ ] **Step 7: Build and relaunch for manual verification**

Use the `build` skill: kill any running `Atelier`, build, relaunch.

Manually verify on-device (check these off only once actually exercised, per `CLAUDE.md`'s Testing section):
- [ ] Lock the screen while music is playing → the card appears bottom-center.
- [ ] Hover over the card → expands to show artwork/scrubber/transport; scrubbing actually seeks; play/pause and skip actually work.
- [ ] Mouse away → collapses back down.
- [ ] Unlock → the card disappears.
- [ ] Lock the screen with nothing playing → no card appears at all.
- [ ] Lock/unlock repeatedly several times → no duplicate windows, no crash, no leftover window after unlock.
- [ ] Confirm the card doesn't overlap the password/Touch ID entry area.
- [ ] Update `docs/ROADMAP.md` with the result of manual verification (or any bug found), same discipline as the file shelf's and tabbed-nav's own entries.

---

## Self-Review Notes

- **Spec coverage:** lock/unlock detection (Task 2), rendering/private API (Task 1), content with parallax + reused scrubber (Tasks 3-4), visibility/positioning logic (Task 5), final integration (Task 6) — all spec sections have a task. The spec's "out of scope" items (weather/timer/other widgets, output-device picking, settings surface, NotchState changes) have no task, correctly.
- **Type consistency:** `SkyLightSpaceOperator.shared`/`.isAvailable`/`.delegateWindow(_:)` (Task 1) match their use in `LockScreenPanelController` (Task 5). `LockScreenManager.isLocked` (Task 2) matches its use in Task 5's `Publishers.CombineLatest`. `LockScreenMusicCardView`'s exact init signature (Task 4) matches its construction in Task 5. `ScrubberView`'s dropped `private` (Task 4) matches its reuse in the same task's `LockScreenMusicCardView`.
- **A real bug caught during planning, fixed before it shipped:** an earlier draft of `LockScreenMusicCardView` took a snapshot `info: NowPlayingInfo` parameter instead of observing `NowPlayingCoordinator` directly — since `NSHostingView.rootView` is set once at window creation, that would have frozen the card's content at whatever was playing the moment the window was first created, never updating again on track changes or scrubber position. Fixed by having the view hold `@ObservedObject var nowPlaying: NowPlayingCoordinator` instead, so it stays live the same way any other SwiftUI subtree does.
- **Placeholder scan:** no TBDs; every step has real code.
