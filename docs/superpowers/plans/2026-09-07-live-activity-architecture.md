# Live Activity Architecture (Phase 6) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Generalize the notch's peek/pill/expanded mechanism from a
Spotify-only surface into an extensible `LiveActivitySource`/
`LiveActivityContent` seam, ship a real resting-pill visual (artwork +
mini waveform, currently blank), and prove the seam with two new widgets
(Battery, then AirPods).

**Architecture:** A new pure `LiveActivityStack` (priority-sorted list,
Foundation-only, unit-tested like `NotchGeometry`/`NotchState`) tracks
which source is "on top." A `LiveActivityCoordinator` (AppKit/Combine
layer) merges each `LiveActivitySource`'s published content into that
stack and republishes generic "identity changed" / "has content" signals
that `NotchController` maps onto `NotchState`'s **existing, unmodified**
event vocabulary (`.trackChanged`, `.isPlayingChanged`,
`.playbackToggled`, `.peekTimerElapsed`) — `NotchState.swift` itself is
not touched; it was already source-agnostic in effect, just single-source
in practice. `NowPlayingCoordinator` becomes the first thing wrapped as a
`LiveActivitySource`; `.expanded` (the interactive transport-controls
view) stays hardcoded to now-playing, since it's the only source with
transport controls to expand into — every other content type is pill/peek
only, matching `isExpandable` defaulting to `false` in the DynamicNotch
reference this design borrows from.

**Tech Stack:** Swift 6, SwiftUI, Combine, `IOKit.ps` (battery),
`IOBluetooth` (AirPods). No third-party dependencies.

**Spec:** `docs/superpowers/specs/2026-09-07-live-activity-architecture-design.md`

## Global Constraints

- `NotchGeometry` and `NotchState` import nothing but Foundation/
  CoreGraphics — do not add imports to either file. `LiveActivityStack`
  follows the same rule (Foundation only).
- Never scripting-query or otherwise probe a media/Bluetooth resource in a
  way that could launch or wake something the user hasn't already got
  running.
- The panel is always sized to the maximum expanded footprint; only
  SwiftUI content animates. Do not resize the window per state.
- Non-interactive regions get `.allowsHitTesting(false)`, scoped
  precisely — not on an ancestor of anything interactive (see
  `docs/decisions/0004-allowshittesting-scoped-to-spacer.md`).
- Collapsed state stays visually indistinguishable from the stock notch.
- Preserve all existing behavior: hover expand/collapse, pill/peek/decay
  timing, peek-on-track-change and peek-on-playback-toggle settings
  gating, output-device switching. No regressions.
- Credit adapted reference-app code in a short source comment
  (`jackson-storm/dynamicnotch` for the content-protocol shape,
  `Clayton630/QuartzNotch` for the Battery/Bluetooth manager patterns).
- Swift Testing (`import Testing`, `@Test`, `#expect`), not XCTest, for
  all new unit tests — matches the existing suite.

---

## Task 1: `LiveActivityStack` (pure, unit-tested)

**Files:**
- Create: `Atelier/Notch/LiveActivityStack.swift`
- Test: `AtelierTests/LiveActivityStackTests.swift`

**Interfaces:**
- Produces: `struct LiveActivityStack: Equatable` with
  `mutating func upsert(id: String, priority: Int)`,
  `mutating func remove(id: String)`, `var topID: String? { get }`.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
@testable import Atelier

struct LiveActivityStackTests {
    @Test func topIDIsNilWhenEmpty() {
        let stack = LiveActivityStack()
        #expect(stack.topID == nil)
    }

    @Test func singleUpsertBecomesTop() {
        var stack = LiveActivityStack()
        stack.upsert(id: "battery", priority: 1)
        #expect(stack.topID == "battery")
    }

    @Test func higherPriorityWins() {
        var stack = LiveActivityStack()
        stack.upsert(id: "battery", priority: 1)
        stack.upsert(id: "nowPlaying", priority: 5)
        #expect(stack.topID == "nowPlaying")
    }

    @Test func lowerPriorityDoesNotDisplaceTop() {
        var stack = LiveActivityStack()
        stack.upsert(id: "nowPlaying", priority: 5)
        stack.upsert(id: "battery", priority: 1)
        #expect(stack.topID == "nowPlaying")
    }

    @Test func upsertReplacesSameIDInPlace() {
        var stack = LiveActivityStack()
        stack.upsert(id: "battery", priority: 1)
        stack.upsert(id: "battery", priority: 9)
        stack.upsert(id: "nowPlaying", priority: 5)
        #expect(stack.topID == "battery")
    }

    @Test func removeDropsEntryAndPromotesNext() {
        var stack = LiveActivityStack()
        stack.upsert(id: "battery", priority: 1)
        stack.upsert(id: "nowPlaying", priority: 5)
        stack.remove(id: "nowPlaying")
        #expect(stack.topID == "battery")
    }

    @Test func removeUnknownIDIsNoOp() {
        var stack = LiveActivityStack()
        stack.upsert(id: "battery", priority: 1)
        stack.remove(id: "nowPlaying")
        #expect(stack.topID == "battery")
    }

