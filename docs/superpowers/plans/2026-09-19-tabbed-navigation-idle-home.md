# Tabbed Navigation + Idle Home Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Home/Shelf tab switcher to the expanded notch, and give the Home tab real content (date/time + battery %) instead of a bare "Nothing playing" label when nothing's playing.

**Architecture:** A new orthogonal `NotchPage` (Home/Shelf), decided by a pure `NotchPageTransition` helper and held in `NotchViewModel`, drives which content `NotchRootView` shows while `NotchState == .expanded` — either `ExpandedPlayerView` (which itself now shows a new `IdleHomeView` in place of its old empty-state text) or `ShelfView`. A new `NotchTabBar` sits above whichever one is showing. `BatterySource` gains a second, always-on percent publisher so `IdleHomeView` doesn't duplicate its `IOKit.ps` reading logic.

**Tech Stack:** Swift 6, SwiftUI, Combine, Swift Testing. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-09-19-tabbed-navigation-idle-home-design.md`

## Global Constraints

- Swift 6, strict concurrency; `@MainActor` where the existing files already are.
- No third-party dependencies.
- `NotchStateMachine`/`NotchState` stay untouched — `NotchPage` is deliberately orthogonal, not folded into the reducer (spec's explicit rejection of that alternative).
- Invariant 3: the panel's actual window frame never resizes per-tab; only inner SwiftUI content does. Selecting the Shelf tab while `.expanded` must use `expandedSize`, not `shelfSize` — this falls out naturally from keeping `NotchState` at `.expanded` for a manual tab switch (only `NotchPage` changes), so no task below needs to touch sizing.
- The existing drag-triggered `.shelf` `NotchState` (entered via `NotchDragDetector`) is unchanged — it renders `ShelfView` exactly as it does today, with no tab bar. The tab bar only ever appears while `NotchState == .expanded`.
- Manual verification only for anything visual/interactive (per `CLAUDE.md`'s Testing section) — say so plainly rather than claiming coverage that doesn't exist.

---

### Task 1: `NotchPage` + `NotchPageTransition`

**Files:**
- Create: `Atelier/Notch/NotchPage.swift`
- Test: `AtelierTests/NotchPageTransitionTests.swift`

**Interfaces:**
- Produces: `enum NotchPage: Equatable { case home, shelf }` and `enum NotchPageTransition { static func page(for state: NotchState, currentPage: NotchPage) -> NotchPage }`, both used by Task 2.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
@testable import Atelier

struct NotchPageTransitionTests {
    @Test func shelfStateForcesShelfPageRegardlessOfCurrentPage() {
        let result = NotchPageTransition.page(for: .shelf, currentPage: .home)

        #expect(result == .shelf)
    }

    @Test func collapsedResetsToHomeEvenIfShelfWasSelected() {
        let result = NotchPageTransition.page(for: .collapsed, currentPage: .shelf)

        #expect(result == .home)
    }

    @Test func pillResetsToHomeEvenIfShelfWasSelected() {
        let result = NotchPageTransition.page(for: .pill, currentPage: .shelf)

        #expect(result == .home)
    }

    @Test func expandedPreservesCurrentPage() {
        let result = NotchPageTransition.page(for: .expanded, currentPage: .shelf)

        #expect(result == .shelf)
    }

    @Test func peekingPreservesCurrentPage() {
        let result = NotchPageTransition.page(for: .peeking, currentPage: .shelf)

        #expect(result == .shelf)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme Atelier -destination 'platform=macOS' -only-testing:AtelierTests/NotchPageTransitionTests`
Expected: FAIL to build — `NotchPage`/`NotchPageTransition` don't exist yet.

- [ ] **Step 3: Write the implementation**

