# File shelf — design

**Status:** approved, not yet implemented.
**Sub-project 1 of 3** under Phase 9 (`docs/ROADMAP.md`). AirDrop integration
and a file format converter are separate sub-projects, each depending on
this one existing first, each getting its own design/spec/plan pass later.

## Goal

Drag a file onto the notch; it lands in a small persistent shelf you can
drag back out to Finder or another app, later. This is Atelier's first
interaction trigger that isn't hover-driven, and its first feature that
touches the filesystem beyond reading (Spotify's AppleScript output,
`IOKit.ps`, private HUD symbols) — it writes and owns files.

## Reference apps

Per `check-reference-apps-first`:
- [Lakr233/NotchDrop](https://github.com/Lakr233/NotchDrop) — `TrayDrop.swift`
  (drop-item model, copy-to-storage, expiry) is the closest match to this
  app's scope: a single-purpose shelf, not a whole file-manager. Its
  `OrderedSet<DropItem>` (from Apple's `swift-collections` package) is
  **not** adopted — `CLAUDE.md`'s no-third-party-dependencies rule means a
  plain `[ShelfItem]` array instead; a manual dedup-by-id check on insert
  gets the same behavior without the package.
- [TheBoredTeam/boring.notch](https://github.com/TheBoredTeam/boring.notch) —
  `observers/DragDetector.swift` is the drag-detection mechanism actually
  adopted here (see below); its own `components/Shelf/` is a much larger
  system (thumbnails, Quick Look, Quick Share, per-item view models) that
  this design deliberately does not match in scope — YAGNI for a personal
  single-user app.

## Detection

New `Notch/NotchDragDetector.swift`, AppKit-side, mirroring the boundary
`NotchGestureModifier`/`NotchGestureInterpreter` already establish
(Invariant 8): AppKit reads raw `NSEvent`s and translates them into a small
vocabulary before crossing into anything else.

Adapted from `boring.notch`'s `DragDetector`: global `NSEvent` monitors on
`.leftMouseDown`/`.leftMouseDragged`/`.leftMouseUp` (mouse-event global
monitors do **not** require Accessibility permission — only keyboard-event
global monitors do, so this needs no new TCC grant). On mouse-down, snapshot
`NSPasteboard(name: .drag)`'s `changeCount`; on drag, a changed count means
real content enter the drag (as opposed to a plain click-drag with nothing
attached). While content is dragging, compare `NSEvent.mouseLocation`
against the notch's screen rect (`NotchGeometry`/`ScreenMetrics`, already
computed) to report region-entered/exited. `.leftMouseUp` while inside the
region completes the drop; ending outside cancels it.

Reports exactly three events to `NotchController`: `dragEntered`,
`dragExited`, `dropCompleted(providers: [NSItemProvider])`. Everything past
that boundary — `NotchState`, `ShelfStore` — never sees an `NSEvent` or
`NSPasteboard`.

## State

`NotchState` (pure, Foundation/CoreGraphics only, per Invariant 1) gains:

```swift
enum NotchState: Equatable {
    // ...existing cases...
    case shelf
}

enum NotchEvent {
    // ...existing cases...
    case dragEntered
    case dragExited
    case dropCompleted
}
```

Reduction, following the same "only takes over from a resting state, active
states aren't yanked away" pattern `.trackChanged`/`.playbackToggled`
already use for `.peeking`:

- `.dragEntered` from `.collapsed`/`.pill` → `.shelf`. From `.expanded`
  (already hovering the player) or `.peeking` → unchanged; a drag entering
  mid-hover doesn't interrupt the player, matching how `.isPlayingChanged`
  already declines to yank `.expanded`/`.peeking` away.
- `.dragExited` while `.shelf` and nothing was dropped → back to resting
  (`.pill` if playing, else `.collapsed` — same resting-state rule
  `hoverEnded` already encodes). From any other state → unchanged (a stray
  exit event that doesn't apply).
- `.dropCompleted` while `.shelf` → stays `.shelf`, so the dropped item is
  visible immediately rather than the shelf closing the instant the file
  lands.
- Closing needs no new event: `.hoverEnded`'s existing reducer branch is
  already unconditional on the current state (`return isPlaying ? .pill :
  .collapsed`, no `switch` on `state`), so once `.shelf` exists as a case,
  the mouse leaving the panel while viewing the shelf already closes it back
  to the correct resting state for free.

All three cases are unit-testable exactly like the existing ones — no new
testing gap.

## Storage

New `Shelf/ShelfStore.swift` and `Shelf/ShelfItem.swift`.

`ShelfItem` (pure, `Codable`):
```swift
struct ShelfItem: Codable, Identifiable, Equatable {
    let id: UUID
    let originalFilename: String
    let addedAt: Date
    var storageURL: URL { /* Application Support/Atelier/Shelf/<id>/<originalFilename> */ }
    func isExpired(now: Date, keepInterval: TimeInterval) -> Bool {
        now.timeIntervalSince(addedAt) > keepInterval
    }
}
```
`isExpired` takes `now`/`keepInterval` as parameters (not read from `Date()`
internally) specifically so it's unit-testable without wall-clock
dependence — same reasoning `BatteryActivityState`'s pure `evaluate` already
follows.

`ShelfStore` (AppKit/Foundation, not pure — owns file I/O):
- On drop, copies each provided file into
  `~/Library/Application Support/Atelier/Shelf/<uuid>/<original filename>`
  (a per-item subdirectory avoids filename collisions between items).
  Originals are untouched.
- Persists the `[ShelfItem]` list as a small JSON manifest
  (`Shelf/manifest.json`) via `Codable`, not `UserDefaults` — this is a
  small structured file list, not a preference.
- Default retention: **24 hours** (matching `NotchDrop`'s own default),
  configurable later from Settings if wanted — not blocking this pass.
- Cleanup is a **lazy sweep**, not a background timer: expired items are
  filtered out of the manifest (and their storage directories deleted) each
  time the shelf is opened (`.shelf` state entered) and once at app launch.
  No persistent polling loop for something that only matters while the
  shelf is actually visible.

## UI

New `UI/ShelfView.swift`, wired into `NotchRootView` as the view for
`.shelf`, sized within the panel's existing max-expanded footprint
(Invariant 3 — no new window, no panel resize).

- A horizontal row/grid of dropped items: a file-type icon (via
  `NSWorkspace.shared.icon(forFile:)`, no thumbnail-generation service —
  YAGNI relative to `boring.notch`'s `ThumbnailService`/`QuickLookService`
  for a first pass) plus filename.
- Each item is itself an `NSItemProvider`-backed drag source (`.draggable`
  in SwiftUI, or an `NSItemProvider`-wrapping `NSView` if SwiftUI's own
  drag modifier doesn't reach far enough) so it can be dragged back out to
  Finder or another app.
- A remove affordance (e.g. an "x" on hover) deletes the item immediately
  rather than waiting for expiry.
- Empty state: a plain "Drop files here" placeholder — matches this
  project's existing pattern for empty/no-data states (`ExpandedPlayerView`'s
  not-playing state).

## Testing

- `NotchStateTests`: the three new events × existing states, following the
  file's current table-style test pattern.
- `ShelfItem.isExpired`: boundary cases (exactly at `keepInterval`, just
  under, just over, `now` before `addedAt` defensively).
- Everything else (`NotchDragDetector`'s `NSEvent` handling, `ShelfStore`'s
  actual file I/O, `ShelfView`'s drag-out behavior) is manual-only, like
  every other AppKit/filesystem seam in this project (`CLAUDE.md`'s Testing
  section already documents this split; nothing new here).

## Explicitly out of scope for this pass

- AirDrop integration (sub-project 2).
- File format converter (sub-project 3).
- Thumbnail previews / Quick Look — icon only.
- Configurable retention from Settings — hardcoded 24h constant for now.
- Drag-reordering within the shelf.