    @Test func equalPriorityBreaksTieByIDOrdering() {
        var stackA = LiveActivityStack()
        stackA.upsert(id: "battery", priority: 1)
        stackA.upsert(id: "airpods", priority: 1)

        var stackB = LiveActivityStack()
        stackB.upsert(id: "airpods", priority: 1)
        stackB.upsert(id: "battery", priority: 1)

        // Deterministic regardless of insertion order.
        #expect(stackA.topID == stackB.topID)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme Atelier -destination 'platform=macOS' -only-testing:AtelierTests/LiveActivityStackTests`
Expected: FAIL to build — `LiveActivityStack` doesn't exist yet.

- [ ] **Step 3: Implement `LiveActivityStack`**

```swift
/// Which `LiveActivitySource` is currently "on top" of the notch, ranked
/// by priority. Pure — Foundation only, no AppKit/SwiftUI — same
/// invariant as `NotchGeometry`/`NotchState`. Holds only `(id, priority)`
/// pairs; the actual content each id maps to is owned by
/// `LiveActivityCoordinator`, not this type.
struct LiveActivityStack: Equatable {
    private struct Entry: Equatable {
        let id: String
        let priority: Int
    }

    private var entries: [Entry] = []

    var topID: String? { entries.first?.id }

    mutating func upsert(id: String, priority: Int) {
        entries.removeAll { $0.id == id }
        entries.append(Entry(id: id, priority: priority))
        entries.sort { lhs, rhs in
            if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
            return lhs.id < rhs.id
        }
    }

    mutating func remove(id: String) {
        entries.removeAll { $0.id == id }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme Atelier -destination 'platform=macOS' -only-testing:AtelierTests/LiveActivityStackTests`
Expected: PASS (all 8 tests)

- [ ] **Step 5: Commit**

```bash
git add Atelier/Notch/LiveActivityStack.swift AtelierTests/LiveActivityStackTests.swift
git commit -m "$(cat <<'EOF'
feat: add pure LiveActivityStack for priority-ranked notch content

Foundation-only priority list deciding which live activity source is
"on top" -- same purity invariant as NotchGeometry/NotchState. No
wiring yet; this is the data structure Phase 6's widgets will share.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_0124yKTWHuLdrDfjcebwgfwU
EOF
)"
```

---

## Task 2: `LiveActivitySource` / `LiveActivityContent` protocols

**Files:**
- Create: `Atelier/Notch/LiveActivitySource.swift`

**Interfaces:**
- Consumes: nothing new.
- Produces: `protocol LiveActivitySource` (`id: String`, `priority: Int`,
  `contentPublisher: AnyPublisher<LiveActivityContent?, Never>`) and
  `protocol LiveActivityContent` (`id: String`, `isExpandable: Bool`,
  `pillView() -> AnyView`, `peekView() -> AnyView`) — every later task's
  sources/content conform to these exact names.

This task is protocol-only (no logic to unit test); it's folded into one
step since there's no meaningful failing-test cycle for a protocol
declaration.

- [ ] **Step 1: Add the protocols**

```swift
import Combine
import SwiftUI

/// One producer of notch content — now-playing, battery, AirPods, etc.
/// Mirrors `NowPlayingSource`'s seam: a new source is one new file
/// conforming here, registered once in `NotchController`, nothing else
/// touched. `nil` from `contentPublisher` means "nothing to show right
/// now," not "remove this source" -- it's how a source opts in/out of the
/// stack as its own state changes (e.g. battery no longer low).
///
/// Shape adapted from jackson-storm/dynamicnotch's `NotchContentProtocol`
/// + `NotchEngine`, read via `gh api` before designing (see
/// check-reference-apps-first) -- simplified to a priority list without
/// its queueing engine or temporary-notification distinction, neither of
/// which anything here needs yet.
protocol LiveActivitySource {
    /// Stable per source (e.g. "nowPlaying", "battery"), used as the
    /// `LiveActivityStack` entry id -- NOT the same as
    /// `LiveActivityContent.id`, which identifies a specific piece of
    /// content (a track, a battery state) and changes far more often.
    var id: String { get }
    var priority: Int { get }
    var contentPublisher: AnyPublisher<LiveActivityContent?, Never> { get }
}

/// What a `LiveActivitySource` currently wants shown. UI-layer (may
/// import SwiftUI), unlike `LiveActivitySource` and `LiveActivityStack`.
protocol LiveActivityContent {
    /// Identifies *this specific piece of content* -- e.g. `"title|artist"`
    /// for a track, `"battery:low"` for a battery state. Two consecutive
    /// values with different ids is what makes `LiveActivityCoordinator`
    /// treat a change as peek-worthy.
    var id: String { get }
    /// Whether hovering while this content is on top should open a full
    /// interactive `.expanded` view. Only now-playing needs this --
    /// everything else defaults to pill/peek only, matching
    /// `NotchContentProtocol.isExpandable` defaulting to `false` in the
    /// dynamicnotch reference.
    var isExpandable: Bool { get }
    @ViewBuilder func pillView() -> AnyView
    @ViewBuilder func peekView() -> AnyView
}

extension LiveActivityContent {
    var isExpandable: Bool { false }
}
```

- [ ] **Step 2: Build to confirm it compiles**

Run: `xcodebuild -scheme Atelier -configuration Debug build`
Expected: BUILD SUCCEEDED (nothing conforms yet, which is fine — no
call sites reference these protocols until Task 4).

- [ ] **Step 3: Commit**

```bash
git add Atelier/Notch/LiveActivitySource.swift
git commit -m "$(cat <<'EOF'
feat: add LiveActivitySource/LiveActivityContent protocols

The widget seam Phase 6 generalizes around, mirroring NowPlayingSource:
one new file per source, nothing else touched. Shape adapted from
jackson-storm/dynamicnotch's NotchContentProtocol, read via gh api
first per check-reference-apps-first.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_0124yKTWHuLdrDfjcebwgfwU
EOF
)"
```

---

## Task 3: `PillPlayerView` — the resting pill gets real content

Ships independently of the protocol work above — uses the same direct
`nowPlaying`/`artworkColor` wiring `PeekPlayerView`/`ExpandedPlayerView`
already use in `NotchRootView`, so this is a small, low-risk, immediately
visible change. Gets folded into the generic seam in Task 4.

**Files:**
- Create: `Atelier/UI/PillPlayerView.swift`
- Modify: `Atelier/UI/NotchRootView.swift:34-70` (add the `.pill` render branch)

**Interfaces:**
- Consumes: `NowPlayingInfo` (`Atelier/NowPlaying/NowPlayingInfo.swift`),
  `ArtworkView(url:cornerRadius:)` and `WaveformView(isPlaying:color:
  barWidth:barSpacing:height:)` (both existing, `Atelier/UI/
  ExpandedPlayerView.swift` / `Atelier/UI/WaveformView.swift`).
- Produces: `struct PillPlayerView: View` with
  `init(info: NowPlayingInfo?, notchHeight: CGFloat, waveformColor: Color)`.

No pure logic here to TDD (it's a SwiftUI layout) — build and verify
on-device per this project's existing convention for UI work (see
`CLAUDE.md`'s testing section: layout is manual-verification, not unit
tested).

- [ ] **Step 1: Write `PillPlayerView`**

```swift
import SwiftUI

/// The persistent sliver shown while `.pill` (playing, not hovering or
/// peeking). `pillSize` is only `pillExtraWidth` (40pt, see
/// `NotchController`) wider than the real notch cutout and the *same
/// height* -- no room for text, only two ~20pt flanks either side of the
/// physical camera cutout (which has no display pixels of its own, so a
/// plain `Spacer` between the two flanks correctly leaves it untouched).
/// Artwork icon on the left flank, a mini waveform on the right --
/// matches Clayton630/QuartzNotch's "real-time audio visualizer" resting
/// pill, read via `gh api` before designing this (see
/// check-reference-apps-first).
struct PillPlayerView: View {
    let info: NowPlayingInfo?
    let notchHeight: CGFloat
    let waveformColor: Color

    private var artworkSide: CGFloat { min(notchHeight - 6, 20) }

    var body: some View {
        Group {
            if let info {
                HStack(spacing: 0) {
                    ArtworkView(url: info.artworkURL, cornerRadius: 4)
                        .frame(width: artworkSide, height: artworkSide)

                    Spacer(minLength: 0)

                    WaveformView(
                        isPlaying: info.isPlaying,
                        color: waveformColor,
                        barWidth: 1.5,
                        barSpacing: 1,
                        height: 12
                    )
                }
            }
        }
        .padding(.horizontal, 6)
    }
}
```

- [ ] **Step 2: Wire it into `NotchRootView`'s `.pill` case**

In `Atelier/UI/NotchRootView.swift`, the `ZStack` currently only branches
on `.expanded` and `.peeking` (lines 40-69). Add a `.pill` branch right
after the `.peeking` branch closes (before the final `}` of the `ZStack`,
line 69-70):

```swift
                } else if viewModel.state == .peeking {
                    PeekPlayerView(
                        info: nowPlaying.current,
                        notchHeight: viewModel.collapsedSize.height,
                        waveformColor: artworkColor.color
                    )
                    .transition(.opacity)
                } else if viewModel.state == .pill {
                    PillPlayerView(
                        info: nowPlaying.current,
                        notchHeight: viewModel.collapsedSize.height,
                        waveformColor: artworkColor.color
                    )
                    .transition(.opacity)
                }
```

- [ ] **Step 3: Build**

Run: `xcodebuild -scheme Atelier -configuration Debug build`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Manual on-device verification**

Use the `/build` slash command (or `xcodebuild ... && relaunch`) to run
the app with Spotify playing. Confirm: while playing and not hovering,
the pill shows small artwork on the left edge and a mini waveform on the
right edge (not a blank sliver); the existing collapsed → pill → peek →
expanded transitions all still animate correctly (no regression).

- [ ] **Step 5: Commit**

```bash
git add Atelier/UI/PillPlayerView.swift Atelier/UI/NotchRootView.swift
git commit -m "$(cat <<'EOF'
feat: show artwork + mini waveform in the resting pill

The .pill state rendered nothing but the bare notch shape -- undershot
Phase 5's own "slim pill hugs the notch while music plays" goal.
Layout (artwork left flank, waveform right flank, physical notch
cutout left untouched in between) matches Clayton630/QuartzNotch's
resting-pill reference image.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_0124yKTWHuLdrDfjcebwgfwU
EOF
)"
```

---

## Task 4: Wrap now-playing as a `LiveActivitySource`, generalize Pill/Peek

**Files:**
- Create: `Atelier/NowPlaying/NowPlayingActivityContent.swift`
- Create: `Atelier/NowPlaying/NowPlayingLiveActivitySource.swift`
- Modify: `Atelier/UI/PeekPlayerView.swift` (remove the external
  `waveformColor` parameter; load its own color, same pattern as the new
  `PillPlayerView` will adopt in this task)
- Modify: `Atelier/UI/PillPlayerView.swift` (same: own its color)
- Modify: `Atelier/UI/NotchRootView.swift` (route `.pill`/`.peeking`
  through the generic content, `.expanded` stays hardcoded to now-playing)

**Interfaces:**
- Consumes: `LiveActivitySource`/`LiveActivityContent` (Task 2),
  `NowPlayingCoordinator` (existing, `Atelier/NowPlaying/
  NowPlayingCoordinator.swift`), `ArtworkColorLoader` (existing,
  `Atelier/UI/ArtworkColorLoader.swift` — confirm actual path with
  `grep -rl "class ArtworkColorLoader"`).
- Produces: `struct NowPlayingActivityContent: LiveActivityContent`,
  `final class NowPlayingLiveActivitySource: LiveActivitySource` with
  `init(coordinator: NowPlayingCoordinator, notchHeight: CGFloat)`, id
  `"nowPlaying"`, priority `NotchLiveActivityPriority.nowPlaying` (define
  as `10` — an internal `enum NotchLiveActivityPriority` constant, same
  file as the source, so Task 7/9's Battery/AirPods sources reference
  named constants instead of magic numbers).

- [ ] **Step 1: Give `PillPlayerView` and `PeekPlayerView` their own artwork-color loader**

Both currently receive `waveformColor` from `NotchRootView`'s single
shared `ArtworkColorLoader`. Once they're constructed generically through
`LiveActivityContent.pillView()`/`peekView()` (no arguments), there's no
place to thread an externally-computed color through — so each view loads
its own, keyed by `info?.artworkURL` exactly like the existing loader's
`load(from:)` already supports. `ExpandedPlayerView` is untouched — it
stays hardcoded to now-playing and keeps using `NotchRootView`'s shared
loader.

In `Atelier/UI/PillPlayerView.swift`, replace the `waveformColor: Color`
parameter:

```swift
struct PillPlayerView: View {
    let info: NowPlayingInfo?
    let notchHeight: CGFloat
    @StateObject private var artworkColor = ArtworkColorLoader()

    private var artworkSide: CGFloat { min(notchHeight - 6, 20) }

    var body: some View {
        Group {
            if let info {
                HStack(spacing: 0) {
                    ArtworkView(url: info.artworkURL, cornerRadius: 4)
                        .frame(width: artworkSide, height: artworkSide)

                    Spacer(minLength: 0)

                    WaveformView(
                        isPlaying: info.isPlaying,
                        color: artworkColor.color,
                        barWidth: 1.5,
                        barSpacing: 1,
                        height: 12
                    )
                }
            }
        }
        .padding(.horizontal, 6)
        .onAppear { artworkColor.load(from: info?.artworkURL) }
        .onChange(of: info?.artworkURL) { _, url in artworkColor.load(from: url) }
    }
}
```

Apply the same pattern to `Atelier/UI/PeekPlayerView.swift`: remove its
`waveformColor: Color` parameter, add `@StateObject private var
artworkColor = ArtworkColorLoader()`, replace the `WaveformView(...,
color: waveformColor, ...)` call with `color: artworkColor.color`, and
add the same `.onAppear`/`.onChange(of: info?.artworkURL)` pair to its
`body`.

- [ ] **Step 2: Build to confirm the two view changes compile on their own**

Run: `xcodebuild -scheme Atelier -configuration Debug build`
Expected: BUILD FAILS at `NotchRootView.swift`'s existing
`PeekPlayerView(..., waveformColor: artworkColor.color)` and
`PillPlayerView(..., waveformColor: artworkColor.color)` call sites —
expected at this point, fixed in Step 5.

- [ ] **Step 3: Write `NowPlayingActivityContent`**

```swift
import SwiftUI

/// Wraps `NowPlayingInfo` as `LiveActivityContent` so the pill/peek
/// surfaces render it through the generic seam instead of being
/// hardcoded to now-playing. `id` is `"title|artist"` -- same dedup key
/// `NotchController` used to compute inline before this task; a change
/// here is what `LiveActivityCoordinator` treats as peek-worthy (see
/// Task 5). Pausing/resuming the *same* track does not change this id --
/// that's carried by the separate `hasContent` signal, not identity.
struct NowPlayingActivityContent: LiveActivityContent {
    let info: NowPlayingInfo
    let notchHeight: CGFloat

    var id: String { "\(info.title)|\(info.artist)" }
    var isExpandable: Bool { true }

    func pillView() -> AnyView {
        AnyView(PillPlayerView(info: info, notchHeight: notchHeight))
    }

    func peekView() -> AnyView {
        AnyView(PeekPlayerView(info: info, notchHeight: notchHeight))
    }
}
```

- [ ] **Step 4: Write `NowPlayingLiveActivitySource`**

```swift
import Combine
import Foundation

/// Priorities for every `LiveActivitySource`, kept in one place so a new
/// source's ranking is a one-line addition, not a magic number buried in
/// its own file.
enum NotchLiveActivityPriority {
    static let nowPlaying = 10
    // Battery/AirPods priorities are added here in later tasks.
}

/// Wraps the existing `NowPlayingCoordinator` as a `LiveActivitySource`,
/// per the design spec's migration note: `NowPlayingCoordinator` itself
/// is not rewritten, just wrapped.
final class NowPlayingLiveActivitySource: LiveActivitySource {
    let id = "nowPlaying"
    let priority = NotchLiveActivityPriority.nowPlaying

    private let notchHeight: CGFloat

    init(coordinator: NowPlayingCoordinator, notchHeight: CGFloat) {
        self.notchHeight = notchHeight
        self.coordinator = coordinator
    }

    private let coordinator: NowPlayingCoordinator

    var contentPublisher: AnyPublisher<LiveActivityContent?, Never> {
        coordinator.$current
            .map { [notchHeight] info -> LiveActivityContent? in
                guard let info, info.isPlaying else { return nil }
                return NowPlayingActivityContent(info: info, notchHeight: notchHeight)
            }
            .eraseToAnyPublisher()
    }
}
```

- [ ] **Step 5: Route `.pill`/`.peeking` in `NotchRootView` through the generic content**

`NotchRootView` needs the coordinator's current top content to render
generically. For this task, before `LiveActivityCoordinator` exists
(Task 5), pass a `LiveActivityContent?` computed directly from
`nowPlaying.current` so the two view changes from Step 1 have a caller —
Task 6 then swaps this for the real coordinator-driven value without
touching this rendering code again.

Add a computed property near the top of `NotchRootView`:

```swift
    private var topContent: LiveActivityContent? {
        guard let info = nowPlaying.current, info.isPlaying else { return nil }
        return NowPlayingActivityContent(info: info, notchHeight: viewModel.collapsedSize.height)
    }
```

Replace the `.peeking` and `.pill` branches (from Task 3) with:

```swift
                } else if viewModel.state == .peeking {
                    if let topContent {
                        topContent.peekView()
                            .transition(.opacity)
                    }
                } else if viewModel.state == .pill {
                    if let topContent {
                        topContent.pillView()
                            .transition(.opacity)
                    }
                }
```

`.expanded`'s branch is unchanged — it still constructs `ExpandedPlayerView`
directly with `nowPlaying.current`, matching `isExpandable` being
now-playing-only.

- [ ] **Step 6: Build**

Run: `xcodebuild -scheme Atelier -configuration Debug build`
Expected: BUILD SUCCEEDED

- [ ] **Step 7: Manual on-device verification**

Run via `/build`. Confirm pill and peek still show artwork/waveform
correctly (colors may take a beat to update now that each view loads its
own — that's expected, same latency `ArtworkColorLoader` always had).
Expanded player unaffected. No regression in hover/peek/decay timing.

- [ ] **Step 8: Commit**

```bash
git add Atelier/NowPlaying/NowPlayingActivityContent.swift \
        Atelier/NowPlaying/NowPlayingLiveActivitySource.swift \
        Atelier/UI/PillPlayerView.swift Atelier/UI/PeekPlayerView.swift \
        Atelier/UI/NotchRootView.swift
git commit -m "$(cat <<'EOF'
feat: render pill/peek through the generic LiveActivityContent seam

NowPlayingActivityContent/NowPlayingLiveActivitySource wrap the
existing NowPlayingCoordinator without rewriting it. .pill/.peeking
now render whatever content is on top generically; .expanded stays
hardcoded to now-playing, the only source with transport controls.
PillPlayerView/PeekPlayerView load their own artwork color now that
nothing external threads it through the no-argument protocol methods.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_0124yKTWHuLdrDfjcebwgfwU
EOF
)"
```

---

## Task 5: `LiveActivityCoordinator`

**Files:**
- Create: `Atelier/Notch/LiveActivityCoordinator.swift`
- Test: `AtelierTests/LiveActivityCoordinatorTests.swift`

**Interfaces:**
- Consumes: `LiveActivitySource`/`LiveActivityContent` (Task 2),
  `LiveActivityStack` (Task 1).
- Produces: `@MainActor final class LiveActivityCoordinator: ObservableObject`
  with `init(sources: [LiveActivitySource])`,
  `@Published private(set) var topContent: LiveActivityContent?`,
  `@Published private(set) var hasContent: Bool`,
  `let identityChanged: PassthroughSubject<Void, Never>`.

A fake `LiveActivitySource` (below) makes the merge/priority/dedup logic
directly testable without touching real `IOKit`/AppleScript.

- [ ] **Step 1: Write the failing tests**

```swift
import Combine
import Testing
@testable import Atelier

private struct FakeContent: LiveActivityContent {
    let id: String
    func pillView() -> AnyView { AnyView(EmptyView()) }
    func peekView() -> AnyView { AnyView(EmptyView()) }
}

private final class FakeSource: LiveActivitySource {
    let id: String
    let priority: Int
    private let subject = CurrentValueSubject<LiveActivityContent?, Never>(nil)

    init(id: String, priority: Int) {
        self.id = id
        self.priority = priority
    }

    var contentPublisher: AnyPublisher<LiveActivityContent?, Never> {
        subject.eraseToAnyPublisher()
    }

    func publish(contentID: String?) {
        subject.send(contentID.map { FakeContent(id: $0) })
    }
}

@MainActor
struct LiveActivityCoordinatorTests {
    @Test func topContentIsNilWithNothingPublished() {
        let source = FakeSource(id: "battery", priority: 1)
        let coordinator = LiveActivityCoordinator(sources: [source])
        #expect(coordinator.topContent == nil)
        #expect(coordinator.hasContent == false)
    }

    @Test func publishingContentBecomesTopContent() {
        let source = FakeSource(id: "battery", priority: 1)
        let coordinator = LiveActivityCoordinator(sources: [source])
        source.publish(contentID: "battery:low")
        #expect(coordinator.topContent?.id == "battery:low")
        #expect(coordinator.hasContent == true)
    }

    @Test func higherPrioritySourceWinsTopContent() {
        let low = FakeSource(id: "battery", priority: 1)
        let high = FakeSource(id: "nowPlaying", priority: 10)
        let coordinator = LiveActivityCoordinator(sources: [low, high])
        low.publish(contentID: "battery:low")
        high.publish(contentID: "trackA")
        #expect(coordinator.topContent?.id == "trackA")
    }

    @Test func withdrawingTopContentFallsBackToNextSource() {
        let low = FakeSource(id: "battery", priority: 1)
        let high = FakeSource(id: "nowPlaying", priority: 10)
        let coordinator = LiveActivityCoordinator(sources: [low, high])
        low.publish(contentID: "battery:low")
        high.publish(contentID: "trackA")
        high.publish(contentID: nil)
        #expect(coordinator.topContent?.id == "battery:low")
    }

    @Test func identityChangedFiresOnDifferentContentID() {
        let source = FakeSource(id: "nowPlaying", priority: 10)
        let coordinator = LiveActivityCoordinator(sources: [source])
        var fireCount = 0
        let cancellable = coordinator.identityChanged.sink { fireCount += 1 }
        source.publish(contentID: "trackA")
        source.publish(contentID: "trackB")
        #expect(fireCount == 2) // nil -> trackA, trackA -> trackB
        cancellable.cancel()
    }

    @Test func identityChangedDoesNotFireForNilTransition() {
        let source = FakeSource(id: "nowPlaying", priority: 10)
        let coordinator = LiveActivityCoordinator(sources: [source])
        source.publish(contentID: "trackA")
        var fireCount = 0
        let cancellable = coordinator.identityChanged.sink { fireCount += 1 }
        source.publish(contentID: nil)
        #expect(fireCount == 0)
        cancellable.cancel()
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme Atelier -destination 'platform=macOS' -only-testing:AtelierTests/LiveActivityCoordinatorTests`
Expected: FAIL to build — `LiveActivityCoordinator` doesn't exist yet.

- [ ] **Step 3: Implement `LiveActivityCoordinator`**

```swift
import Combine
import Foundation

/// Merges every `LiveActivitySource`'s content into a `LiveActivityStack`
/// and republishes two generic signals `NotchController` maps onto
/// `NotchState`'s existing event vocabulary (`.trackChanged`,
/// `.isPlayingChanged`, `.playbackToggled`) -- `NotchState.swift` itself
/// is not modified; it was already source-agnostic in effect. Simplified
/// relative to dynamicnotch's `NotchEngine` (no queueing, no
/// temporary-vs-persistent distinction, no dismiss/restore history) --
/// per the design spec, nothing here needs that yet.
@MainActor
final class LiveActivityCoordinator: ObservableObject {
    @Published private(set) var topContent: LiveActivityContent?
    @Published private(set) var hasContent = false
    let identityChanged = PassthroughSubject<Void, Never>()

    private var stack = LiveActivityStack()
    private var latestContent: [String: LiveActivityContent] = [:]
    private var lastContentID: String?
    private var cancellables: Set<AnyCancellable> = []

    init(sources: [LiveActivitySource]) {
        for source in sources {
            source.contentPublisher
                .sink { [weak self] content in
                    self?.handle(sourceID: source.id, priority: source.priority, content: content)
                }
                .store(in: &cancellables)
        }
    }

    private func handle(sourceID: String, priority: Int, content: LiveActivityContent?) {
        if let content {
            latestContent[sourceID] = content
            stack.upsert(id: sourceID, priority: priority)
        } else {
            latestContent.removeValue(forKey: sourceID)
            stack.remove(id: sourceID)
        }

        topContent = stack.topID.flatMap { latestContent[$0] }

        let newContentID = topContent?.id
        if let newContentID, newContentID != lastContentID {
            identityChanged.send()
        }
        lastContentID = newContentID

        hasContent = topContent != nil
    }
}
```

Note: `@Published` only publishes when the new value differs for
`Equatable` types; `LiveActivityContent` is not `Equatable` (existential
protocol), so `hasContent` (a plain `Bool`) is the dedup'd boolean signal
`NotchController` observes — assigning it unconditionally here is
correct, `@Published`'s `willSet` still only triggers subscriber
`objectWillChange` sends on actual writes, but consumers should observe
`$hasContent.removeDuplicates()` (Task 6) to match the old
`isPlayingCancellable`'s `.removeDuplicates()` behavior exactly.

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme Atelier -destination 'platform=macOS' -only-testing:AtelierTests/LiveActivityCoordinatorTests`
Expected: PASS (all 6 tests)

- [ ] **Step 5: Commit**

```bash
git add Atelier/Notch/LiveActivityCoordinator.swift AtelierTests/LiveActivityCoordinatorTests.swift
git commit -m "$(cat <<'EOF'
feat: add LiveActivityCoordinator merging sources into the stack

Publishes topContent (priority winner), hasContent (generalizes the
old isPlaying signal), and identityChanged (generalizes the old
title|artist dedup key) generically across any number of sources.
NotchController wiring lands in the next task.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_0124yKTWHuLdrDfjcebwgfwU
EOF
)"
```

---

## Task 6: Wire `NotchController`/`NotchRootView` through the coordinator

This is the highest-risk task in the plan — it replaces
`NotchController`'s direct `nowPlayingCoordinator.$current` subscriptions
with coordinator-driven equivalents. Read `Atelier/Notch/
NotchController.swift` in full before starting; the goal is **identical
observable behavior**, generalized.

**Files:**
- Modify: `Atelier/Notch/NotchController.swift`
- Modify: `Atelier/UI/NotchRootView.swift` (swap the Task 4 stand-in
  `topContent` computed property for the real coordinator)

**Interfaces:**
- Consumes: `LiveActivityCoordinator` (Task 5),
  `NowPlayingLiveActivitySource` (Task 4).
- Produces: `NotchController` exposes `let liveActivityCoordinator:
  LiveActivityCoordinator` (so `NotchRootView` can be constructed with
  it) — matches the existing pattern of passing `nowPlayingCoordinator`
  into `NotchRootView`'s init.

- [ ] **Step 1: Add the coordinator and its source list to `NotchController`**

In `Atelier/Notch/NotchController.swift`, after the existing
`nowPlayingCoordinator` property (line 13):

```swift
    private let nowPlayingCoordinator = NowPlayingCoordinator()
    private let liveActivityCoordinator: LiveActivityCoordinator
```

Since `liveActivityCoordinator` needs `collapsedRect.height` (only known
inside `init`, after `NSScreen.notchedOrMain` resolves), initialize it
alongside `viewModel` in both branches of `init()`. For the no-notch
fallback branch (`guard let screen = NSScreen.notchedOrMain else { ... }`,
around line 47):

```swift
        guard let screen = NSScreen.notchedOrMain else {
            viewModel = NotchViewModel(collapsedSize: .zero, expandedSize: .zero, pillSize: .zero, peekSize: .zero)
            liveActivityCoordinator = LiveActivityCoordinator(sources: [
                NowPlayingLiveActivitySource(coordinator: nowPlayingCoordinator, notchHeight: 0)
            ])
            panel.contentView = ClickThroughHostingView(
                rootView: NotchRootView(
                    viewModel: viewModel,
                    nowPlaying: nowPlayingCoordinator,
                    liveActivity: liveActivityCoordinator
                )
            )
            return
        }
```

And after `collapsedRect` is computed (around line 56), before
`viewModel` is assigned:

```swift
        let collapsedRect = NotchGeometry.notchRect(for: metrics)
        liveActivityCoordinator = LiveActivityCoordinator(sources: [
            NowPlayingLiveActivitySource(coordinator: nowPlayingCoordinator, notchHeight: collapsedRect.height)
        ])
```

Update both `NotchRootView(...)` construction call sites (the fallback
above and the real one further down, around line 84) to pass
`liveActivity: liveActivityCoordinator`.

- [ ] **Step 2: Update `NotchRootView`'s init to take the coordinator**

In `Atelier/UI/NotchRootView.swift`, add the property and remove the
Task-4 stand-in:

```swift
struct NotchRootView: View {
    @ObservedObject var viewModel: NotchViewModel
    @ObservedObject var nowPlaying: NowPlayingCoordinator
    @ObservedObject var liveActivity: LiveActivityCoordinator
    @StateObject private var artworkColor = ArtworkColorLoader()
    ...
```

Delete the `topContent` computed property added in Task 4, and change
its two call sites (`.peeking`/`.pill` branches) from `topContent` to
`liveActivity.topContent`.

- [ ] **Step 3: Replace the direct now-playing subscriptions with coordinator-driven ones**

In `Atelier/Notch/NotchController.swift`, `isPlayingCancellable` and
`trackChangeCancellable` (the two `Combine` subscriptions built off
`nowPlayingCoordinator.$current`) are replaced with subscriptions to
`liveActivityCoordinator`. Everything else about `triggerPeek` and the
decay `Task` stays exactly as it was — only the two `Cancellable`
assignments and `lastTrackKey` change. Replace:

```swift
        isPlayingCancellable = nowPlayingCoordinator.$current
            .map { $0?.isPlaying ?? false }
            .removeDuplicates()
            .sink { [weak self] isPlaying in
                guard let self else { return }
                if AtelierSettings.peekOnTrackChangeEnabled {
                    triggerPeek(with: .playbackToggled)
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        viewModel.handle(.isPlayingChanged(isPlaying))
                    }
                }
            }
```

with:

```swift
        // Generalizes the old isPlaying signal to "does the stack have
        // any content at all" -- for now-playing that's still exactly
        // isPlaying, since NowPlayingLiveActivitySource only publishes
        // content while playing (Task 4). `removeDuplicates` preserves
        // the exact behavior the old `.map { isPlaying }.removeDuplicates()`
        // had: only fire on an actual true<->false transition.
        isPlayingCancellable = liveActivityCoordinator.$hasContent
            .removeDuplicates()
            .sink { [weak self] hasContent in
                guard let self else { return }
                if AtelierSettings.peekOnTrackChangeEnabled {
                    triggerPeek(with: .playbackToggled)
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        viewModel.handle(.isPlayingChanged(hasContent))
                    }
                }
            }
```

And replace:

```swift
        trackChangeCancellable = nowPlayingCoordinator.$current
            .compactMap { $0 }
            .sink { [weak self] info in
                let key = "\(info.title)|\(info.artist)"
                guard key != self?.lastTrackKey else { return }
                self?.lastTrackKey = key
                self?.triggerPeek(with: .trackChanged)
            }
```

with:

```swift
        // liveActivityCoordinator.identityChanged already dedups by
        // content id (Task 5) -- the old lastTrackKey bookkeeping lived
        // here only because that dedup didn't exist yet.
        trackChangeCancellable = liveActivityCoordinator.identityChanged
            .sink { [weak self] in
                self?.triggerPeek(with: .trackChanged)
            }
```

Remove the now-unused `private var lastTrackKey: String?` property.

- [ ] **Step 4: Update `triggerPeek`'s decay read**

`triggerPeek`'s decay `Task` reads `nowPlayingCoordinator.current?.isPlaying`
to resolve `.peekTimerElapsed(isPlaying:)`. Generalize the same way:

```swift
        peekDecayTask = Task { [weak self] in
            try? await Task.sleep(for: Self.peekDuration)
            guard !Task.isCancelled, let self else { return }
            let hasContent = liveActivityCoordinator.hasContent
            withAnimation(.spring(response: 0.55, dampingFraction: 0.92)) {
                viewModel.handle(.peekTimerElapsed(isPlaying: hasContent))
            }
        }
```

(Only the `let isPlaying = nowPlayingCoordinator.current?.isPlaying ?? false`
line changes to `let hasContent = liveActivityCoordinator.hasContent`,
and the argument label at the call site updates accordingly.)

- [ ] **Step 5: Build**

Run: `xcodebuild -scheme Atelier -configuration Debug build`
Expected: BUILD SUCCEEDED

- [ ] **Step 6: Run the full existing test suite**

Run: `xcodebuild test -scheme Atelier -destination 'platform=macOS'`
Expected: PASS, same count as before this task (this task touches no
`NotchState`/`NotchGeometry` logic, so `NotchStateTests`/
`NotchGeometryTests` must be unaffected).

- [ ] **Step 7: Manual on-device verification (must not regress)**

Run via `/build` with Spotify running:
- Play a track: pill appears with artwork+waveform.
- Skip to a new track: peek fires, shows the new track, decays back to
  pill after ~2.5s.
- Pause/resume: peek fires (if "Peek on Track Change" is on) or the pill
  ↔ collapsed transition happens directly (if off) — toggle the menu-bar
  setting and check both paths.
- Hover during pill/peek: expands to the full interactive player;
  releasing hover returns to pill/collapsed correctly.
This is the same checklist Phase 5 verified — confirm none of it broke.

- [ ] **Step 8: Commit**

```bash
git add Atelier/Notch/NotchController.swift Atelier/UI/NotchRootView.swift
git commit -m "$(cat <<'EOF'
feat: drive NotchController's peek/pill logic from LiveActivityCoordinator

Replaces the direct nowPlayingCoordinator.$current subscriptions with
coordinator-driven equivalents (hasContent generalizes isPlaying,
identityChanged generalizes the title|artist dedup key). NotchState's
event vocabulary is unchanged -- only what drives it is now generic.
Behavior verified identical on-device: pill/peek/decay/hover timing
unaffected.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_0124yKTWHuLdrDfjcebwgfwU
EOF
)"
```

---

## Task 7: `BatterySource` — pure threshold/formatting logic

**Files:**
- Create: `Atelier/Widgets/Battery/BatteryActivityState.swift`
- Test: `AtelierTests/BatteryActivityStateTests.swift`

**Interfaces:**
- Produces: `enum BatteryActivityState: Equatable` (`.charging`, `.low
  (percent: Int)`, `.full`) and `static func evaluate(percent: Int,
  isCharging: Bool, wasCharging: Bool) -> BatteryActivityState?` — pure,
  no `IOKit` import, unit-tested like `SpotifyOutputParser`.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
@testable import Atelier

struct BatteryActivityStateTests {
    @Test func justStartedChargingProducesChargingState() {
        let result = BatteryActivityState.evaluate(percent: 40, isCharging: true, wasCharging: false)
        #expect(result == .charging)
    }

    @Test func alreadyChargingProducesNoNewAlert() {
        let result = BatteryActivityState.evaluate(percent: 41, isCharging: true, wasCharging: true)
        #expect(result == nil)
    }

    @Test func lowBatteryUnplugged() {
        let result = BatteryActivityState.evaluate(percent: 20, isCharging: false, wasCharging: false)
        #expect(result == .low(percent: 20))
    }

    @Test func aboveLowThresholdProducesNoAlert() {
        let result = BatteryActivityState.evaluate(percent: 21, isCharging: false, wasCharging: false)
        #expect(result == nil)
    }

    @Test func fullWhilePluggedIn() {
        let result = BatteryActivityState.evaluate(percent: 100, isCharging: true, wasCharging: true)
        #expect(result == .full)
    }

    @Test func hundredPercentWhileUnpluggedIsNotFull() {
        let result = BatteryActivityState.evaluate(percent: 100, isCharging: false, wasCharging: false)
        #expect(result == nil)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme Atelier -destination 'platform=macOS' -only-testing:AtelierTests/BatteryActivityStateTests`
