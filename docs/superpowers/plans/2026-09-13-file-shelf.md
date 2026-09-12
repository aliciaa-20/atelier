# File Shelf Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Drag a file onto the notch and have it land in a small persistent
shelf, visible as a new `.shelf` state, that you can later drag back out to
Finder or another app.

**Architecture:** A pure `.shelf` case + three new events added to the
existing `NotchState`/`NotchStateMachine` (Invariant 1: Foundation/CG only).
Drag detection lives in a new AppKit-side `NotchDragDetector`, mirroring the
`NotchGestureModifier`/`NotchGestureInterpreter` boundary (Invariant 8) —
raw `NSEvent`/`NSPasteboard` never crosses into pure code. Dropped files are
copied into `~/Library/Application Support/Atelier/Shelf/` and tracked by a
new `ShelfStore` (a plain `[ShelfItem]` array + JSON manifest, no
third-party dependency), rendered by a new `ShelfView`.

**Tech Stack:** Swift 6, AppKit (`NSEvent`, `NSPasteboard`, `NSItemProvider`,
`NSWorkspace`), SwiftUI, Swift Testing (`import Testing`).

**Spec:** `docs/superpowers/specs/2026-09-13-file-shelf-design.md`

## Global Constraints

- No third-party dependencies (`CLAUDE.md`) — a plain `[ShelfItem]` array,
  not `swift-collections`' `OrderedSet`.
