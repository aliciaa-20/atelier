# Tabbed navigation + idle Home — design

**Status:** approved, not yet implemented.

Two related feature ideas, brainstormed together because the idle-state
question turned out to be what the Home tab shows, not a separate feature:

1. **Tabbed page navigation** inside the expanded notch (Home / Shelf), first
   flagged as a backlog item in `docs/FEATURES.md` (§ "Tabbed page
   navigation") after a user-requested reference screenshot on 2026-09-13,
   and deliberately queued until after the file shelf sub-project shipped.
2. **Idle Home content** — what the Home tab shows when nothing is playing.

## Goal

Right now `NotchState` treats `.expanded` (now-playing) and `.shelf`
(drag-triggered) as mutually exclusive single states — there's no way to
manually switch to the shelf while hovering, only by dragging a file onto
the notch. And when nothing is playing, hovering the notch shows nothing
useful — the expanded player has no content to show.

This adds a small Home/Shelf tab switcher to the expanded notch, and gives
the Home tab a real idle state (date/time + battery %) instead of nothing.

## Reference apps

Per `check-reference-apps-first`, three repos checked; findings below.

- [TheBoredTeam/boring.notch](https://github.com/TheBoredTeam/boring.notch) —
  `components/Tabs/TabSelectionView.swift` + `TabButton.swift` is the pattern
  this design adopts: a `TabModel` array driving a capsule-style segmented
  control with a `matchedGeometryEffect` sliding highlight, backed by a
  plain `@Published currentView` property on a coordinator — entirely
  orthogonal to their own hover/notch-state machine. Their `NotchHomeView`
  does **not** have a distinct idle state: `MusicPlayerView` renders
  unconditionally, just visually muted (dimmed artwork, scaled down) when
  `!isPlaying`, with an optional inline `CalendarView`/camera mirror shown
  alongside it (gated by settings, not by tabs).
- [Ebullioscopic/Atoll](https://github.com/Ebullioscopic/Atoll) —
  `components/EmptyState.swift` is a simple placeholder (gray music-note
  icon + a message like "Play some music babies"), still music-specific,
  not a general idle dashboard.
- [monuk7735/mew-notch](https://github.com/monuk7735/mew-notch) —
  `Utils/DateUtils.swift` is a small reusable `DateFormatter` wrapper,
  useful as a pattern for this design's date/time formatting. Its
  `NotchHomeView` renders a `.Placeholder` now-playing model when idle
  rather than a distinct clock/battery widget.

**Explicitly not found in any reference app:** a combined clock + battery
idle widget. This part of the design has no existing pattern to adapt —
it's new for Atelier.

## Page architecture

`NotchViewModel` (not the pure `NotchStateMachine`) gains:

```swift
enum NotchPage: Equatable {
    case home
    case shelf
}
```

`NotchPage` is pure (Foundation only) but does **not** live inside the
`NotchState`/`NotchStateMachine` reducer — folding pages into `NotchState`
itself (`.expandedHome`, `.expandedShelf`, ...) was considered and rejected:
it would duplicate every hover/peek transition per page and bloat the
reducer for no real benefit. Keeping `currentPage` orthogonal, the way
boring.notch's `currentView` is orthogonal to its own notch-state machine,
is the simpler fit.

`NotchViewModel` adds:
```swift
@Published private(set) var currentPage: NotchPage = .home
```

A pure helper (Foundation only, unit-tested like the rest of the reducer
layer) decides the page for a given transition:

```swift
enum NotchPageTransition {
    /// `state` is the *new* NotchState after NotchStateMachine.reduce.
    /// `currentPage` is the page before this transition.
    static func page(for state: NotchState, currentPage: NotchPage) -> NotchPage {
        switch state {
        case .shelf:
            return .shelf
        case .collapsed, .pill:
            return .home   // reset for next time the notch opens
        case .expanded, .peeking:
            return currentPage   // manual tab selection persists across peeks/hovers
        }
    }
}
```

- Dragging a file onto the notch still force-switches to `.shelf`, matching
  today's behavior exactly.
- Returning to `.collapsed`/`.pill` resets to `.home`, so the notch always
  opens on Home next time rather than remembering a stale Shelf selection.
- A manual tab tap while `.expanded` calls a new `NotchViewModel.selectPage(_:)`
  directly (bypassing the transition helper — it's a UI action, not a state
  transition) and simply sets `currentPage`.

`NotchController` calls `NotchPageTransition.page(for:currentPage:)` in the
same place it already drives `state` from `NotchStateMachine.reduce`,
passing the result into `NotchViewModel.currentPage`.

## Tab bar UI

New `Atelier/UI/NotchTabBar.swift`, adapted from boring.notch's
`TabSelectionView`/`TabButton` with credit — a two-item (Home, Shelf)
capsule segmented control with a sliding highlight
(`matchedGeometryEffect`), shown only while `state == .expanded` (not during
`.peeking` — a peek is a passive preview, not an interactive mode; showing
tab controls during a decaying peek invites a click that reopens the panel
via `hoverStarted` in a confusing way).

Wired to `viewModel.currentPage` / `viewModel.selectPage(_:)`.

## Idle Home content

New `Atelier/UI/IdleHomeView.swift`, shown by the existing expanded-content
container when `currentPage == .home` and nothing is playing (i.e. today's
"nothing to show" branch gets real content instead of empty space). Shows:

- **Date/time** — a small formatted string (e.g. `"3:45 PM · Fri, Sep 19"`),
  updated on a `Timer`/`TimelineView` tick, using a small new date-formatting
  helper in the same spirit as mew-notch's `DateUtils` (credited, not
  copied — Atelier's needs are simpler, a single format string).
- **Battery percentage** — always shown, not gated behind the
  charging/low/full thresholds `BatterySource`'s existing
  `BatteryActivityState.evaluate` uses for its ambient pill content.

### Battery percent: a second publisher, not a second reader

`BatterySource`'s `LiveActivityContent` publisher intentionally only emits
on `.charging`/`.low`/`.full` (see `BatteryActivityState`'s doc comment) —
reusing it as-is for the idle view would mean blank most of the time.
Rather than duplicating the `IOKit.ps` percent-reading logic in a second
place (which would fork "how do we read the battery" into two paths that
could drift), `BatterySource` gains a second, always-on publisher:

```swift
var currentPercentPublisher: AnyPublisher<Int, Never> { ... }
```

fed by the same `IOPSNotificationCreateRunLoopSource` callback and
`IOKit.ps` read `BatterySource` already does for its ambient content — one
IOKit read, two publishers downstream. `IdleHomeView` observes
`currentPercentPublisher` directly; it does not go through
`LiveActivityCoordinator` at all, since idle Home isn't a pill/peek content
source, it's a page's own view.

## Error handling

No new failure modes: date/time formatting can't fail, and the battery
percent publisher reuses `BatterySource`'s existing IOKit read path
(already handles the "no battery" case on a desktop Mac, though this
machine has one — not exercised, same as today).

## Testing

- `NotchPageTransition.page(for:currentPage:)` is pure Foundation — gets a
  `NotchPageTransitionTests` suite alongside the existing
  `NotchStateMachineTests`, covering: drag-in forces `.shelf` regardless of
  prior page, collapse/pill resets to `.home`, expanded/peeking preserves
  the current page.
- `NotchTabBar`, `IdleHomeView`, and the battery-percent wiring are
  manual-verification-only, same treatment as the rest of `UI/*.swift` and
  `Widgets/*/*.swift` (per `CLAUDE.md`'s Testing section) — say so plainly
  in `docs/ROADMAP.md` rather than claiming coverage that doesn't exist.

## Out of scope (this spec)

- Any third tab beyond Home/Shelf (a future Clipboard/History tab, per the
  original `FEATURES.md` note, is a separate design pass when actually
  built).
- Calendar/camera-mirror-style companion widgets inline with Home (Phase 14
  backlog, unrelated to this).
- Any change to `.peeking`'s existing decay/timer behavior.