Expected: FAIL to build — type doesn't exist yet.

- [ ] **Step 3: Implement**

```swift
/// A battery condition worth surfacing in the notch. Pure -- no IOKit
/// import -- so the threshold logic is unit-testable independent of the
/// actual power-source polling in `BatterySource`.
enum BatteryActivityState: Equatable {
    case charging
    case low(percent: Int)
    case full

    private static let lowThreshold = 20

    /// `nil` means "nothing worth surfacing right now" -- this is what
    /// `BatterySource` publishes as its `LiveActivityContent?` when
    /// nothing has changed enough to matter.
    static func evaluate(percent: Int, isCharging: Bool, wasCharging: Bool) -> BatteryActivityState? {
        if isCharging && !wasCharging {
            return .charging
        }
        if isCharging && percent >= 100 {
            return .full
        }
        if !isCharging && percent <= lowThreshold {
            return .low(percent: percent)
        }
        return nil
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme Atelier -destination 'platform=macOS' -only-testing:AtelierTests/BatteryActivityStateTests`
Expected: PASS (all 6 tests)

- [ ] **Step 5: Commit**

```bash
git add Atelier/Widgets/Battery/BatteryActivityState.swift AtelierTests/BatteryActivityStateTests.swift
git commit -m "$(cat <<'EOF'
feat: add pure BatteryActivityState threshold logic

charging/low/full detection, unit-tested independent of the actual
IOKit polling that will drive it (next task) -- same split
SpotifyOutputParser uses for its parsing logic.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_0124yKTWHuLdrDfjcebwgfwU
EOF
)"
```