```swift
/// Which page the expanded notch is showing — orthogonal to `NotchState`
/// on purpose (see the design spec's rejected alternative: folding this
/// into `NotchState` itself would duplicate every hover/peek transition
/// per page). Only matters while `NotchState == .expanded`; `NotchState`
/// itself still governs whether the notch is open at all.
enum NotchPage: Equatable {
    case home
    case shelf
}

/// Decides `NotchPage` alongside `NotchStateMachine.reduce` — kept pure
/// and separately testable for the same reason the reducer itself is.
enum NotchPageTransition {
    /// `state` is the *new* `NotchState` after `NotchStateMachine.reduce`
    /// has already run; `currentPage` is the page before this transition.
    static func page(for state: NotchState, currentPage: NotchPage) -> NotchPage {
        switch state {
        case .shelf:
            // A file drag/drop always wins, matching today's behavior.
            return .shelf
        case .collapsed, .pill:
            // Reset so the notch always opens on Home next time, rather
            // than remembering a stale Shelf selection.
            return .home
        case .expanded, .peeking:
            // A manual tab tap (handled outside this function, see
            // NotchViewModel.selectPage) persists across peeks/hovers.
            return currentPage
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme Atelier -destination 'platform=macOS' -only-testing:AtelierTests/NotchPageTransitionTests`
Expected: PASS, all 5 tests.

- [ ] **Step 5: Commit**

```bash
git add Atelier/Notch/NotchPage.swift AtelierTests/NotchPageTransitionTests.swift
git commit -m "feat: add NotchPage and its pure transition helper"
```

---

### Task 2: Wire `currentPage` into `NotchViewModel`

**Files:**
- Modify: `Atelier/Notch/NotchViewModel.swift`

**Interfaces:**
- Consumes: `NotchPage`, `NotchPageTransition.page(for:currentPage:)` from Task 1.
- Produces: `NotchViewModel.currentPage: NotchPage` (published) and `NotchViewModel.selectPage(_:)`, both used by Task 6.

- [ ] **Step 1: Modify `handle(_:)` and add `selectPage(_:)`**

In `Atelier/Notch/NotchViewModel.swift`, add a new published property next to `state`:

```swift
@Published private(set) var state: NotchState = .collapsed
@Published private(set) var currentPage: NotchPage = .home
```

Replace the existing `handle(_:)` method:

```swift
func handle(_ event: NotchEvent) {
    state = NotchStateMachine.reduce(state, on: event)
}
```

with:

```swift
func handle(_ event: NotchEvent) {
    let newState = NotchStateMachine.reduce(state, on: event)
    currentPage = NotchPageTransition.page(for: newState, currentPage: currentPage)
    state = newState
}

/// Called directly from a tab tap — bypasses `NotchPageTransition` since
/// this is a UI action, not a state-machine transition.
func selectPage(_ page: NotchPage) {
    currentPage = page
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `xcodebuild -scheme Atelier -configuration Debug build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Run the full unit suite to confirm no regression**

Run: `xcodebuild test -scheme Atelier -destination 'platform=macOS'`
Expected: `** TEST SUCCEEDED **`, same count as before plus Task 1's 5 new tests.

- [ ] **Step 4: Commit**

```bash
git add Atelier/Notch/NotchViewModel.swift
git commit -m "feat: track currentPage on NotchViewModel"
```

---

### Task 3: `BatterySource` always-on percent publisher

**Files:**
- Modify: `Atelier/Widgets/Battery/BatterySource.swift`

**Interfaces:**
- Produces: `BatterySource.currentPercentPublisher: AnyPublisher<Int, Never>`, used by Task 5.

- [ ] **Step 1: Add the subject and publisher**

In `Atelier/Widgets/Battery/BatterySource.swift`, add alongside the existing `subject`:

```swift
private let subject = CurrentValueSubject<LiveActivityContent?, Never>(nil)
/// Always-on, unlike `subject` above (which only emits on charging/low/
/// full) — feeds `IdleHomeView`'s always-visible battery percent without
/// a second `IOKit.ps` reader duplicating this class's own poll logic.
private let percentSubject = CurrentValueSubject<Int, Never>(0)
```

Add the new publisher next to the existing one:

```swift
var contentPublisher: AnyPublisher<LiveActivityContent?, Never> {
    subject.eraseToAnyPublisher()
}

var currentPercentPublisher: AnyPublisher<Int, Never> {
    percentSubject.eraseToAnyPublisher()
}
```