- `NotchGeometry`/`NotchState` (and this plan's new `NotchState` additions)
  import nothing but Foundation/CoreGraphics (Invariant 1).
- Global mouse-event monitors (`.leftMouseDown/Dragged/Up`) need no
  Accessibility permission — only keyboard-event global monitors do. No new
  TCC grant for this feature.
- Default retention: 24 hours, hardcoded (not a Settings toggle in this pass).
- Swift Testing (`import Testing`, `@Test`, `#expect`), not XCTest — match
  every existing test file's style.

---

### Task 1: `NotchState` gains `.shelf` and three drag events

**Files:**
- Modify: `Atelier/Notch/NotchState.swift`
- Test: `AtelierTests/NotchStateTests.swift`

**Interfaces:**
- Produces: `NotchState.shelf` case; `NotchEvent.dragEntered`,
  `.dragExited`, `.dropCompleted` cases; `NotchStateMachine.reduce` handles
  all three.

- [ ] **Step 1: Write the failing tests**

Append to `AtelierTests/NotchStateTests.swift`:

```swift
extension NotchStateTests {
    @Test func dragEnteredOpensShelfFromCollapsed() {
        let result = NotchStateMachine.reduce(.collapsed, on: .dragEntered)

        #expect(result == .shelf)
    }

    @Test func dragEnteredOpensShelfFromPill() {
        let result = NotchStateMachine.reduce(.pill, on: .dragEntered)

        #expect(result == .shelf)
    }

    @Test func dragEnteredDoesNothingWhileExpanded() {
        let result = NotchStateMachine.reduce(.expanded, on: .dragEntered)

        #expect(result == .expanded)
    }

    @Test func dragEnteredDoesNothingWhilePeeking() {
        let result = NotchStateMachine.reduce(.peeking, on: .dragEntered)

        #expect(result == .peeking)
    }

    @Test func dragExitedRestsAsCollapsedWhenNotPlaying() {
        let result = NotchStateMachine.reduce(.shelf, on: .dragExited(isPlaying: false))

        #expect(result == .collapsed)
    }

    @Test func dragExitedRestsAsPillWhenPlaying() {
        let result = NotchStateMachine.reduce(.shelf, on: .dragExited(isPlaying: true))

        #expect(result == .pill)
    }

    @Test func dragExitedDoesNothingOutsideShelf() {
        let result = NotchStateMachine.reduce(.expanded, on: .dragExited(isPlaying: true))

        #expect(result == .expanded)
    }

    @Test func dropCompletedStaysInShelf() {
        let result = NotchStateMachine.reduce(.shelf, on: .dropCompleted)

        #expect(result == .shelf)
    }

    @Test func hoverEndedClosesShelf() {
        let result = NotchStateMachine.reduce(.shelf, on: .hoverEnded(isPlaying: false))

        #expect(result == .collapsed)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme Atelier -destination 'platform=macOS' -only-testing:AtelierTests/NotchStateTests`
Expected: FAIL to compile — `NotchState` has no member `shelf`, `NotchEvent` has no member `dragEntered`/`dragExited`/`dropCompleted`.

- [ ] **Step 3: Implement**

Replace the full contents of `Atelier/Notch/NotchState.swift`:

```swift
/// What the notch is currently showing.
enum NotchState: Equatable {
    /// Visually indistinguishable from the stock notch (Invariant 7).
    case collapsed
    /// A slim always-on sliver while music plays, not hovering.
    case pill
    /// The full player, shown on hover.
    case expanded
    /// The full player, auto-shown briefly on a track change (not hover-
    /// driven). Decays back to the resting state after a timer unless the
    /// user starts actually hovering, at which point `.hoverStarted` takes
    /// over and it behaves exactly like a normal expand.
    case peeking
    /// The file shelf, shown while dragging a file over the notch (or
    /// after a drop, until the mouse leaves). A separate interaction
    /// dimension from hover/peek -- entered by dragging, not hovering.
    case shelf
}

enum NotchEvent {
    case hoverStarted
    /// Carries the current playing state so the resting state after hover
    /// is `.pill` (still playing) or `.collapsed` (not), without the pure
    /// reducer needing to remember anything across calls.
    case hoverEnded(isPlaying: Bool)
    /// Fired by `NowPlayingCoordinator` whenever playback starts/stops.
    case isPlayingChanged(Bool)
    /// Fired on a detected track change, gated by the user's "peek on
    /// track change" setting before it ever reaches the state machine.
    case trackChanged
    /// Fired when playback starts or stops, same gating as `trackChanged`.
    /// A separate case from `isPlayingChanged` (which only governs the
    /// collapsed/pill resting state) so a play/pause toggle earns a peek
    /// too, not just a track change.
    case playbackToggled
    /// Fired by a timer started when entering `.peeking`; a no-op unless
    /// still `.peeking` (i.e. the user hasn't started hovering since).
    case peekTimerElapsed(isPlaying: Bool)
    /// Fired by `NotchDragDetector` when a drag carrying real file content
    /// enters the notch's screen region.
    case dragEntered
    /// Fired by `NotchDragDetector` when a drag exits the region without
    /// dropping. Carries `isPlaying` for the same reason `hoverEnded` does
    /// -- resolving the correct resting state without the reducer
    /// remembering anything across calls.
    case dragExited(isPlaying: Bool)
    /// Fired by `NotchDragDetector` when a drag is released inside the
    /// region. Stays in `.shelf` rather than closing immediately, so the
    /// newly-dropped item is visible.
    case dropCompleted
}

enum NotchStateMachine {
    static func reduce(_ state: NotchState, on event: NotchEvent) -> NotchState {
        switch event {
        case .hoverStarted:
            return .expanded
        case .hoverEnded(let isPlaying):
            return isPlaying ? .pill : .collapsed
        case .isPlayingChanged(let isPlaying):
            switch state {
            case .expanded, .peeking, .shelf:
                // Don't yank the player/shelf away mid-hover/peek/drag just
                // because playback state changed underneath it.
                return state
            case .collapsed, .pill:
                return isPlaying ? .pill : .collapsed
            }
        case .trackChanged, .playbackToggled:
            // Only takes over from a resting state; an active hover
            // already shows everything a peek would.
            switch state {
            case .collapsed, .pill:
                return .peeking
            case .expanded, .peeking, .shelf:
                return state
            }
        case .peekTimerElapsed(let isPlaying):
            guard state == .peeking else { return state }
            return isPlaying ? .pill : .collapsed
        case .dragEntered:
            switch state {
            case .collapsed, .pill:
                return .shelf
            case .expanded, .peeking, .shelf:
                return state
            }
        case .dragExited(let isPlaying):
            guard state == .shelf else { return state }
            return isPlaying ? .pill : .collapsed
        case .dropCompleted:
            return state
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme Atelier -destination 'platform=macOS' -only-testing:AtelierTests/NotchStateTests`
Expected: PASS, all tests including the 9 new ones.

- [ ] **Step 5: Fix the two other exhaustive switches this breaks**

`NotchState.shelf` is a new case — `NotchViewModel.currentSize` and
`NotchRootView`'s `cornerRadii`/`frameSize` all `switch` on `state`
exhaustively and will now fail to compile. Fix minimally here (placeholder
sizing/radii reusing `.expanded`'s values) — Task 5 replaces the placeholder
with real shelf rendering.

In `Atelier/Notch/NotchViewModel.swift`, change:
```swift
    var currentSize: CGSize {
        switch state {
        case .collapsed: collapsedSize
        case .pill: pillSize
        case .expanded: expandedSize
        case .peeking: peekSize
        }
    }
```
to:
```swift
    var currentSize: CGSize {
        switch state {
        case .collapsed: collapsedSize
        case .pill: pillSize
        case .expanded: expandedSize
        case .peeking: peekSize
        // Placeholder -- Task 5 gives the shelf its own size once
        // `ShelfView` exists to size around.
        case .shelf: expandedSize
        }
    }
```

In `Atelier/UI/NotchRootView.swift`, change the `cornerRadii` switch's
`.peeking` case block to add a `.shelf` case right after it:
```swift
        case .peeking:
            let content = liveActivity.topContent ?? lastPeekContent
            return content?.isExpandable == false ? (top: 6, bottom: 14) : (top: 14, bottom: 14)
        }
```
to:
```swift
        case .peeking:
            let content = liveActivity.topContent ?? lastPeekContent
            return content?.isExpandable == false ? (top: 6, bottom: 14) : (top: 14, bottom: 14)
        // Placeholder -- Task 5 gives the shelf its own radii.
        case .shelf:
            return (top: 14, bottom: 20)
        }
```

And the `frameSize` switch's line:
```swift
        case .pill, .collapsed, .expanded:
            return viewModel.currentSize
        }
```
to:
```swift
        case .pill, .collapsed, .expanded, .shelf:
            return viewModel.currentSize
        }
```

- [ ] **Step 6: Build and run the full suite to verify nothing else broke**

Run: `xcodebuild -scheme Atelier -configuration Debug build`
Expected: BUILD SUCCEEDED

Run: `xcodebuild test -scheme Atelier -destination 'platform=macOS'`
Expected: all tests pass (85 existing + 9 new = 94).

- [ ] **Step 7: Commit**

```bash
git add Atelier/Notch/NotchState.swift Atelier/Notch/NotchViewModel.swift Atelier/UI/NotchRootView.swift AtelierTests/NotchStateTests.swift
git commit -m "feat: add NotchState.shelf and drag events for the file shelf"
```

---

### Task 2: `ShelfItem` pure model

**Files:**
- Create: `Atelier/Shelf/ShelfItem.swift`
- Test: `AtelierTests/ShelfItemTests.swift`

**Interfaces:**
- Consumes: nothing new.
- Produces: `struct ShelfItem: Codable, Identifiable, Equatable` with
  `id: UUID`, `originalFilename: String`, `addedAt: Date`, a `storageURL(root:)`
  method, and `isExpired(now:keepInterval:) -> Bool`. `ShelfStore` (Task 3)
  and `ShelfView` (Task 5) both depend on this exact shape.

- [ ] **Step 1: Write the failing test**

Create `AtelierTests/ShelfItemTests.swift`:

```swift
import Testing
import Foundation
@testable import Atelier

struct ShelfItemTests {
    private static let keepInterval: TimeInterval = 60 * 60 * 24 // 24h

    @Test func isNotExpiredJustAfterAdding() {
        let now = Date()
        let item = ShelfItem(id: UUID(), originalFilename: "a.txt", addedAt: now)

        #expect(item.isExpired(now: now, keepInterval: Self.keepInterval) == false)
    }

    @Test func isNotExpiredJustUnderTheInterval() {
        let addedAt = Date()
        let now = addedAt.addingTimeInterval(Self.keepInterval - 1)
        let item = ShelfItem(id: UUID(), originalFilename: "a.txt", addedAt: addedAt)

        #expect(item.isExpired(now: now, keepInterval: Self.keepInterval) == false)
    }

    @Test func isExpiredJustOverTheInterval() {
        let addedAt = Date()
        let now = addedAt.addingTimeInterval(Self.keepInterval + 1)
        let item = ShelfItem(id: UUID(), originalFilename: "a.txt", addedAt: addedAt)

        #expect(item.isExpired(now: now, keepInterval: Self.keepInterval) == true)
    }

    @Test func isNotExpiredIfNowIsBeforeAddedAt() {
        // Defensive: a clock adjustment shouldn't retroactively expire a
        // just-added item.
        let addedAt = Date()
        let now = addedAt.addingTimeInterval(-10)
        let item = ShelfItem(id: UUID(), originalFilename: "a.txt", addedAt: addedAt)

        #expect(item.isExpired(now: now, keepInterval: Self.keepInterval) == false)
    }

    @Test func storageURLNestsUnderIDThenFilename() {
        let id = UUID()
        let item = ShelfItem(id: id, originalFilename: "report.pdf", addedAt: Date())
        let root = URL(fileURLWithPath: "/tmp/AtelierShelfTest")

        let url = item.storageURL(root: root)

        #expect(url == root.appendingPathComponent(id.uuidString).appendingPathComponent("report.pdf"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme Atelier -destination 'platform=macOS' -only-testing:AtelierTests/ShelfItemTests`
Expected: FAIL to compile — no such file `ShelfItem.swift`.

- [ ] **Step 3: Implement**

Create `Atelier/Shelf/ShelfItem.swift`:

```swift
import Foundation

/// One file on the shelf. Pure -- no FileManager/AppKit -- so expiry logic
/// is unit-testable independent of `ShelfStore`'s actual file I/O.
struct ShelfItem: Codable, Identifiable, Equatable {
    let id: UUID
    let originalFilename: String
    let addedAt: Date

    /// Nested under a per-item UUID directory (not stored flat) so two
    /// items with the same original filename never collide.
    func storageURL(root: URL) -> URL {
        root.appendingPathComponent(id.uuidString).appendingPathComponent(originalFilename)
    }

    /// `now`/`keepInterval` are parameters, not read from `Date()`/a stored
    /// default internally, specifically so this stays unit-testable without
    /// wall-clock dependence -- same reasoning `BatteryActivityState.evaluate`
    /// already follows for its own pure threshold check.
    func isExpired(now: Date, keepInterval: TimeInterval) -> Bool {
        now.timeIntervalSince(addedAt) > keepInterval
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme Atelier -destination 'platform=macOS' -only-testing:AtelierTests/ShelfItemTests`
Expected: PASS, all 5 tests.

- [ ] **Step 5: Commit**

```bash
git add Atelier/Shelf/ShelfItem.swift AtelierTests/ShelfItemTests.swift
git commit -m "feat: add pure ShelfItem model with testable expiry"
```

---

### Task 3: `ShelfStore` — file I/O, manifest persistence, sweep

**Files:**
- Create: `Atelier/Shelf/ShelfStore.swift`
- Test: `AtelierTests/ShelfStoreTests.swift`

**Interfaces:**
- Consumes: `ShelfItem` (Task 2) — `storageURL(root:)`, `isExpired(now:keepInterval:)`.
- Produces: `@MainActor final class ShelfStore: ObservableObject` with
  `@Published private(set) var items: [ShelfItem]`, `init(rootDirectory: URL, keepInterval: TimeInterval = 86400)`,
  `func addFile(at sourceURL: URL, originalFilename: String) throws`,
  `func remove(_ id: UUID)`, `func sweepExpired(now: Date = Date())`.
  `NotchController` (Task 6) and `ShelfView` (Task 5) both depend on this
  exact shape. `rootDirectory` is an injected parameter (not a hardcoded
  Application Support path inside the type) specifically so tests can point
  it at a temp directory instead of touching the real filesystem location.

- [ ] **Step 1: Write the failing tests**

Create `AtelierTests/ShelfStoreTests.swift`:

```swift
import Testing
import Foundation
@testable import Atelier

@MainActor
struct ShelfStoreTests {
    private func makeTempRoot() -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AtelierShelfStoreTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makeSourceFile(named name: String, in directory: URL) -> URL {
        let url = directory.appendingPathComponent(name)
        try? "test content".write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @Test func addFileCopiesIntoRootAndTracksItem() throws {
        let root = makeTempRoot()
        let sourceDir = makeTempRoot()
        let source = makeSourceFile(named: "note.txt", in: sourceDir)
        let store = ShelfStore(rootDirectory: root)

        try store.addFile(at: source, originalFilename: "note.txt")

        #expect(store.items.count == 1)
        let item = try #require(store.items.first)
        #expect(item.originalFilename == "note.txt")
        #expect(FileManager.default.fileExists(atPath: item.storageURL(root: root).path))
        // Original untouched.
        #expect(FileManager.default.fileExists(atPath: source.path))
    }

    @Test func removeDeletesFileAndDropsItem() throws {
        let root = makeTempRoot()
        let sourceDir = makeTempRoot()
        let source = makeSourceFile(named: "note.txt", in: sourceDir)
        let store = ShelfStore(rootDirectory: root)
        try store.addFile(at: source, originalFilename: "note.txt")
        let item = try #require(store.items.first)

        store.remove(item.id)

        #expect(store.items.isEmpty)
        #expect(FileManager.default.fileExists(atPath: item.storageURL(root: root).path) == false)
    }

    @Test func sweepExpiredRemovesOnlyOldItems() throws {
        let root = makeTempRoot()
        let sourceDir = makeTempRoot()
        let oldSource = makeSourceFile(named: "old.txt", in: sourceDir)
        let freshSource = makeSourceFile(named: "fresh.txt", in: sourceDir)
        let store = ShelfStore(rootDirectory: root, keepInterval: 60)
        try store.addFile(at: oldSource, originalFilename: "old.txt")
        try store.addFile(at: freshSource, originalFilename: "fresh.txt")

        store.sweepExpired(now: Date().addingTimeInterval(120))

        #expect(store.items.map(\.originalFilename) == ["fresh.txt"])
    }

    @Test func manifestPersistsAcrossStoreInstances() throws {
        let root = makeTempRoot()
        let sourceDir = makeTempRoot()
        let source = makeSourceFile(named: "note.txt", in: sourceDir)
        let firstStore = ShelfStore(rootDirectory: root)
        try firstStore.addFile(at: source, originalFilename: "note.txt")

        let secondStore = ShelfStore(rootDirectory: root)

        #expect(secondStore.items.map(\.originalFilename) == ["note.txt"])
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme Atelier -destination 'platform=macOS' -only-testing:AtelierTests/ShelfStoreTests`
Expected: FAIL to compile — no such file `ShelfStore.swift`.

- [ ] **Step 3: Implement**

Create `Atelier/Shelf/ShelfStore.swift`:

```swift
import Foundation

/// Owns dropped files on disk: copies them into `rootDirectory`, tracks
/// them as a plain `[ShelfItem]` (no `OrderedSet`/`swift-collections`
/// dependency), and persists that list as a small JSON manifest.
/// `rootDirectory` is injected rather than hardcoded to a real Application
/// Support path so tests can point this at a temp directory.
@MainActor
final class ShelfStore: ObservableObject {
    @Published private(set) var items: [ShelfItem] = []

    private let rootDirectory: URL
    private let keepInterval: TimeInterval
    private var manifestURL: URL { rootDirectory.appendingPathComponent("manifest.json") }

    init(rootDirectory: URL, keepInterval: TimeInterval = 60 * 60 * 24) {
        self.rootDirectory = rootDirectory
        self.keepInterval = keepInterval
        try? FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        items = Self.loadManifest(at: manifestURL)
    }

    /// Copies `sourceURL` into a fresh per-item directory under
    /// `rootDirectory` and adds it to `items`. The original file is never
    /// modified or moved.
    func addFile(at sourceURL: URL, originalFilename: String) throws {
        let item = ShelfItem(id: UUID(), originalFilename: originalFilename, addedAt: Date())
        let destination = item.storageURL(root: rootDirectory)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: sourceURL, to: destination)

        items.insert(item, at: 0)
        saveManifest()
    }

    func remove(_ id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        try? FileManager.default.removeItem(at: item.storageURL(root: rootDirectory).deletingLastPathComponent())
        items.removeAll { $0.id == id }
        saveManifest()
    }

    /// Lazy sweep, not a background timer -- called when the shelf is
    /// opened and once at app launch, per the design spec. `now` is a
    /// parameter so this stays testable without wall-clock dependence.
    func sweepExpired(now: Date = Date()) {
        let expired = items.filter { $0.isExpired(now: now, keepInterval: keepInterval) }
        guard !expired.isEmpty else { return }
        for item in expired {
            try? FileManager.default.removeItem(at: item.storageURL(root: rootDirectory).deletingLastPathComponent())
        }
        items.removeAll { item in expired.contains(item) }
        saveManifest()
    }

    private func saveManifest() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: manifestURL, options: .atomic)
    }

    private static func loadManifest(at url: URL) -> [ShelfItem] {
        guard let data = try? Data(contentsOf: url),
              let items = try? JSONDecoder().decode([ShelfItem].self, from: data)
        else { return [] }
        return items
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme Atelier -destination 'platform=macOS' -only-testing:AtelierTests/ShelfStoreTests`
Expected: PASS, all 4 tests.

- [ ] **Step 5: Commit**

```bash
git add Atelier/Shelf/ShelfStore.swift AtelierTests/ShelfStoreTests.swift
git commit -m "feat: add ShelfStore for shelf file persistence and expiry"
```

---

### Task 4: `ShelfView` — the shelf's SwiftUI content

**Files:**
- Create: `Atelier/UI/ShelfView.swift`

**Interfaces:**
- Consumes: `ShelfStore` (Task 3) — `items: [ShelfItem]`, `remove(_:)`.
  `ShelfItem.storageURL(root:)` (Task 2).
- Produces: `struct ShelfView: View`, `init(store: ShelfStore, rootDirectory: URL, notchHeight: CGFloat)`.
  `NotchRootView` (Task 6) renders this for `.shelf`.

No unit test for this task — SwiftUI view layout is manual-verification
only, same as every other `UI/*.swift` view in this project (`CLAUDE.md`'s
Testing section).

- [ ] **Step 1: Implement**

Create `Atelier/UI/ShelfView.swift`:

```swift
import SwiftUI

struct ShelfView: View {
    @ObservedObject var store: ShelfStore
    let rootDirectory: URL
    /// Same reasoning as `PeekPlayerView.notchHeight`: the physical notch
    /// cutout has no display pixels, so content starts below it.
    let notchHeight: CGFloat

    private let columns = [GridItem(.adaptive(minimum: 64, maximum: 64), spacing: 12)]

    var body: some View {
        Group {
            if store.items.isEmpty {
                Text("Drop files here")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHGrid(rows: columns, spacing: 12) {
                        ForEach(store.items) { item in
                            ShelfItemCell(item: item, rootDirectory: rootDirectory) {
                                store.remove(item.id)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
        .padding(.top, notchHeight + 8)
        .padding(.bottom, 10)
    }
}

private struct ShelfItemCell: View {
    let item: ShelfItem
    let rootDirectory: URL
    let onRemove: () -> Void
    @State private var isHovering = false

    private var fileURL: URL { item.storageURL(root: rootDirectory) }

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: fileURL.path))
                    .resizable()
                    .frame(width: 40, height: 40)

                if isHovering {
                    Button(action: onRemove) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.white, .black.opacity(0.6))
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.plain)
                    .offset(x: 6, y: -6)
                }
            }

            Text(item.originalFilename)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .frame(width: 64)
        }
        .onHover { isHovering = $0 }
        .onDrag { NSItemProvider(contentsOf: fileURL) ?? NSItemProvider() }
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `xcodebuild -scheme Atelier -configuration Debug build`
Expected: BUILD SUCCEEDED. `ShelfView` isn't referenced anywhere yet
(Task 6 wires it in), so this only confirms the file itself compiles.

- [ ] **Step 3: Commit**

```bash
git add Atelier/UI/ShelfView.swift
git commit -m "feat: add ShelfView grid, drag-out, and empty state"
```

---

### Task 5: `NotchDragDetector` — AppKit drag detection

**Files:**
- Create: `Atelier/Notch/NotchDragDetector.swift`

**Interfaces:**
- Produces: `struct NotchDragModifier: ViewModifier` with
  `init(onDragEntered: @escaping () -> Void, onDragExited: @escaping () -> Void, onDrop: @escaping ([NSItemProvider]) -> Void)`.
  `NotchRootView` (Task 6) applies this via `.modifier(...)`.

No unit test — raw `NSEvent`/`NSPasteboard` handling is manual-verification
only, same as `NotchGestureModifier` (its own doc comment already states
this).

- [ ] **Step 1: Implement**

Create `Atelier/Notch/NotchDragDetector.swift`:

```swift
import SwiftUI
import AppKit

/// Detects a file drag entering/exiting/dropping on the notch panel's own
/// screen region. Adapted from TheBoredTeam/boring.notch's `DragDetector`
/// (read via `gh api` per check-reference-apps-first): global `NSEvent`
/// monitors on mouse down/dragged/up, using the drag pasteboard's
/// `changeCount` to distinguish real dragged content from a plain click.
/// Mirrors the AppKit boundary `NotchGestureModifier`/`NotchGestureInterpreter`
/// already establish (Invariant 8) -- raw `NSEvent`/`NSPasteboard` never
/// crosses past this file; `NotchRootView` only sees the three closures
/// below. Manual-verification only -- no real drag session in CI, same
/// treatment as `NotchGestureModifier`.
struct NotchDragModifier: ViewModifier {
    let onDragEntered: () -> Void
    let onDragExited: () -> Void
    let onDrop: ([NSItemProvider]) -> Void

    func body(content: Content) -> some View {
        content.background(
            NotchDragMonitorRepresentable(onDragEntered: onDragEntered, onDragExited: onDragExited, onDrop: onDrop)
        )
    }
}

private struct NotchDragMonitorRepresentable: NSViewRepresentable {
    let onDragEntered: () -> Void
    let onDragExited: () -> Void
    let onDrop: ([NSItemProvider]) -> Void

    func makeNSView(context: Context) -> NotchDragMonitorView {
        let view = NotchDragMonitorView()
        view.update(onDragEntered: onDragEntered, onDragExited: onDragExited, onDrop: onDrop)
        return view
    }

    func updateNSView(_ nsView: NotchDragMonitorView, context: Context) {
        nsView.update(onDragEntered: onDragEntered, onDragExited: onDragExited, onDrop: onDrop)
    }

    static func dismantleNSView(_ nsView: NotchDragMonitorView, coordinator: ()) {
        nsView.stopMonitoring()
    }
}

@MainActor private final class NotchDragMonitorView: NSView {
    private var mouseDownMonitor: Any?
    private var mouseDraggedMonitor: Any?
    private var mouseUpMonitor: Any?

    private var onDragEntered: (() -> Void)?
    private var onDragExited: (() -> Void)?
    private var onDrop: (([NSItemProvider]) -> Void)?

    private let dragPasteboard = NSPasteboard(name: .drag)
    private var pasteboardChangeCount = -1
    private var isDragging = false
    private var isContentDragging = false
    private var hasEnteredRegion = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        installMonitorsIfNeeded()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    isolated deinit {
        if let mouseDownMonitor { NSEvent.removeMonitor(mouseDownMonitor) }
        if let mouseDraggedMonitor { NSEvent.removeMonitor(mouseDraggedMonitor) }
        if let mouseUpMonitor { NSEvent.removeMonitor(mouseUpMonitor) }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        installMonitorsIfNeeded()
    }

    func update(onDragEntered: @escaping () -> Void, onDragExited: @escaping () -> Void, onDrop: @escaping ([NSItemProvider]) -> Void) {
        self.onDragEntered = onDragEntered
        self.onDragExited = onDragExited
        self.onDrop = onDrop
    }

    func stopMonitoring() {
        if let mouseDownMonitor { NSEvent.removeMonitor(mouseDownMonitor) }
        if let mouseDraggedMonitor { NSEvent.removeMonitor(mouseDraggedMonitor) }
        if let mouseUpMonitor { NSEvent.removeMonitor(mouseUpMonitor) }
        mouseDownMonitor = nil
        mouseDraggedMonitor = nil
        mouseUpMonitor = nil
    }

    /// Same reasoning as `NotchGestureMonitorView.hitTest`: this view exists
    /// purely to install `NSEvent` monitors, which fire regardless of
    /// AppKit hit-testing, so it must not intercept clicks meant for the
    /// SwiftUI content above it.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private extension NotchDragMonitorView {
    func installMonitorsIfNeeded() {
        if mouseDownMonitor == nil {
            mouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
                self?.handleMouseDown()
            }
        }
        if mouseDraggedMonitor == nil {
            mouseDraggedMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] _ in
                self?.handleMouseDragged()
            }
        }
        if mouseUpMonitor == nil {
            mouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
                self?.handleMouseUp()
            }
        }
    }

    func handleMouseDown() {
        pasteboardChangeCount = dragPasteboard.changeCount
        isDragging = true
        isContentDragging = false
        hasEnteredRegion = false
    }

    func handleMouseDragged() {
        guard isDragging else { return }

        if !isContentDragging, dragPasteboard.changeCount != pasteboardChangeCount, hasValidDragContent() {
            isContentDragging = true
        }
        guard isContentDragging, let screenRect = currentScreenRect() else { return }

        let containsMouse = screenRect.contains(NSEvent.mouseLocation)
        if containsMouse, !hasEnteredRegion {
            hasEnteredRegion = true
            onDragEntered?()
        } else if !containsMouse, hasEnteredRegion {
            hasEnteredRegion = false
            onDragExited?()
        }
    }

    func handleMouseUp() {
        guard isDragging else { return }
        if isContentDragging, hasEnteredRegion, let providers = draggedItemProviders() {
            onDrop?(providers)
        } else if hasEnteredRegion {
            onDragExited?()
        }
        isDragging = false
        isContentDragging = false
        hasEnteredRegion = false
        pasteboardChangeCount = -1
    }

    func hasValidDragContent() -> Bool {
        dragPasteboard.types?.contains(.fileURL) ?? false
    }

    func draggedItemProviders() -> [NSItemProvider]? {
        guard let urls = dragPasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !urls.isEmpty else {
            return nil
        }
        return urls.map { NSItemProvider(contentsOf: $0) ?? NSItemProvider() }
    }

    func currentScreenRect() -> CGRect? {
        guard let window else { return nil }
        let rectInWindow = convert(bounds, to: nil)
        return window.convertToScreen(rectInWindow)
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `xcodebuild -scheme Atelier -configuration Debug build`
Expected: BUILD SUCCEEDED. Not wired into `NotchRootView` yet (Task 6).

- [ ] **Step 3: Commit**

```bash
git add Atelier/Notch/NotchDragDetector.swift
git commit -m "feat: add NotchDragDetector for file-drag region detection"
```

---

### Task 6: Wire everything into `NotchController`/`NotchRootView`

**Files:**
- Modify: `Atelier/Notch/NotchController.swift`
- Modify: `Atelier/Notch/NotchViewModel.swift`
- Modify: `Atelier/UI/NotchRootView.swift`

**Interfaces:**
- Consumes: `ShelfStore` (Task 3), `ShelfView` (Task 4), `NotchDragModifier`
  (Task 5), `NotchEvent.dragEntered/.dragExited/.dropCompleted` (Task 1).

- [ ] **Step 1: Give the shelf its own size**

In `Atelier/Notch/NotchViewModel.swift`, add a `shelfSize` property next to
`compactPeekSize` and use it instead of the Task 1 placeholder:

```swift
    let compactPeekSize: CGSize
    /// The file shelf's own footprint -- wide enough for a short horizontal
    /// row of items, shorter than the full player since there's no
    /// scrubber/transport row to fit.
    let shelfSize: CGSize

    init(collapsedSize: CGSize, expandedSize: CGSize, pillSize: CGSize, peekSize: CGSize, compactPeekSize: CGSize, shelfSize: CGSize) {
        self.collapsedSize = collapsedSize
        self.expandedSize = expandedSize
        self.pillSize = pillSize
        self.peekSize = peekSize
        self.compactPeekSize = compactPeekSize
        self.shelfSize = shelfSize
    }
```

And change `currentSize`'s `.shelf` case from the Task 1 placeholder:
```swift
        case .shelf: expandedSize
```
to:
```swift
        case .shelf: shelfSize
```

- [ ] **Step 2: Update both `NotchViewModel(...)` call sites in `NotchController.swift`**

The no-notch-screen fallback branch (near the top of `init()`):
```swift
            viewModel = NotchViewModel(collapsedSize: .zero, expandedSize: .zero, pillSize: .zero, peekSize: .zero, compactPeekSize: .zero)
```
becomes:
```swift
            viewModel = NotchViewModel(collapsedSize: .zero, expandedSize: .zero, pillSize: .zero, peekSize: .zero, compactPeekSize: .zero, shelfSize: .zero)
```

The real-screen branch: add a `shelfSize` constant next to the other size
constants and pass it through. Add near `Self.expandedWidth`:
```swift
    private static let expandedWidth: CGFloat = 352
    /// A single row of ~64pt item cells plus padding -- matches
    /// `ShelfView`'s own column width. Shorter than `playerContentHeight`
    /// since there's no scrubber/transport row.
    private static let shelfContentHeight: CGFloat = 90
```
Then where `compactPeekSize` is built, add:
```swift
        let compactPeekSize = CGSize(
            width: Self.compactPeekWidth,
            height: collapsedRect.height + Self.compactPeekContentHeight
        )
        let shelfSize = CGSize(
            width: Self.expandedWidth,
            height: collapsedRect.height + Self.shelfContentHeight
        )
        viewModel = NotchViewModel(
            collapsedSize: collapsedRect.size,
            expandedSize: expandedSize,
            pillSize: pillSize,
            peekSize: peekSize,
            compactPeekSize: compactPeekSize,
            shelfSize: shelfSize
        )
```
(replacing the existing `viewModel = NotchViewModel(...)` call, which had no
`shelfSize:` argument).

- [ ] **Step 3: Add a `ShelfStore` owned by `NotchController`**

Add a stored property next to `liveActivityCoordinator`:
```swift
    private let liveActivityCoordinator: LiveActivityCoordinator
    private let shelfStore: ShelfStore
```

In `init()`, construct it once before either branch builds `NotchRootView`
(right after `let hudOrder = SystemHUDOrder()` in each branch is fine, or
immediately before `panel.contentView = ...` — construct it once, near the
top of `init()`, before the `guard let screen = ...` so both branches share
it):
```swift
    init() {
        let shelfRoot = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Atelier", isDirectory: true)
            .appendingPathComponent("Shelf", isDirectory: true)
        shelfStore = ShelfStore(rootDirectory: shelfRoot)
        shelfStore.sweepExpired()

        guard let screen = NSScreen.notchedOrMain else {
```
(This replaces the existing `init() {` line and the `guard let screen = ...`
line right after it — everything else in `init()` stays where it is.)

Pass it to both `NotchRootView(...)` constructions. The no-screen fallback
branch (inside the `guard let screen = ... else { ... }` block):
```swift
            panel.contentView = ClickThroughHostingView(
                rootView: NotchRootView(
                    viewModel: viewModel,
                    nowPlaying: nowPlayingCoordinator,
                    liveActivity: liveActivityCoordinator,
                    shelfStore: shelfStore
                )
            )
```
And the real-screen branch, later in the same `init()`, after `guard`'s
closing brace:
```swift
        panel.contentView = ClickThroughHostingView(
            rootView: NotchRootView(
                viewModel: viewModel,
                nowPlaying: nowPlayingCoordinator,
                liveActivity: liveActivityCoordinator,
                shelfStore: shelfStore
            )
        )
```
(both blocks already exist in the file with the same shape minus
`shelfStore: shelfStore` — add that one line to each).

- [ ] **Step 4: Wire drag detection and real `ShelfView` rendering into `NotchRootView`**

In `Atelier/UI/NotchRootView.swift`, add the new property:
```swift
struct NotchRootView: View {
    @ObservedObject var viewModel: NotchViewModel
    @ObservedObject var nowPlaying: NowPlayingCoordinator
    @ObservedObject var liveActivity: LiveActivityCoordinator
    @ObservedObject var shelfStore: ShelfStore
```

Replace the Task 1 placeholder `cornerRadii` `.shelf` case:
```swift
        case .shelf:
            return (top: 14, bottom: 20)
```
stays the same (it already matches `.expanded`'s radii, which is the
intended look for the shelf card) — no change needed here.

Add the shelf's real content branch in `body`'s `ZStack`, alongside the
existing `.expanded`/`.peeking`/`.pill` branches:
```swift
                } else if viewModel.state == .shelf {
                    ShelfView(store: shelfStore, rootDirectory: shelfRootDirectory, notchHeight: viewModel.collapsedSize.height)
                        .transition(.opacity)
                        .onAppear { shelfStore.sweepExpired() }
                }
```
(insert this as a new `else if` branch right after the existing `} else if viewModel.state == .pill { ... }` block's closing brace, before the outer `ZStack`'s own closing brace).

Add the computed property this references, next to `cornerRadii`:
```swift
    /// `ShelfStore` doesn't expose its own root directory (it only reports
    /// `items`), so `ShelfView` needs it separately to build each item's
    /// `storageURL`. Computed the same way `ShelfStore` computes its own
    /// default in `NotchController`, kept in exactly one other place.
    private var shelfRootDirectory: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Atelier", isDirectory: true)
            .appendingPathComponent("Shelf", isDirectory: true)
    }
```

Add the drag modifier alongside the existing `.modifier(NotchGestureModifier(...))`:
```swift
            .modifier(
                NotchDragModifier(
                    onDragEntered: {
                        withAnimation(NotchAnimations.open) {
                            viewModel.handle(.dragEntered)
                        }
                    },
                    onDragExited: {
                        withAnimation(NotchAnimations.close) {
                            viewModel.handle(.dragExited(isPlaying: liveActivity.hasContent))
                        }
                    },
                    onDrop: { providers in
                        for provider in providers {
                            _ = provider.loadFileRepresentation(forTypeIdentifier: "public.item") { url, _ in
                                guard let url else { return }
                                Task { @MainActor in
                                    try? shelfStore.addFile(at: url, originalFilename: url.lastPathComponent)
                                }
                            }
                        }
                        withAnimation(NotchAnimations.open) {
                            viewModel.handle(.dropCompleted)
                        }
                    }
                )
            )
```
(add this right after the existing `.modifier(NotchGestureModifier(...))`
block, still inside the same `VStack`, before the trailing `Spacer(minLength: 0).allowsHitTesting(false)`).

- [ ] **Step 5: Update the one call site outside `NotchController`/tests that constructs `NotchRootView`, if any**

Search for other constructions:
```bash
grep -rn "NotchRootView(" Atelier/
```
`NotchController.swift` (both branches, already updated in Step 3) should
be the only production call site. If a SwiftUI preview or anything else
constructs `NotchRootView`, add `shelfStore: ShelfStore(rootDirectory: FileManager.default.temporaryDirectory)`
to it too.

- [ ] **Step 6: Build and run the full suite**

Run: `xcodebuild -scheme Atelier -configuration Debug build`
Expected: BUILD SUCCEEDED

Run: `xcodebuild test -scheme Atelier -destination 'platform=macOS'`
Expected: all tests pass (94, unchanged from Task 1 — this task added no
new unit tests, only wiring).

- [ ] **Step 7: Manual verification**

Build and relaunch the app (`/build`), then:
- Drag a file from Finder toward the notch. Confirm the notch opens into
  the shelf as the drag enters its region, and closes if you drag away
  without dropping.
- Drop a file on the notch. Confirm it appears in the shelf with the
  correct icon and filename, and the original file at its source location
  is untouched.
- Hover a shelf item and click its remove button. Confirm it disappears
  and its copy in `~/Library/Application Support/Atelier/Shelf/` is gone
  (`ls ~/Library/Application\ Support/Atelier/Shelf/`).
- Drag a shelf item back out onto the Desktop or into another app. Confirm
  it drops successfully.
- Quit and relaunch the app. Confirm previously-dropped (non-expired) items
  are still in the shelf (manifest persistence).

- [ ] **Step 8: Commit**

```bash
git add Atelier/Notch/NotchController.swift Atelier/Notch/NotchViewModel.swift Atelier/UI/NotchRootView.swift
git commit -m "feat: wire file shelf drag detection and storage into the notch"
```

---

## After this plan

Run `phase-completion-checklist` before claiming Phase 9's shelf sub-project
done: confirm the manual verification steps above were actually exercised
on-device, update `docs/ROADMAP.md`'s Phase 9 checkbox and "Where we are"
line, and check whether `CLAUDE.md`'s architecture table needs a `Shelf/`
row (it currently lists `Widgets/*/*.swift` but not `Shelf/*.swift`).
AirDrop integration and the format converter are separate sub-projects,
each needing their own design pass before planning.