---

## Task 8: `BatterySource` + `BatteryLiveActivityView`, wired in

**Files:**
- Create: `Atelier/Widgets/Battery/BatterySource.swift`
- Create: `Atelier/Widgets/Battery/BatteryActivityContent.swift`
- Modify: `Atelier/Notch/NotchController.swift` (register the new source)

**Interfaces:**
- Consumes: `BatteryActivityState` (Task 7), `LiveActivitySource`/
  `LiveActivityContent` (Task 2).
- Produces: `final class BatterySource: LiveActivitySource` (id
  `"battery"`, priority `NotchLiveActivityPriority.battery`, defined as
  `5` — below now-playing's `10`, so music never gets displaced by a
  battery blip), `struct BatteryActivityContent: LiveActivityContent`.

`IOKit.ps` polling itself is manual-verification, same treatment as
`AppleScriptRunner` — there's no meaningful way to unit test a live
power-source read.

- [ ] **Step 1: Add the priority constant**

In `Atelier/NowPlaying/NowPlayingLiveActivitySource.swift`'s
`NotchLiveActivityPriority` enum, replace the placeholder comment:

```swift
enum NotchLiveActivityPriority {
    static let nowPlaying = 10
    static let battery = 5
}
```

- [ ] **Step 2: Write `BatterySource`**