- [ ] **Step 2: Publish the percent from `poll()`**

In `poll()`, right after `let percent = Int(...)` is computed (before the `guard let state = BatteryActivityState.evaluate(...)` line), add:

```swift
let percent = Int((Double(currentCapacity) / Double(maxCapacity) * 100).rounded())
percentSubject.send(percent)

guard let state = BatteryActivityState.evaluate(percent: percent, isCharging: isCharging) else {
```

(Only the `percentSubject.send(percent)` line is new — it must run unconditionally, before the `guard`'s early return, so the idle view's percent updates even when there's nothing worth surfacing as ambient content.)

- [ ] **Step 3: Build to verify it compiles**

Run: `xcodebuild -scheme Atelier -configuration Debug build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add Atelier/Widgets/Battery/BatterySource.swift
git commit -m "feat: add always-on battery percent publisher"
```

---

### Task 4: `NotchTabBar`

**Files:**
- Create: `Atelier/UI/NotchTabBar.swift`

**Interfaces:**
- Consumes: `NotchPage` from Task 1.
- Produces: `NotchTabBar(currentPage:onSelect:)`, used by Task 6.

- [ ] **Step 1: Write the view**

```swift
import SwiftUI

/// A two-item Home/Shelf segmented control shown above the expanded
/// notch's content. Adapted from TheBoredTeam/boring.notch's
/// `TabSelectionView`/`TabButton` (read via `gh api` per
/// check-reference-apps-first) — same capsule-with-sliding-highlight
/// shape, simplified to this app's two fixed tabs instead of a
/// data-driven list.
struct NotchTabBar: View {
    let currentPage: NotchPage
    let onSelect: (NotchPage) -> Void

    private static let tabs: [(page: NotchPage, label: String)] = [
        (.home, "Home"),
        (.shelf, "Shelf")
    ]

    @Namespace private var highlight

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Self.tabs, id: \.page) { tab in
                Button {
                    onSelect(tab.page)
                } label: {
                    Text(tab.label)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(currentPage == tab.page ? .white : .white.opacity(0.5))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background {
                            if currentPage == tab.page {
                                Capsule()
                                    .fill(Color.white.opacity(0.15))
                                    .matchedGeometryEffect(id: "tabHighlight", in: highlight)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .background(Capsule().fill(Color.white.opacity(0.05)))
        .clipShape(Capsule())
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `xcodebuild -scheme Atelier -configuration Debug build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add Atelier/UI/NotchTabBar.swift
git commit -m "feat: add NotchTabBar Home/Shelf segmented control"
```

---

### Task 5: `IdleHomeView` and wiring it into `ExpandedPlayerView`

**Files:**
- Create: `Atelier/UI/IdleHomeView.swift`
- Modify: `Atelier/UI/ExpandedPlayerView.swift`

**Interfaces:**
- Consumes: `BatterySource.currentPercentPublisher` from Task 3.
- Produces: `IdleHomeView(batterySource:)`, used by Task 6 (indirectly, via `ExpandedPlayerView`'s new `batterySource` parameter).

- [ ] **Step 1: Write `IdleHomeView`**

```swift
import SwiftUI

/// Shown by `ExpandedPlayerView` in place of a bare "Nothing playing"
/// label when there's no `NowPlayingInfo` — date/time and battery percent,
/// the two pieces of ambient info worth surfacing when there's nothing
/// else to show. No reference app combines these two (see the design
/// spec's reference-apps section) — built fresh for Atelier.
struct IdleHomeView: View {
    let batterySource: BatterySource
    @State private var percent: Int?

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        return formatter
    }()

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            VStack(spacing: 6) {
                Text(Self.timeFormatter.string(from: timeline.date))
                    .font(.title2)
                    .fontWeight(.medium)
                Text(Self.dateFormatter.string(from: timeline.date))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
                if let percent {
                    Label("\(percent)%", systemImage: "battery.100")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                        .padding(.top, 4)
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onReceive(batterySource.currentPercentPublisher) { percent = $0 }
    }
}
```

- [ ] **Step 2: Wire it into `ExpandedPlayerView`**

In `Atelier/UI/ExpandedPlayerView.swift`, add a new stored property next to the existing ones:

```swift
struct ExpandedPlayerView: View {
    let info: NowPlayingInfo?
    let notchHeight: CGFloat
    let waveformColor: Color
    let outputDevices: [AudioOutputDevice]
    let currentOutputDeviceID: AudioDeviceID?
    let batterySource: BatterySource
    let onPlayPause: () -> Void
```

Replace the existing `emptyState`:

```swift
private var emptyState: some View {
    Text("Nothing playing")
        .font(.subheadline)
        .foregroundStyle(.white.opacity(0.65))
}
```

with:

```swift
private var emptyState: some View {
    IdleHomeView(batterySource: batterySource)
}
```

- [ ] **Step 3: Build to verify it compiles**

Run: `xcodebuild -scheme Atelier -configuration Debug build`
Expected: build FAILS at this point — `NotchRootView`'s existing `ExpandedPlayerView(...)` call site doesn't pass the new required `batterySource` argument yet. This is expected; Task 6 fixes the call site. Confirm the failure is specifically a missing-argument error at that call site, not something else.

- [ ] **Step 4: Commit**

```bash
git add Atelier/UI/IdleHomeView.swift Atelier/UI/ExpandedPlayerView.swift
git commit -m "feat: add IdleHomeView, show it from ExpandedPlayerView's empty state"
```

(Committing a build that doesn't compile is intentional here only because Task 6 is the very next task and fixes the one call site — the plan's tasks are meant to run back-to-back, not leave the tree broken for long. If executing this plan with real gaps between tasks, fold Task 5 and Task 6 together instead.)

---

### Task 6: Final wiring — `NotchController` and `NotchRootView`

**Files:**
- Modify: `Atelier/Notch/NotchController.swift`
- Modify: `Atelier/UI/NotchRootView.swift`

**Interfaces:**
- Consumes: `NotchViewModel.currentPage`/`selectPage(_:)` (Task 2), `NotchTabBar` (Task 4), `ExpandedPlayerView`'s new `batterySource` parameter (Task 5).

- [ ] **Step 1: Store `batterySource` as a property in `NotchController`**

In `Atelier/Notch/NotchController.swift`, add a new stored property next to `volumeSource`/`brightnessSource`:

```swift
private let volumeSource: VolumeSource
private let brightnessSource: BrightnessSource
private let batterySource: BatterySource
```

In the no-notch-screen fallback path (around line 87-100), change:

```swift
let volumeSource = VolumeSource(notchHeight: 0, hudOrder: hudOrder)
let brightnessSource = BrightnessSource(notchHeight: 0, hudOrder: hudOrder)
self.volumeSource = volumeSource
self.brightnessSource = brightnessSource
mediaKeyInterceptor = MediaKeyInterceptor(volumeSource: volumeSource, brightnessSource: brightnessSource)
liveActivityCoordinator = LiveActivityCoordinator(sources: [
    NowPlayingLiveActivitySource(coordinator: nowPlayingCoordinator, notchHeight: 0),
    BatterySource(notchHeight: 0),
    ScreenRecordingSource(notchHeight: 0),
    volumeSource,
    brightnessSource
])
panel.contentView = ClickThroughHostingView(
    rootView: NotchRootView(
        viewModel: viewModel,
        nowPlaying: nowPlayingCoordinator,
        liveActivity: liveActivityCoordinator,
        shelfStore: shelfStore
    )
)
```

to:

```swift
let volumeSource = VolumeSource(notchHeight: 0, hudOrder: hudOrder)
let brightnessSource = BrightnessSource(notchHeight: 0, hudOrder: hudOrder)
let batterySource = BatterySource(notchHeight: 0)
self.volumeSource = volumeSource
self.brightnessSource = brightnessSource
self.batterySource = batterySource
mediaKeyInterceptor = MediaKeyInterceptor(volumeSource: volumeSource, brightnessSource: brightnessSource)
liveActivityCoordinator = LiveActivityCoordinator(sources: [
    NowPlayingLiveActivitySource(coordinator: nowPlayingCoordinator, notchHeight: 0),
    batterySource,
    ScreenRecordingSource(notchHeight: 0),
    volumeSource,
    brightnessSource
])
panel.contentView = ClickThroughHostingView(
    rootView: NotchRootView(
        viewModel: viewModel,
        nowPlaying: nowPlayingCoordinator,
        liveActivity: liveActivityCoordinator,
        shelfStore: shelfStore,
        batterySource: batterySource
    )
)
```

In the real (notched-screen) path (around line 128-139), apply the same change:

```swift
let volumeSource = VolumeSource(notchHeight: collapsedRect.height, hudOrder: hudOrder)
let brightnessSource = BrightnessSource(notchHeight: collapsedRect.height, hudOrder: hudOrder)
let batterySource = BatterySource(notchHeight: collapsedRect.height)
self.volumeSource = volumeSource
self.brightnessSource = brightnessSource
self.batterySource = batterySource
mediaKeyInterceptor = MediaKeyInterceptor(volumeSource: volumeSource, brightnessSource: brightnessSource)
liveActivityCoordinator = LiveActivityCoordinator(sources: [
    NowPlayingLiveActivitySource(coordinator: nowPlayingCoordinator, notchHeight: collapsedRect.height),
    batterySource,
    ScreenRecordingSource(notchHeight: collapsedRect.height),
    volumeSource,
    brightnessSource
])
```

And further down, update the real path's `NotchRootView(...)` construction the same way:

```swift
panel.contentView = ClickThroughHostingView(
    rootView: NotchRootView(
        viewModel: viewModel,
        nowPlaying: nowPlayingCoordinator,
        liveActivity: liveActivityCoordinator,
        shelfStore: shelfStore,
        batterySource: batterySource
    )
)
```

- [ ] **Step 2: Add `batterySource` to `NotchRootView` and rewrite the `.expanded` branch**

In `Atelier/UI/NotchRootView.swift`, add the new property next to the existing ones:

```swift
struct NotchRootView: View {
    @ObservedObject var viewModel: NotchViewModel
    @ObservedObject var nowPlaying: NowPlayingCoordinator
    @ObservedObject var liveActivity: LiveActivityCoordinator
    @ObservedObject var shelfStore: ShelfStore
    let batterySource: BatterySource
```

Replace the existing `.expanded` branch:

```swift
if viewModel.state == .expanded {
    ExpandedPlayerView(
        info: nowPlaying.current,
        notchHeight: viewModel.collapsedSize.height,
        waveformColor: artworkColor.color,
        outputDevices: outputDevices,
        currentOutputDeviceID: currentOutputDeviceID,
        onPlayPause: { Task { await nowPlaying.playPause() } },
        onNext: { Task { await nowPlaying.next() } },
        onPrevious: { Task { await nowPlaying.previous() } },
        onSeek: { time in Task { await nowPlaying.seek(to: time) } },
        onToggleShuffle: { Task { await nowPlaying.toggleShuffle() } },
        onSelectOutputDevice: { deviceID in
            OutputDeviceManager.setDefaultOutputDevice(deviceID)
            currentOutputDeviceID = deviceID
        }
    )
    .transition(.opacity)
    .onAppear {
        outputDevices = OutputDeviceManager.availableOutputDevices()
        currentOutputDeviceID = OutputDeviceManager.currentDefaultOutputDevice()
    }
}
```

with:

```swift
if viewModel.state == .expanded {
    VStack(spacing: 0) {
        NotchTabBar(currentPage: viewModel.currentPage) { page in
            withAnimation(NotchAnimations.open) {
                viewModel.selectPage(page)
            }
        }
        .padding(.top, viewModel.collapsedSize.height + 8)

        if viewModel.currentPage == .shelf {
            ShelfView(store: shelfStore, rootDirectory: shelfStore.rootDirectory, notchHeight: 0)
                .onAppear { shelfStore.sweepExpired() }
        } else {
            ExpandedPlayerView(
                info: nowPlaying.current,
                notchHeight: 0,
                waveformColor: artworkColor.color,
                outputDevices: outputDevices,
                currentOutputDeviceID: currentOutputDeviceID,
                batterySource: batterySource,
                onPlayPause: { Task { await nowPlaying.playPause() } },
                onNext: { Task { await nowPlaying.next() } },
                onPrevious: { Task { await nowPlaying.previous() } },
                onSeek: { time in Task { await nowPlaying.seek(to: time) } },
                onToggleShuffle: { Task { await nowPlaying.toggleShuffle() } },
                onSelectOutputDevice: { deviceID in
                    OutputDeviceManager.setDefaultOutputDevice(deviceID)
                    currentOutputDeviceID = deviceID
                }
            )
            .onAppear {
                outputDevices = OutputDeviceManager.availableOutputDevices()
                currentOutputDeviceID = OutputDeviceManager.currentDefaultOutputDevice()
            }
        }
    }
    .transition(.opacity)
}
```

(`notchHeight: 0` on both `ShelfView` and `ExpandedPlayerView` here is deliberate — the new `NotchTabBar` above them now provides the top clearance past the physical notch cutout that `notchHeight` used to provide directly. Their own existing `.padding(.top, notchHeight + …)` still adds a small gap under the tab bar since `notchHeight` is 0, not removed.)

- [ ] **Step 3: Build to verify it compiles**

Run: `xcodebuild -scheme Atelier -configuration Debug build`
Expected: `** BUILD SUCCEEDED **` — this is where Task 5's deliberately-broken build gets fixed.

- [ ] **Step 4: Run the full unit suite**

Run: `xcodebuild test -scheme Atelier -destination 'platform=macOS'`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Atelier/Notch/NotchController.swift Atelier/UI/NotchRootView.swift
git commit -m "feat: wire NotchTabBar and page switching into the expanded notch"
```

- [ ] **Step 6: Build and relaunch for manual verification**

Use the `build` skill (or run its steps directly): kill any running `Atelier`, build, relaunch.

Manually verify on-device (check these off only once actually exercised, per `CLAUDE.md`'s Testing section — this is real UI behavior, not something the unit suite covers):
- [ ] Hovering with nothing playing shows the Home tab with date/time + battery %, not a bare "Nothing playing" label.
- [ ] Tapping "Shelf" while hovering switches to the shelf grid, without the panel changing size (Invariant 3 / the "don't take up more space" constraint).
- [ ] Tapping "Home" switches back.
- [ ] Dragging a file onto the notch still auto-switches to Shelf exactly as before (drag-triggered `.shelf` `NotchState`, unaffected by this change).
- [ ] Closing the notch (mouse leaves) and reopening always lands back on Home, even if Shelf was selected last.
- [ ] Playing music still shows the player as before, tab bar visible above it.
- [ ] Update `docs/ROADMAP.md` with the result of manual verification (or any bug found) — same discipline as the file shelf's own entry.

---

## Self-Review Notes

- **Spec coverage:** page architecture (Task 1-2), tab bar UI (Task 4), idle content (Task 5), battery percent publisher (Task 3), final wiring (Task 6) — all spec sections have a task. The spec's "out of scope" items (a third tab, calendar/camera companions, `.peeking` changes) have no task, correctly.
- **Type consistency:** `NotchPage`/`NotchPageTransition.page(for:currentPage:)` (Task 1) match their use in `NotchViewModel.handle(_:)` (Task 2) and `NotchTabBar`'s `currentPage`/`onSelect` (Task 4) match their use in `NotchRootView` (Task 6). `BatterySource.currentPercentPublisher` (Task 3) matches its use in `IdleHomeView` (Task 5). `ExpandedPlayerView`'s new `batterySource` parameter (Task 5) matches both its call sites (Task 6, one only — the old call site is fully replaced, not left as a second one).
- **Placeholder scan:** no TBDs; every step has real code.
