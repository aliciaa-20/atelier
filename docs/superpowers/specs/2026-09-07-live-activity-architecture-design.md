# Phase 6 — Live Activity / widget architecture

## Context

Atelier v1 (Phases 0–5) hardcodes the notch's peek/pill mechanism to one
content type: Spotify now-playing. The roadmap's Phase 6 calls for
generalizing that into an extensible concept so later phases (battery/volume
HUDs, file shelf, system alerts, lock-screen widget) plug into a shared
seam instead of each bolting a new surface onto `NotchState` directly. See
[FEATURES.md §5](../../FEATURES.md#5-live-activities--system-alerts-extensible-framework).

This design was prompted by two shipped reference apps the user pointed at
directly: [jackson-storm/dynamicnotch](https://github.com/jackson-storm/dynamicnotch)
(protocol-driven content + a priority-ranked activity stack) and
[Clayton630/QuartzNotch](https://github.com/Clayton630/QuartzNotch) (a
boring.notch fork with per-signal "managers" feeding one shared view model).
Both were read directly via `gh api` per `check-reference-apps-first`
before designing (not reasoned about from memory/screenshots).

**Reference architectures, compared:**

- **DynamicNotch**: a `NotchContentProtocol` (id, priority, per-content
  `size()`/`cornerRadius()`/`makeView()`) plus a `NotchEngine` that keeps a
  priority-sorted stack of active "live activities," distinguishes
  short-lived "temporary notifications" (auto-dismissing) from persistent
  ones, and queues state transitions through an async `Task`-based pipeline
  so they don't stomp each other mid-animation. Built for dozens of
  simultaneous system signals with a user-configurable priority table.
- **QuartzNotch**: no shared protocol. Each system signal
  (`BatteryActivityManager`, `BluetoothActivityManager`, ...) is its own
  manager publishing into one `QuartzViewModel`; every new activity type
  touches that shared view model directly.

**Decision:** borrow DynamicNotch's protocol shape (it matches Atelier's
existing `NowPlayingSource` seam — a new source shouldn't require touching
files outside its own), but not its full engine. QuartzNotch's
everything-touches-one-view-model pattern is exactly what the
`NowPlayingSource` seam was designed to avoid, so it's not adopted at all.
Build a middle ground: the multi-activity **data structure** now (a
priority-sorted list, so a 2nd/3rd widget type doesn't force a rewrite of
the first), but skip the queueing engine, the temporary-vs-persistent
notification split, and dismiss/restore history — nothing in Atelier needs
that complexity yet, and it's straightforward to add later once a real
widget needs it. (User confirmed this scope explicitly over the
full-engine alternative.)

**Also decided:** Phase 6 is not architecture-only as originally scoped on
the roadmap — it includes two new widgets to prove the protocol works for
something other than now-playing: **Battery**, then **AirPods** (in that
order — the user doesn't have AirPods on hand to test right now).

## Non-goals

- Priority *table* / user-configurable priority settings (DynamicNotch has
  a Settings UI for this). Priorities are fixed constants for now.
- Temporary-notification-vs-live-activity distinction, dismiss/restore
  history, async transition queueing.
- Volume/brightness HUD, timer, wifi, file shelf, lock-screen widget — later
  phases (7–11 per the roadmap), each building on this seam.
- AirPods per-bud battery percentage as a hard requirement — see the
  AirPods section below.

## Architecture

```
NotchController ──owns── NotchPanel
        │                    │
        │                    └── NotchRootView (SwiftUI)
        │                          ├── CollapsedPillView
        │                          ├── PeekPlayerView / PeekBatteryView / ...
        │                          └── ExpandedPlayerView / ExpandedBatteryView / ...
        │
        ├── NotchGeometry        (pure)                          ← unit tested
        ├── NotchState           (pure: peek/pill/expand machine) ← unit tested
        ├── LiveActivityStack    (pure: priority-sorted list)     ← unit tested
        │
        └── LiveActivityCoordinator
              └── [LiveActivitySource]
                    ├── NowPlayingCoordinator (existing, wrapped)
                    ├── BatterySource
                    └── (Battery done →) AirPodsSource
```

### `LiveActivitySource` — the data seam

Mirrors `NowPlayingSource`'s shape: one file per source, no changes
elsewhere to add a new one.

```swift
protocol LiveActivitySource {
    var id: String { get }
    var priority: Int { get }
    var contentPublisher: AnyPublisher<LiveActivityContent?, Never> { get }
}
```

`nil` from the publisher means "this source has nothing to show right now"
(e.g. battery not low/charging, AirPods disconnected) — it does not mean
"remove the source," it means "this source currently contributes nothing to
the stack."

### `LiveActivityContent` — the UI seam

A separate protocol (UI layer — may import SwiftUI, unlike the pure layer
above). Shape borrowed from DynamicNotch's `NotchContentProtocol`, credited
in a source comment:

```swift
protocol LiveActivityContent: Identifiable {
    var id: String { get }
    @ViewBuilder func pillView() -> AnyView
    @ViewBuilder func expandedView() -> AnyView
}
```

Each widget's SwiftUI view lives next to its source
(`Widgets/Battery/BatteryLiveActivityView.swift`, etc.), following the
existing convention of colocating a data type with its presentation.

### `LiveActivityStack` — pure, unit-tested

Foundation only, no AppKit/SwiftUI — same invariant as `NotchGeometry` and
`NotchState`. Holds active `(id, priority)` summaries (not full content —
content flows separately through the coordinator), sorted by priority
descending, ties broken by insertion order. Exposes:

```swift
struct LiveActivityStack: Equatable {
    private(set) var activeIDs: [(id: String, priority: Int)] = []
    var topID: String? { activeIDs.first?.id }

    mutating func upsert(id: String, priority: Int)
    mutating func remove(id: String)
}
```

`NotchState`'s peek/pill/expand transitions become driven by "the stack's
top changed" rather than Spotify-specific `trackChanged`/`playbackToggled`
events — those become one specific producer of stack changes rather than
`NotchState`'s only vocabulary. This is the generalization the roadmap
asks for, kept inside the existing pure-layer invariant.

### `LiveActivityCoordinator`

AppKit/Combine layer, parallel to the existing `NowPlayingCoordinator`.
Owns the list of `LiveActivitySource`s, subscribes to each
`contentPublisher`, maintains the `LiveActivityStack`, and drives
`NotchState` + hands the top content's `LiveActivityContent` to the UI
layer for rendering. `NowPlayingCoordinator` becomes one source wrapped to
conform to `LiveActivitySource` rather than being special-cased.

## Battery widget (first)

`BatterySource` polls via `IOPSNotificationCreateRunLoopSource` +
`IOPSCopyPowerSourcesInfo` (`IOKit.ps`, public API, no entitlement) —
adapted from QuartzNotch's `BatteryActivityManager`, credited in a source
comment. Publishes content only when charging just started, battery is low
(a fixed threshold, e.g. ≤20%), or battery just reached 100% while
plugged in — matching the reference images (Charging / Battery Low /
Full Battery). Formatting/threshold logic (what counts as "low," charging
label text) is pure and unit-tested the same way `SpotifyOutputParser` is.

## AirPods widget (second)

`AirPodsSource` detects connect/disconnect via `IOBluetooth`'s
`IOBluetoothDevice.register(forConnectNotifications:)`, classifying the
device (Pro/Max/basic/legacy) via Apple's Bluetooth vendor/product ID —
adapted from QuartzNotch's `BluetoothActivityManager`, credited in a source
comment. Both are public-ish, stable APIs.

**Battery percentage** (shown in the reference image) requires an
undocumented `IOBluetoothDevice` key with no stability guarantee across
macOS versions. Decision: build it, but isolate it behind one small
internal helper (`AirPodsBatteryReader.swift`) so a future macOS update
breaking it only touches that file; the widget ships and reads correctly
without a percentage if the key returns nothing (connection status alone
still renders).

Since the user doesn't have AirPods on hand right now, this widget is
built second and its on-device verification is deferred until they do.

## Testing

- `LiveActivityStackTests` — priority ordering, upsert/replace-by-id,
  remove, ties.
- `NotchStateTests` — extend existing tests to cover stack-driven
  transitions instead of (or alongside) the Spotify-specific events.
- `BatterySourceTests` (or similar) — pure threshold/formatting logic only;
  the actual `IOKit.ps` calls are manual-verification, same treatment as
  `AppleScriptRunner`.
- AirPods: connection/classification logic testable against fixture
  vendor/product IDs; the battery-percentage helper is manual-verification
  only, explicitly documented as such (no fabricated coverage).

## Migration

Existing pill/peek/expanded now-playing behavior must not regress.
`NowPlayingCoordinator` gets wrapped as a `LiveActivitySource` rather than
rewritten; its existing tests continue to apply to the wrapped behavior.