```swift
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
```

- [ ] **Step 3: Write `BatteryActivityContent` + its pill/peek views**

```swift
import SwiftUI

struct BatteryActivityContent: LiveActivityContent {
    let state: BatteryActivityState

    var id: String {
        switch state {
        case .charging: "battery:charging"
        case .low(let percent): "battery:low:\(percent)"
        case .full: "battery:full"
        }
    }

    private var symbolName: String {
        switch state {
        case .charging: "bolt.fill"
        case .low: "battery.25"
        case .full: "battery.100"
        }
    }

    private var tint: Color {
        switch state {
        case .charging: .green
        case .low: .red
        case .full: .green
        }
    }

    private var label: String {
        switch state {
        case .charging: "Charging"
        case .low(let percent): "Battery Low  \(percent)%"
        case .full: "Full Battery"
        }
    }

    func pillView() -> AnyView {
        AnyView(
            Image(systemName: symbolName)
                .foregroundStyle(tint)
                .font(.system(size: 12))
                .padding(.horizontal, 6)
        )
    }

    func peekView() -> AnyView {
        AnyView(
            HStack(spacing: 8) {
                Image(systemName: symbolName)
                    .foregroundStyle(tint)
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 9)
        )
    }
}
```

- [ ] **Step 4: Register `BatterySource` in `NotchController`**

In both `LiveActivityCoordinator(sources: [...])` call sites added in
Task 6, add `BatterySource()` to the array:

```swift
        liveActivityCoordinator = LiveActivityCoordinator(sources: [
            NowPlayingLiveActivitySource(coordinator: nowPlayingCoordinator, notchHeight: collapsedRect.height),
            BatterySource()
        ])
```

- [ ] **Step 5: Build**

Run: `xcodebuild -scheme Atelier -configuration Debug build`
Expected: BUILD SUCCEEDED

- [ ] **Step 6: Run the full test suite**

Run: `xcodebuild test -scheme Atelier -destination 'platform=macOS'`
Expected: PASS

- [ ] **Step 7: Manual on-device verification**

Plug/unplug the charger and (carefully, don't actually run the battery
down just for this) note the console/UI when capacity is near the 20%
threshold if it happens to already be low. At minimum: confirm plugging
in fires a peek showing "Charging," and it doesn't fire repeatedly every
poll while still charging (only once, on the false→true transition,
matching `BatteryActivityStateTests.alreadyChargingProducesNoNewAlert`).

- [ ] **Step 8: Commit**

```bash
git add Atelier/Widgets/Battery/BatterySource.swift \
        Atelier/Widgets/Battery/BatteryActivityContent.swift \
        Atelier/NowPlaying/NowPlayingLiveActivitySource.swift \
        Atelier/Notch/NotchController.swift
git commit -m "$(cat <<'EOF'
feat: add Battery live activity, first non-now-playing widget

Proves the LiveActivitySource/LiveActivityContent seam: BatterySource
polls IOKit.ps (public API), BatteryActivityContent renders charging/
low/full through the same pillView()/peekView() protocol now-playing
uses. Lower priority than now-playing so it never displaces the
current track.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_0124yKTWHuLdrDfjcebwgfwU
EOF
)"
```

---

## Task 9: AirPods classification — pure logic

**Files:**
- Create: `Atelier/Widgets/AirPods/AirPodsKind.swift`
- Test: `AtelierTests/AirPodsKindTests.swift`

**Interfaces:**
- Produces: `enum AirPodsKind: Equatable` (`.pro`, `.max`, `.basic`,
  `.legacy`) and `static func classify(vendorID: UInt16?, productID:
  UInt16?, name: String) -> AirPodsKind?` — pure, no `IOBluetooth`
  import.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
@testable import Atelier

struct AirPodsKindTests {
    @Test func recognizesProByAppleProductID() {
        let result = AirPodsKind.classify(vendorID: 0x004C, productID: 0x200E, name: "AirPods Pro")
        #expect(result == .pro)
    }

    @Test func recognizesMaxByAppleProductID() {
        let result = AirPodsKind.classify(vendorID: 0x004C, productID: 0x200A, name: "AirPods Max")
        #expect(result == .max)
    }

    @Test func fallsBackToNameWhenIDsUnavailable() {
        let result = AirPodsKind.classify(vendorID: nil, productID: nil, name: "Alicia's AirPods Pro")
        #expect(result == .pro)
    }

    @Test func nonAppleVendorIsNotAirPods() {
        let result = AirPodsKind.classify(vendorID: 0x1234, productID: 0x200E, name: "Some Headphones")
        #expect(result == nil)
    }

    @Test func unrelatedDeviceNameIsNotAirPods() {
        let result = AirPodsKind.classify(vendorID: nil, productID: nil, name: "Magic Keyboard")
        #expect(result == nil)
    }

    @Test func genericAirPodsNameFallsBackToLegacy() {
        let result = AirPodsKind.classify(vendorID: nil, productID: nil, name: "AirPods")
        #expect(result == .legacy)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme Atelier -destination 'platform=macOS' -only-testing:AtelierTests/AirPodsKindTests`
Expected: FAIL to build — type doesn't exist yet.

- [ ] **Step 3: Implement**

Classification order adapted from Clayton630/QuartzNotch's
`BluetoothActivityManager` (`airPodsKindFromApplePID` /
`airPodsKindFromName`), read via `gh api` before designing — simplified
to the four kinds Atelier actually renders differently (basic and legacy
render identically in `AirPodsActivityContent`, Task 10, so they're kept
distinct here only because the reference app's PID table already
distinguishes them cheaply).

```swift
/// Pure AirPods model classification -- no IOBluetooth import, so it's
/// unit-testable against fixture vendor/product IDs without a real
/// device connected.
enum AirPodsKind: Equatable {
    case pro, max, basic, legacy

    private static let appleVendorID: UInt16 = 0x004C

    static func classify(vendorID: UInt16?, productID: UInt16?, name: String) -> AirPodsKind? {
        if let vendorID, vendorID == appleVendorID, let productID {
            switch productID {
            case 0x200E, 0x2014, 0x2024: return .pro
            case 0x200A: return .max
            case 0x2013, 0x2019, 0x201B: return .basic
            case 0x2002, 0x200F: return .legacy
            default: break
            }
        }

        let normalized = name.lowercased()
        guard normalized.contains("airpods") else { return nil }
        if normalized.contains("pro") { return .pro }
        if normalized.contains("max") { return .max }
        return .legacy
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme Atelier -destination 'platform=macOS' -only-testing:AtelierTests/AirPodsKindTests`
Expected: PASS (all 6 tests)

- [ ] **Step 5: Commit**

```bash
git add Atelier/Widgets/AirPods/AirPodsKind.swift AtelierTests/AirPodsKindTests.swift
git commit -m "$(cat <<'EOF'
feat: add pure AirPods model classification

VID/PID-first, name-fallback, adapted from QuartzNotch's
BluetoothActivityManager (read via gh api first). Unit-tested against
fixture IDs -- no IOBluetooth import, no real device needed to test.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_0124yKTWHuLdrDfjcebwgfwU
EOF
)"
```

---

## Task 10: `AirPodsSource` + battery-percentage helper + wiring

**Files:**
- Create: `Atelier/Widgets/AirPods/AirPodsSource.swift`
- Create: `Atelier/Widgets/AirPods/AirPodsBatteryReader.swift`
- Create: `Atelier/Widgets/AirPods/AirPodsActivityContent.swift`
- Modify: `Atelier/NowPlaying/NowPlayingLiveActivitySource.swift`
  (add the priority constant)
- Modify: `Atelier/Notch/NotchController.swift` (register the source)

**Interfaces:**
- Consumes: `AirPodsKind` (Task 9), `LiveActivitySource`/
  `LiveActivityContent` (Task 2).
- Produces: `final class AirPodsSource: LiveActivitySource` (id
  `"airpods"`, priority `NotchLiveActivityPriority.airpods = 6` — above
  battery, since a just-connected headphone is more immediately relevant
  than an ambient battery state, below now-playing), `enum
  AirPodsBatteryReader` with `static func percent(for device:
  IOBluetoothDevice) -> Int?`.

Connection detection is manual-verification (needs real hardware, and
the user doesn't have their AirPods on hand right now per this session —
verify this task once they do). The battery-percentage helper is
isolated specifically so a future macOS update breaking its undocumented
key only touches this one file.

- [ ] **Step 1: Add the priority constant**

```swift
enum NotchLiveActivityPriority {
    static let nowPlaying = 10
    static let airpods = 6
    static let battery = 5
}
```

- [ ] **Step 2: Write `AirPodsBatteryReader`, isolated per the design spec**

```swift
import IOBluetooth

/// AirPods battery percentage via an undocumented `IOBluetoothDevice`
/// key -- no stability guarantee across macOS versions. Isolated to this
/// one file (per the design spec's decision) so a future OS update
/// breaking it only touches here; `AirPodsSource` treats a `nil` result
/// as "no percentage available," not an error.
enum AirPodsBatteryReader {
    static func percent(for device: IOBluetoothDevice) -> Int? {
        guard let value = device.value(forKey: "batteryPercentCombined") as? NSNumber else {
            return nil
        }
        return value.intValue
    }
}
```

- [ ] **Step 3: Write `AirPodsSource`**

```swift
import Combine
import Foundation
import IOBluetooth

/// Detects AirPods connect/disconnect via `IOBluetoothDevice`'s public
/// connect-notification API -- adapted from Clayton630/QuartzNotch's
/// `BluetoothActivityManager`, read via `gh api` before designing (see
/// check-reference-apps-first). Classification is `AirPodsKind.classify`
/// (Task 9); battery percentage is best-effort via
/// `AirPodsBatteryReader` and omitted from the content when unavailable.
final class AirPodsSource: LiveActivitySource {
    let id = "airpods"
    let priority = NotchLiveActivityPriority.airpods

    private let subject = CurrentValueSubject<LiveActivityContent?, Never>(nil)
    private var connectNotification: IOBluetoothUserNotification?
    private var disconnectNotification: IOBluetoothUserNotification?

    var contentPublisher: AnyPublisher<LiveActivityContent?, Never> {
        subject.eraseToAnyPublisher()
    }

    init() {
        connectNotification = IOBluetoothDevice.register(
            forConnectNotifications: self,
            selector: #selector(deviceConnected(_:device:))
        )
    }

    deinit {
        connectNotification?.unregister()
        disconnectNotification?.unregister()
    }

    @objc private func deviceConnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        let name = device.name ?? ""
        let vendorID = (device.value(forKey: "vendorID") as? NSNumber)?.uint16Value
        let productID = (device.value(forKey: "productID") as? NSNumber)?.uint16Value

        guard let kind = AirPodsKind.classify(vendorID: vendorID, productID: productID, name: name) else {
            return
        }

        let percent = AirPodsBatteryReader.percent(for: device)
        subject.send(AirPodsActivityContent(kind: kind, percent: percent))

        disconnectNotification = device.register(
            forDisconnectNotification: self,
            selector: #selector(deviceDisconnected(_:device:))
        )
    }

    @objc private func deviceDisconnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        subject.send(nil)
        disconnectNotification?.unregister()
        disconnectNotification = nil
    }
}
```

- [ ] **Step 4: Write `AirPodsActivityContent`**

```swift
import SwiftUI

struct AirPodsActivityContent: LiveActivityContent {
    let kind: AirPodsKind
    let percent: Int?

    var id: String { "airpods:\(kind)" }

    private var name: String {
        switch kind {
        case .pro: "AirPods Pro"
        case .max: "AirPods Max"
        case .basic: "AirPods"
        case .legacy: "AirPods"
        }
    }

    func pillView() -> AnyView {
        AnyView(
            Image(systemName: "airpods")
                .foregroundStyle(.white)
                .font(.system(size: 12))
                .padding(.horizontal, 6)
        )
    }

    func peekView() -> AnyView {
        AnyView(
            HStack(spacing: 8) {
                Image(systemName: "airpods")
                    .foregroundStyle(.white)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Connected").font(.caption).foregroundStyle(.white.opacity(0.65))
                    Text(name).font(.subheadline).foregroundStyle(.white)
                }
                if let percent {
                    Spacer(minLength: 0)
                    Text("\(percent)%").font(.subheadline).foregroundStyle(.green)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 9)
        )
    }
}
```

- [ ] **Step 5: Register `AirPodsSource` in `NotchController`**

```swift
        liveActivityCoordinator = LiveActivityCoordinator(sources: [
            NowPlayingLiveActivitySource(coordinator: nowPlayingCoordinator, notchHeight: collapsedRect.height),
            BatterySource(),
            AirPodsSource()
        ])
```

- [ ] **Step 6: Build**

Run: `xcodebuild -scheme Atelier -configuration Debug build`
Expected: BUILD SUCCEEDED

- [ ] **Step 7: Run the full test suite**

Run: `xcodebuild test -scheme Atelier -destination 'platform=macOS'`
Expected: PASS

- [ ] **Step 8: Manual on-device verification — deferred**

Requires real AirPods, which the user doesn't have on hand this session.
**Do not mark this task's on-device check complete until verified**:
connect AirPods, confirm a peek fires showing the correct model name; if
`percent` comes back nil, confirm the peek still renders correctly
without a percentage (no blank space or crash) rather than assuming the
undocumented key works.

- [ ] **Step 9: Commit**

```bash
git add Atelier/Widgets/AirPods/ \
        Atelier/NowPlaying/NowPlayingLiveActivitySource.swift \
        Atelier/Notch/NotchController.swift
git commit -m "$(cat <<'EOF'
feat: add AirPods live activity (connection status + best-effort battery %)

AirPodsSource detects connect/disconnect via IOBluetooth's public
connect-notification API; classification via AirPodsKind (Task 9).
Battery percentage reads an undocumented IOBluetoothDevice key,
isolated in AirPodsBatteryReader so a future macOS break only touches
that file -- the widget degrades to connection-status-only if it
returns nil. On-device verification deferred: no AirPods on hand this
session.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_0124yKTWHuLdrDfjcebwgfwU
EOF
)"
```

---

## Task 11: ROADMAP.md update

**Files:**
- Modify: `docs/ROADMAP.md`

- [ ] **Step 1: Update Phase 6's checklist and the "Where we are" summary**

Check off Phase 6's items in `docs/ROADMAP.md` (the
`check-reference-apps-first` spike, generalizing `NotchState`'s
mechanism, defining the protocol) and add the two shipped widgets plus
the pill-content addition as extras, following the existing style used
for Phase 5's entries (see the "Extra, ahead of Phase 6" /
"Extra, beyond the original checklist" bullets already there). Note
explicitly that AirPods on-device verification is deferred pending
hardware, matching how Phase 5's hover-holds-open gap was recorded.
Update "Where we are" to point at Phase 7 or whichever phase is next.

- [ ] **Step 2: Commit**

```bash
git add docs/ROADMAP.md
git commit -m "$(cat <<'EOF'
docs: sync ROADMAP.md with Phase 6's Live Activity architecture

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_0124yKTWHuLdrDfjcebwgfwU
EOF
)"
```

---

## Self-Review Notes

- **Spec coverage:** `LiveActivityStack` (Task 1), `LiveActivitySource`/
  `LiveActivityContent` (Task 2), resting-pill content addendum (Task 3),
  now-playing wrapped without rewriting `NowPlayingCoordinator` (Task 4),
  `LiveActivityCoordinator` (Task 5), `NotchState` left untouched with
  wiring generalized at the coordinator layer (Task 6), Battery widget
  (Tasks 7-8), AirPods widget with isolated battery-percentage helper
  (Tasks 9-10, ordered after Battery per the user's explicit request), doc
  sync (Task 11). All spec sections have a task.
- **Deviation from spec, called out explicitly:** the spec's protocol
  sketch used a single `expandedView()`; this plan splits pill/peek only
  (`pillView()`/`peekView()`) and leaves `.expanded` hardcoded to
  now-playing via `isExpandable`, since only now-playing has interactive
  transport controls to expand into — battery/AirPods are pill/peek-only
  in both reference images. This is a refinement discovered while mapping
  the spec onto `NotchRootView`'s actual structure, not a scope cut.
