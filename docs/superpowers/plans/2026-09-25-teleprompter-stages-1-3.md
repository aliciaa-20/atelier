# Teleprompter (Phase 17, stages 1-3) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Teleprompter notch tab with a WPM-paced scrolling script, a control strip and progress ring in the notch band, a Settings pane (editor + file drop), Ghost Mode, and optional global hotkeys.

**Architecture:** Pure, time-anchored scroll math (`TeleprompterScroll` computes position from a start date, so the view needs no mutating tick loop) plus pure line-index math (`TeleprompterLines`). A CoreText wrapper turns a script into display lines for a given width/font. A `@MainActor` `TeleprompterModel` owns state; a SwiftUI page renders only the few visible lines. Ghost Mode is `panel.sharingType = .none`, applied live from settings. Hotkeys use Carbon (no permission, no dependency).

**Tech Stack:** Swift 6 (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`), SwiftUI + AppKit/CoreText, Swift Testing, Carbon `RegisterEventHotKey`. No third-party dependencies.

**Spec:** `docs/superpowers/specs/2026-09-25-teleprompter-design.md` (stages 1-3). Stage 4 (voice sync) gets its own plan after these ship.

## Deviations from the spec (decided while reading the code)

1. **No `PaceSource` protocol yet.** `TeleprompterScroll` already has the two entry points a pace source needs: time-driven (`play`/`position(at:)`) and externally driven (`seek(to:at:)`). The stage-4 plan introduces a protocol only if the speech source really needs one (YAGNI).
2. **Text area is ~80-88pt, not ~118pt.** The tab-dot row already sits under the notch band (`collapsedSize.height + 5`, ~24pt target), so 150pt total leaves room for 3-4 lines at 15pt. The dots stay.
3. **Pages don't have size objects.** `NotchRootView.frameSize` branches per page; the teleprompter gets a branch there plus `NotchViewModel.teleprompterSize`.
4. **Pause-on-hover means "pause while the pointer is over the notch, resume on exit"** (only if it was playing when the pointer entered). Pressing play while the pointer is inside plays normally. This exists because the notch normally retracts on hover-out; hold-open keeps it up while reading.
5. **Hold-open is always on while playing** (no setting, unlike Camera): retracting mid-read is never wanted.

## Global Constraints

- Swift 6, strict concurrency; project default actor isolation is `MainActor`.
- SwiftUI first, AppKit/CoreText where SwiftUI can't reach. Deployment target macOS 26.0.
- **No third-party dependencies.** No new Swift packages.
- Invariant 1/8: pure types import only Foundation/CoreGraphics (`TeleprompterScript`, `TeleprompterScroll`, `TeleprompterLines`, `TeleprompterHoldOpen`).
- Invariant 3: the panel is the maximum footprint of any page; only SwiftUI content animates.
- Invariant 4: non-interactive regions get `.allowsHitTesting(false)`.
- Tests: Swift Testing (`import Testing`), not XCTest. Build: `xcodebuild -scheme Atelier -configuration Debug build`. Tests: `xcodebuild test -scheme Atelier -destination 'platform=macOS'`.
- Never use a trailing "..." in any UI label. Icon-only controls get `.help()` and a VoiceOver label. Bouncy/parallax motion honors Reduce Motion.
- Performance: nothing ticks unless the script is playing; `TimelineView(.periodic)` at 30 fps (4 fps under Reduce Motion), never `.animation`.
- Never hardcode secrets; commit to the `feat/teleprompter` branch, never `main`; ask before pushing.
- Every task ends with a green build + green full test suite before its commit.

## Review Focus

Failure modes the spec implies but the happy path won't exercise. Each has a test in the owning task.

1. **Empty or whitespace-only script, then Play** must be a no-op (no crash, no divide-by-zero in progress/time). Task 1.
2. **One word wider than the panel** (a long URL) must produce a single overflowing line, not an infinite loop or duplicate line starts. Task 4.
3. **WPM changed mid-play** must not make the text jump. Task 1.
4. **Script edited or replaced while playing** must stop and reset to the top, not scroll past the new end. Task 5.
5. **Dropped/picked file that is the wrong type, empty, or not UTF-8** must show a message and leave the current script untouched. Task 3 (importer) and Task 7 (pane).

---

## File Structure

| File | Responsibility |
|---|---|
| `Atelier/Notch/TeleprompterScript.swift` (new, pure) | text -> words + paragraph ranges |
| `Atelier/Notch/TeleprompterScroll.swift` (new, pure) | time-anchored position, WPM, progress, time remaining |
| `Atelier/Notch/TeleprompterLines.swift` (new, pure) | line starts <-> fractional line position, visible window |
| `Atelier/Notch/TeleprompterHoldOpen.swift` (new, pure) | should hover-out be ignored |
| `Atelier/Teleprompter/ScriptImporter.swift` (new) | `.txt/.md/.doc/.docx/.rtf` -> plain text |
| `Atelier/Teleprompter/ScriptStore.swift` (new) | one script file in Application Support |
| `Atelier/Teleprompter/TeleprompterLineWrapper.swift` (new) | CoreText wrapping + font helpers |
| `Atelier/Teleprompter/TeleprompterModel.swift` (new) | observable state, play/pause/WPM/pointer logic |
| `Atelier/Teleprompter/GlobalHotkeys.swift` (new) | Carbon hotkeys |
| `Atelier/UI/TeleprompterPageView.swift` (new) | reading view |
| `Atelier/UI/TeleprompterControlStrip.swift` (new) | play/pause, speed menu, ghost icon, ring |
| `Atelier/UI/TeleprompterRing.swift` (new) | progress ring with centered time |
| `Atelier/Settings/Panes/TeleprompterPane.swift` (new) | editor, file drop, options |
| Modified: `NotchPage.swift`, `AtelierSettings.swift`, `NotchViewModel.swift`, `NotchController.swift`, `NotchRootView.swift`, `NotchLayout.swift`, `NotchTabBar.swift`, `TabsPane.swift`, `SettingsView.swift`, `AtelierApp.swift`, docs | wiring |
| Tests (new, in `AtelierTests/`): `TeleprompterScriptTests`, `TeleprompterScrollTests`, `TeleprompterLinesTests`, `TeleprompterHoldOpenTests`, `ScriptImporterTests`, `ScriptStoreTests`, `TeleprompterLineWrapperTests`, `TeleprompterModelTests` | |

The Xcode project uses synchronized folders, so new files under `Atelier/` and `AtelierTests/` are picked up automatically (no `.pbxproj` edits).

---

### Task 1: Pure scroll logic (script, scroll, lines)

**Files:**
- Create: `Atelier/Notch/TeleprompterScript.swift`, `Atelier/Notch/TeleprompterScroll.swift`, `Atelier/Notch/TeleprompterLines.swift`
- Test: `AtelierTests/TeleprompterScriptTests.swift`, `AtelierTests/TeleprompterScrollTests.swift`, `AtelierTests/TeleprompterLinesTests.swift`

**Interfaces:**
- Produces:
  - `struct TeleprompterScript: Equatable { let words: [String]; let paragraphs: [Range<Int>]; var wordCount: Int; var isEmpty: Bool; init(text: String) }`
  - `struct TeleprompterScroll: Equatable { static let wpmRange: ClosedRange<Double>; static let defaultWPM: Double; private(set) var totalWords: Int; private(set) var wpm: Double; init(totalWords: Int, wpm: Double = defaultWPM); func position(at: Date) -> Double; func progress(at: Date) -> Double; func isFinished(at: Date) -> Bool; func isPlaying(at: Date) -> Bool; func secondsRemaining(at: Date) -> TimeInterval; func secondsElapsed(at: Date) -> TimeInterval; var secondsTotal: TimeInterval; mutating func play(at: Date); mutating func pause(at: Date); mutating func setWPM(_ wpm: Double, at: Date); mutating func seek(to word: Double, at: Date); mutating func settle(at: Date) }`
  - `struct TeleprompterLines: Equatable { let starts: [Int]; let totalWords: Int; static let empty; var count: Int; func linePosition(forWord: Double) -> Double; func currentLine(forWord: Double) -> Int; func visibleLines(around: Double, behind: Int, ahead: Int) -> Range<Int> }`

- [ ] **Step 1: Write the failing tests**

`AtelierTests/TeleprompterScriptTests.swift`:
```swift
import Testing
@testable import Atelier

struct TeleprompterScriptTests {
    @Test func emptyTextHasNoWords() {
        let script = TeleprompterScript(text: "")
        #expect(script.isEmpty)
        #expect(script.wordCount == 0)
        #expect(script.paragraphs.isEmpty)
    }

    @Test func whitespaceOnlyIsEmpty() {
        let script = TeleprompterScript(text: "  \n\t\n   \n")
        #expect(script.isEmpty)
    }

    @Test func eachNonEmptyLineIsAParagraph() {
        let script = TeleprompterScript(text: "hello world\n\nsecond line here")
        #expect(script.words == ["hello", "world", "second", "line", "here"])
        #expect(script.paragraphs == [0..<2, 2..<5])
        #expect(script.wordCount == 5)
    }

    @Test func crlfAndExtraSpacesAreHandled() {
        let script = TeleprompterScript(text: "one   two\r\nthree")
        #expect(script.words == ["one", "two", "three"])
        #expect(script.paragraphs == [0..<2, 2..<3])
    }
}
```

`AtelierTests/TeleprompterScrollTests.swift`:
```swift
import Testing
import Foundation
@testable import Atelier

struct TeleprompterScrollTests {
    private let t0 = Date(timeIntervalSinceReferenceDate: 1_000)

    @Test func pausedPositionIsTheAnchor() {
        let scroll = TeleprompterScroll(totalWords: 100, wpm: 120)
        #expect(scroll.position(at: t0) == 0)
        #expect(scroll.position(at: t0.addingTimeInterval(99)) == 0)
        #expect(!scroll.isPlaying(at: t0))
    }

    @Test func playingAdvancesAtWPM() {
        var scroll = TeleprompterScroll(totalWords: 1_000, wpm: 120)
        scroll.play(at: t0)
        #expect(scroll.isPlaying(at: t0))
        // 120 words/min = 2 words/sec -> 30s = 60 words.
        #expect(scroll.position(at: t0.addingTimeInterval(30)) == 60)
    }

    @Test func pauseKeepsTheReachedPosition() {
        var scroll = TeleprompterScroll(totalWords: 1_000, wpm: 120)
        scroll.play(at: t0)
        scroll.pause(at: t0.addingTimeInterval(30))
        #expect(scroll.position(at: t0.addingTimeInterval(500)) == 60)
        #expect(!scroll.isPlaying(at: t0.addingTimeInterval(500)))
    }

    // Review Focus 3: changing speed mid-play must not make the text jump.
    @Test func changingWPMMidPlayDoesNotJump() {
        var scroll = TeleprompterScroll(totalWords: 1_000, wpm: 120)
        scroll.play(at: t0)
        let mid = t0.addingTimeInterval(30)
        scroll.setWPM(60, at: mid)
        #expect(scroll.position(at: mid) == 60)
        // 60 wpm = 1 word/sec -> 30 more seconds = 30 more words.
        #expect(scroll.position(at: mid.addingTimeInterval(30)) == 90)
    }

    @Test func wpmIsClampedToTheSupportedRange() {
        var scroll = TeleprompterScroll(totalWords: 100)
        scroll.setWPM(10, at: t0)
        #expect(scroll.wpm == 50)
        scroll.setWPM(999, at: t0)
        #expect(scroll.wpm == 300)
    }

    @Test func positionClampsAtTheEndAndReportsFinished() {
        var scroll = TeleprompterScroll(totalWords: 10, wpm: 60)
        scroll.play(at: t0)
        let late = t0.addingTimeInterval(100)
        #expect(scroll.position(at: late) == 10)
        #expect(scroll.isFinished(at: late))
        #expect(!scroll.isPlaying(at: late))
    }

    @Test func settleFreezesAFinishedScript() {
        var scroll = TeleprompterScroll(totalWords: 10, wpm: 60)
        scroll.play(at: t0)
        scroll.settle(at: t0.addingTimeInterval(100))
        #expect(scroll.position(at: t0.addingTimeInterval(9_999)) == 10)
    }

    @Test func playAtTheEndRestartsFromTheTop() {
        var scroll = TeleprompterScroll(totalWords: 10, wpm: 60)
        scroll.play(at: t0)
        let late = t0.addingTimeInterval(100)
        scroll.play(at: late)
        #expect(scroll.position(at: late) == 0)
        #expect(scroll.isPlaying(at: late))
    }

    // Review Focus 1: an empty script can't play and never divides by zero.
    @Test func emptyScriptCannotPlayAndHasZeroProgress() {
        var scroll = TeleprompterScroll(totalWords: 0, wpm: 120)
        scroll.play(at: t0)
        #expect(!scroll.isPlaying(at: t0))
        #expect(scroll.progress(at: t0) == 0)
        #expect(scroll.secondsRemaining(at: t0) == 0)
        #expect(!scroll.isFinished(at: t0))
    }

    @Test func seekClampsAndKeepsPlayingState() {
        var scroll = TeleprompterScroll(totalWords: 100, wpm: 120)
        scroll.seek(to: 500, at: t0)
        #expect(scroll.position(at: t0) == 100)
        scroll.seek(to: -5, at: t0)
        #expect(scroll.position(at: t0) == 0)

        scroll.play(at: t0)
        scroll.seek(to: 50, at: t0.addingTimeInterval(10))
        #expect(scroll.isPlaying(at: t0.addingTimeInterval(10)))
        #expect(scroll.position(at: t0.addingTimeInterval(20)) == 70)
    }

    @Test func timesAreDerivedFromWPM() {
        var scroll = TeleprompterScroll(totalWords: 120, wpm: 120)
        #expect(scroll.secondsTotal == 60)
        #expect(scroll.secondsRemaining(at: t0) == 60)
        scroll.play(at: t0)
        #expect(scroll.secondsElapsed(at: t0.addingTimeInterval(15)) == 15)
        #expect(scroll.secondsRemaining(at: t0.addingTimeInterval(15)) == 45)
        #expect(scroll.progress(at: t0.addingTimeInterval(30)) == 0.5)
    }
}
```

`AtelierTests/TeleprompterLinesTests.swift`:
```swift
import Testing
@testable import Atelier

struct TeleprompterLinesTests {
    // Three lines starting at words 0, 4 and 9 of a 12-word script.
    private let lines = TeleprompterLines(starts: [0, 4, 9], totalWords: 12)

    @Test func emptyLinesAreSafe() {
        #expect(TeleprompterLines.empty.linePosition(forWord: 5) == 0)
        #expect(TeleprompterLines.empty.currentLine(forWord: 5) == 0)
        #expect(TeleprompterLines.empty.visibleLines(around: 0, behind: 2, ahead: 3) == 0..<0)
    }

    @Test func linePositionInterpolatesWithinALine() {
        #expect(lines.linePosition(forWord: 0) == 0)
        #expect(lines.linePosition(forWord: 2) == 0.5)
        #expect(lines.linePosition(forWord: 4) == 1)
        #expect(lines.linePosition(forWord: 6.5) == 1.5)
    }

    @Test func linePositionAtTheEndIsPastTheLastLine() {
        #expect(lines.linePosition(forWord: 12) == 3)
        #expect(lines.linePosition(forWord: 999) == 3)
        #expect(lines.linePosition(forWord: -3) == 0)
    }

    @Test func currentLineIsClampedToARealLine() {
        #expect(lines.currentLine(forWord: 0) == 0)
        #expect(lines.currentLine(forWord: 5) == 1)
        #expect(lines.currentLine(forWord: 12) == 2)
    }

    @Test func visibleWindowIsClampedToTheLineCount() {
        #expect(lines.visibleLines(around: 1.5, behind: 2, ahead: 3) == 0..<3)
        let many = TeleprompterLines(starts: Array(0..<10).map { $0 * 3 }, totalWords: 30)
        #expect(many.visibleLines(around: 5.2, behind: 2, ahead: 3) == 3..<9)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme Atelier -destination 'platform=macOS' -only-testing:AtelierTests/TeleprompterScriptTests -only-testing:AtelierTests/TeleprompterScrollTests -only-testing:AtelierTests/TeleprompterLinesTests 2>&1 | tail -15`
Expected: build FAILS with "cannot find 'TeleprompterScript' in scope" (and the other two types).

- [ ] **Step 3: Write the implementation**

`Atelier/Notch/TeleprompterScript.swift`:
```swift
import Foundation

/// A script split into words, plus which words start a new line of the
/// source text. Every non-empty source line is one "paragraph" and always
/// begins a new display line (scripts are usually typed one sentence per
/// line); blank lines are ignored. Pure and Foundation-only (Invariant 1).
struct TeleprompterScript: Equatable {
    let words: [String]
    /// Word-index ranges, one per non-empty source line, in order.
    let paragraphs: [Range<Int>]

    var wordCount: Int { words.count }
    var isEmpty: Bool { words.isEmpty }

    init(text: String) {
        var words: [String] = []
        var paragraphs: [Range<Int>] = []
        for line in text.split(whereSeparator: \.isNewline) {
            let lineWords = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard !lineWords.isEmpty else { continue }
            paragraphs.append(words.count ..< words.count + lineWords.count)
            words.append(contentsOf: lineWords)
        }
        self.words = words
        self.paragraphs = paragraphs
    }
}
```

`Atelier/Notch/TeleprompterScroll.swift`:
```swift
import Foundation

/// Where the script is, as a fractional word index, derived from a start
/// date instead of a mutating tick: `position(at:)` is a pure function of
/// time, so the view can ask "where are we now?" on every frame without
/// any timer writing state. Pausing, changing speed, or seeking "re-anchors"
/// (bakes the current position in) so nothing ever jumps. Pure and
/// Foundation-only (Invariant 1); the stage-4 speech source drives it via
/// `seek(to:at:)` instead of the clock.
struct TeleprompterScroll: Equatable {
    static let wpmRange: ClosedRange<Double> = 50...300
    static let defaultWPM: Double = 140

    private(set) var totalWords: Int
    private(set) var wpm: Double
    private var anchorPosition: Double = 0
    /// Non-nil while playing: the moment `anchorPosition` was true.
    private var anchorDate: Date?

    init(totalWords: Int, wpm: Double = TeleprompterScroll.defaultWPM) {
        self.totalWords = max(0, totalWords)
        self.wpm = Self.clamped(wpm)
    }

    private static func clamped(_ wpm: Double) -> Double {
        min(max(wpm, wpmRange.lowerBound), wpmRange.upperBound)
    }

    func position(at date: Date) -> Double {
        guard let anchorDate else { return anchorPosition }
        let elapsed = max(0, date.timeIntervalSince(anchorDate))
        return min(Double(totalWords), anchorPosition + elapsed * wpm / 60)
    }

    func progress(at date: Date) -> Double {
        guard totalWords > 0 else { return 0 }
        return position(at: date) / Double(totalWords)
    }

    func isFinished(at date: Date) -> Bool {
        totalWords > 0 && position(at: date) >= Double(totalWords)
    }

    /// Playing means running and not yet at the end.
    func isPlaying(at date: Date) -> Bool {
        anchorDate != nil && !isFinished(at: date)
    }

    var secondsTotal: TimeInterval { Double(totalWords) / wpm * 60 }

    func secondsElapsed(at date: Date) -> TimeInterval {
        position(at: date) / wpm * 60
    }

    func secondsRemaining(at date: Date) -> TimeInterval {
        max(0, Double(totalWords) - position(at: date)) / wpm * 60
    }

    mutating func play(at date: Date) {
        guard totalWords > 0 else { return }
        if isFinished(at: date) {
            anchorPosition = 0
        } else if anchorDate != nil {
            return
        }
        anchorDate = date
    }

    mutating func pause(at date: Date) {
        anchorPosition = position(at: date)
        anchorDate = nil
    }

    mutating func setWPM(_ newWPM: Double, at date: Date) {
        if anchorDate != nil {
            anchorPosition = position(at: date)
            anchorDate = date
        }
        wpm = Self.clamped(newWPM)
    }

    mutating func seek(to word: Double, at date: Date) {
        anchorPosition = min(max(word, 0), Double(totalWords))
        if anchorDate != nil { anchorDate = date }
    }

    /// Freezes a script that has run off the end so it stops being "playing".
    mutating func settle(at date: Date) {
        guard isFinished(at: date) else { return }
        anchorPosition = Double(totalWords)
        anchorDate = nil
    }
}
```

`Atelier/Notch/TeleprompterLines.swift`:
```swift
import Foundation

/// Where each *display* line starts (a word index), for whatever width and
/// font the view is using. Turns a word position into a fractional line
/// position (integer part = line, fraction = progress through it), which
/// is what drives the smooth vertical glide and the Focus Guide. The
/// wrapping itself (needs fonts) lives in `TeleprompterLineWrapper`; this
/// type stays pure (Invariant 1).
struct TeleprompterLines: Equatable {
    /// Ascending; `starts[0] == 0` when there is any text.
    let starts: [Int]
    let totalWords: Int

    static let empty = TeleprompterLines(starts: [], totalWords: 0)

    var count: Int { starts.count }

    func linePosition(forWord word: Double) -> Double {
        guard !starts.isEmpty else { return 0 }
        let clamped = min(max(word, 0), Double(totalWords))
        // Largest index whose start is <= clamped.
        var lo = 0
        var hi = starts.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if Double(starts[mid]) <= clamped { lo = mid } else { hi = mid - 1 }
        }
        let lineStart = Double(starts[lo])
        let lineEnd = lo + 1 < starts.count ? Double(starts[lo + 1]) : Double(totalWords)
        let span = lineEnd - lineStart
        let fraction = span > 0 ? (clamped - lineStart) / span : 0
        return Double(lo) + min(fraction, 1)
    }

    func currentLine(forWord word: Double) -> Int {
        guard !starts.isEmpty else { return 0 }
        return min(Int(linePosition(forWord: word)), starts.count - 1)
    }

    /// The lines worth building views for, so a 5,000-word script renders
    /// a handful of `Text`s, not thousands.
    func visibleLines(around linePosition: Double, behind: Int, ahead: Int) -> Range<Int> {
        guard !starts.isEmpty else { return 0..<0 }
        let current = min(max(Int(linePosition), 0), starts.count - 1)
        return max(0, current - behind) ..< min(starts.count, current + ahead + 1)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run the same command as Step 2. Expected: all three suites PASS.

- [ ] **Step 5: Full build + suite, then commit**

Run: `xcodebuild -scheme Atelier -configuration Debug build 2>&1 | tail -3 && xcodebuild test -scheme Atelier -destination 'platform=macOS' 2>&1 | grep -E "Test run|TEST (SUCCEEDED|FAILED)"`
Expected: `BUILD SUCCEEDED`, all tests pass (163 existing + the new ones).

```bash
git add Atelier/Notch/Teleprompter*.swift AtelierTests/Teleprompter*.swift
git commit -m "feat(teleprompter): pure script, scroll and line logic (stage 1)

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 2: `NotchPage.teleprompter`, settings keys, hold-open rule

**Files:**
- Create: `Atelier/Notch/TeleprompterHoldOpen.swift`
- Modify: `Atelier/Notch/NotchPage.swift` (enum), `Atelier/AtelierSettings.swift`, `Atelier/UI/NotchTabBar.swift:80-92`, `Atelier/Settings/Panes/TabsPane.swift:115-150`
- Test: `AtelierTests/TeleprompterHoldOpenTests.swift`

**Interfaces:**
- Consumes: `NotchPage`, `NotchState`.
- Produces:
  - `NotchPage.teleprompter`
  - `TeleprompterHoldOpen.shouldSuppressRetract(isPlaying: Bool, currentPage: NotchPage, state: NotchState) -> Bool`
  - `AtelierSettings`: `teleprompterEnabledKey`, `teleprompterWPMKey`, `teleprompterMonoFontKey`, `teleprompterFontSizeKey`, `teleprompterPauseOnHoverKey`, `teleprompterHotkeysKey`, `ghostModeKey`, and `static var teleprompterEnabled: Bool`, `teleprompterWPM: Double { get set }`, `teleprompterMonoFont: Bool`, `teleprompterFontSize: Double`, `teleprompterPauseOnHover: Bool`, `teleprompterHotkeysEnabled: Bool`, `ghostModeEnabled: Bool`.

- [ ] **Step 1: Write the failing test**

`AtelierTests/TeleprompterHoldOpenTests.swift`:
```swift
import Testing
@testable import Atelier

struct TeleprompterHoldOpenTests {
    @Test func suppressesWhilePlayingOnTheTeleprompterPageExpanded() {
        #expect(TeleprompterHoldOpen.shouldSuppressRetract(isPlaying: true, currentPage: .teleprompter, state: .expanded))
    }

    @Test func doesNotSuppressWhenPaused() {
        #expect(!TeleprompterHoldOpen.shouldSuppressRetract(isPlaying: false, currentPage: .teleprompter, state: .expanded))
    }

    @Test func doesNotSuppressOnOtherPages() {
        #expect(!TeleprompterHoldOpen.shouldSuppressRetract(isPlaying: true, currentPage: .home, state: .expanded))
    }

    @Test func doesNotSuppressOutsideExpanded() {
        #expect(!TeleprompterHoldOpen.shouldSuppressRetract(isPlaying: true, currentPage: .teleprompter, state: .peeking))
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `xcodebuild test -scheme Atelier -destination 'platform=macOS' -only-testing:AtelierTests/TeleprompterHoldOpenTests 2>&1 | tail -8`
Expected: FAIL to compile (`teleprompter` not a member of `NotchPage`).

- [ ] **Step 3: Implement**

`Atelier/Notch/NotchPage.swift` — add the case after `camera`:
```swift
    case camera
    case teleprompter
}
```

`Atelier/Notch/TeleprompterHoldOpen.swift`:
```swift
import Foundation

/// Whether a hover-out should be ignored so the script keeps scrolling.
/// Pure and Foundation-only like `CameraHoldOpen`: `NotchStateMachine`
/// doesn't learn about the teleprompter. Only hover-out consults this; an
/// explicit swipe-close or tab change still closes and pauses. Unlike the
/// camera there is no setting: retracting mid-read is never wanted.
enum TeleprompterHoldOpen {
    static func shouldSuppressRetract(
        isPlaying: Bool,
        currentPage: NotchPage,
        state: NotchState
    ) -> Bool {
        isPlaying && currentPage == .teleprompter && state == .expanded
    }
}
```

`Atelier/AtelierSettings.swift` — add keys next to `cameraHoldOpenKey` (line ~14):
```swift
    static let teleprompterEnabledKey = "teleprompterEnabled"
    static let teleprompterWPMKey = "teleprompterWPM"
    static let teleprompterMonoFontKey = "teleprompterMonoFont"
    static let teleprompterFontSizeKey = "teleprompterFontSize"
    static let teleprompterPauseOnHoverKey = "teleprompterPauseOnHover"
    static let teleprompterHotkeysKey = "teleprompterHotkeys"
    static let ghostModeKey = "ghostMode"
```
Add to `registerDefaults()` (inside the dictionary, after `cameraEnabledKey: true,`):
```swift
            teleprompterEnabledKey: true,
            teleprompterWPMKey: TeleprompterScroll.defaultWPM,
            teleprompterFontSizeKey: 15.0,
            teleprompterPauseOnHoverKey: true,
```
Add accessors after `cameraHoldOpen`:
```swift
    static var teleprompterEnabled: Bool {
        UserDefaults.standard.bool(forKey: teleprompterEnabledKey)
    }

    /// Falls back to the default rather than 0 if defaults were never
    /// registered (unit tests that don't launch `AtelierApp`).
    static var teleprompterWPM: Double {
        get {
            let stored = UserDefaults.standard.double(forKey: teleprompterWPMKey)
            return stored == 0 ? TeleprompterScroll.defaultWPM : stored
        }
        set { UserDefaults.standard.set(newValue, forKey: teleprompterWPMKey) }
    }

    /// Sans bold is the default; mono is a Settings option.
    static var teleprompterMonoFont: Bool {
        UserDefaults.standard.bool(forKey: teleprompterMonoFontKey)
    }

    static var teleprompterFontSize: Double {
        let stored = UserDefaults.standard.double(forKey: teleprompterFontSizeKey)
        return stored == 0 ? 15 : stored
    }

    /// Pause while the pointer is over the notch, resume when it leaves.
    static var teleprompterPauseOnHover: Bool {
        UserDefaults.standard.bool(forKey: teleprompterPauseOnHoverKey)
    }

    /// Off by default: global shortcuts take keys from other apps, so
    /// they're opt-in.
    static var teleprompterHotkeysEnabled: Bool {
        UserDefaults.standard.bool(forKey: teleprompterHotkeysKey)
    }

    /// Hides the whole notch panel from screen sharing and recording
    /// (`NSWindow.sharingType = .none`, applied by `NotchController`).
    static var ghostModeEnabled: Bool {
        UserDefaults.standard.bool(forKey: ghostModeKey)
    }
```
In `enabledPages` add after the camera line:
```swift
        if teleprompterEnabled { pages.insert(.teleprompter) }
```

`Atelier/UI/NotchTabBar.swift` — in `accessibilityName` add `case .teleprompter: "Teleprompter"`.

`Atelier/Settings/Panes/TabsPane.swift` — add to the three switches:
```swift
        case .teleprompter: "Teleprompter"        // title
        case .teleprompter: "text.alignleft"      // symbol
        case .teleprompter: AtelierSettings.teleprompterEnabledKey   // enabledKey
```

- [ ] **Step 4: Build; fix any other exhaustive `switch` on `NotchPage`**

Run: `xcodebuild -scheme Atelier -configuration Debug build 2>&1 | grep -E "error:|BUILD"`
Expected: `BUILD SUCCEEDED`. If the compiler reports "switch must be exhaustive" anywhere else, add the `.teleprompter` case there with the analogous value (there should be none beyond the three above).

- [ ] **Step 5: Run the full suite**

Run: `xcodebuild test -scheme Atelier -destination 'platform=macOS' 2>&1 | grep -E "Test run|TEST (SUCCEEDED|FAILED)|✘"`
Expected: all pass. If `TabOrderTests` or `NotchPageTransitionTests` hard-code the list of pages, add `.teleprompter` to the expected values (it is appended last by `NotchPage.allCases`).

- [ ] **Step 6: Commit**

```bash
git add -A Atelier AtelierTests
git commit -m "feat(teleprompter): NotchPage.teleprompter, settings keys, hold-open rule (stage 1)

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 3: Script import and storage

**Files:**
- Create: `Atelier/Teleprompter/ScriptImporter.swift`, `Atelier/Teleprompter/ScriptStore.swift`
- Test: `AtelierTests/ScriptImporterTests.swift`, `AtelierTests/ScriptStoreTests.swift`

**Interfaces:**
- Produces:
  - `enum ScriptImporter { static let supportedExtensions: Set<String>; enum ImportError: Error, Equatable { case unsupportedType(String), unreadable, empty; var message: String }; static func importText(from url: URL) throws -> String; static func stripMarkdown(_ text: String) -> String }`
  - `@MainActor final class ScriptStore { static let didChange: Notification.Name; static let shared: ScriptStore; static var defaultDirectory: URL; init(directory: URL); func load() -> String; func save(_ text: String) throws }`

- [ ] **Step 1: Write the failing tests**

`AtelierTests/ScriptImporterTests.swift`:
```swift
import Testing
import AppKit
@testable import Atelier

struct ScriptImporterTests {
    private func tempFile(_ name: String, data: Data) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AtelierImporterTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    @Test func plainTextIsReadAndTrimmed() throws {
        let url = try tempFile("a.txt", data: Data("  Hello there\nsecond line \n\n".utf8))
        #expect(try ScriptImporter.importText(from: url) == "Hello there\nsecond line")
    }

    @Test func markdownIsStrippedToSpeakableText() throws {
        let md = "# Title\n\n**Bold** and *italic* with [a link](http://x.com).\n- item one\n1. item two\n"
        let url = try tempFile("a.md", data: Data(md.utf8))
        let text = try ScriptImporter.importText(from: url)
        #expect(text == "Title\n\nBold and italic with a link.\nitem one\nitem two")
    }

    @Test func markdownKeepsSnakeCaseAndDropsFencesAndRules() {
        let md = "use my_var_name here\n```\ncode line\n```\n---\nend"
        #expect(ScriptImporter.stripMarkdown(md) == "use my_var_name here\ncode line\nend")
    }

    @Test func rtfRoundTrips() throws {
        let attributed = NSAttributedString(string: "Rich text script")
        let data = try attributed.data(
            from: NSRange(location: 0, length: attributed.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
        let url = try tempFile("a.rtf", data: data)
        #expect(try ScriptImporter.importText(from: url) == "Rich text script")
    }

    // Review Focus 5: bad files raise a specific error and never crash.
    @Test func unsupportedExtensionIsRejected() throws {
        let url = try tempFile("a.pdf", data: Data("x".utf8))
        #expect(throws: ScriptImporter.ImportError.unsupportedType("pdf")) {
            try ScriptImporter.importText(from: url)
        }
    }

    @Test func emptyFileIsRejected() throws {
        let url = try tempFile("a.txt", data: Data("  \n\n".utf8))
        #expect(throws: ScriptImporter.ImportError.empty) {
            try ScriptImporter.importText(from: url)
        }
    }

    @Test func nonUTF8TextFallsBackToDetectedEncoding() throws {
        // "café script" in ISO Latin-1: the 0xE9 byte is invalid UTF-8.
        let url = try tempFile("a.txt", data: Data([0x63, 0x61, 0x66, 0xE9, 0x20, 0x73, 0x63, 0x72, 0x69, 0x70, 0x74]))
        let text = try ScriptImporter.importText(from: url)
        #expect(text.hasSuffix("script"))
    }

    @Test func missingFileIsUnreadable() {
        let url = URL(fileURLWithPath: "/nonexistent/atelier-\(UUID().uuidString).txt")
        #expect(throws: ScriptImporter.ImportError.unreadable) {
            try ScriptImporter.importText(from: url)
        }
    }

    @Test func brokenDocxIsUnreadableNotACrash() throws {
        let url = try tempFile("a.docx", data: Data("not a zip".utf8))
        #expect(throws: ScriptImporter.ImportError.unreadable) {
            try ScriptImporter.importText(from: url)
        }
    }
}
```

`AtelierTests/ScriptStoreTests.swift`:
```swift
import Testing
import Foundation
@testable import Atelier

@MainActor
struct ScriptStoreTests {
    private func makeTempDir() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("AtelierScriptStoreTests-\(UUID().uuidString)")
    }

    @Test func loadOfMissingScriptIsEmpty() {
        #expect(ScriptStore(directory: makeTempDir()).load() == "")
    }

    @Test func saveThenLoadRoundTrips() throws {
        let store = ScriptStore(directory: makeTempDir())
        try store.save("Line one\nLine two")
        #expect(store.load() == "Line one\nLine two")
    }

    @Test func aFreshStoreOnTheSameDirectoryReadsTheSavedScript() throws {
        let dir = makeTempDir()
        try ScriptStore(directory: dir).save("persisted")
        #expect(ScriptStore(directory: dir).load() == "persisted")
    }

    @Test func savePostsDidChange() throws {
        let store = ScriptStore(directory: makeTempDir())
        var fired = false
        let token = NotificationCenter.default.addObserver(forName: ScriptStore.didChange, object: store, queue: nil) { _ in fired = true }
        defer { NotificationCenter.default.removeObserver(token) }
        try store.save("x")
        #expect(fired)
    }
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `xcodebuild test -scheme Atelier -destination 'platform=macOS' -only-testing:AtelierTests/ScriptImporterTests -only-testing:AtelierTests/ScriptStoreTests 2>&1 | tail -8`
Expected: FAIL to compile (`ScriptImporter`, `ScriptStore` not found).

- [ ] **Step 3: Implement**

`Atelier/Teleprompter/ScriptImporter.swift`:
```swift
import AppKit

/// Turns a dropped/picked file into plain script text. `.txt`/`.md` are
/// read directly (Markdown syntax stripped); `.rtf`/`.doc`/`.docx` go
/// through `NSAttributedString`'s document importer, which is why no
/// third-party dependency is needed. Manual-verification only for real
/// Word files; the text and RTF paths are unit-tested.
enum ScriptImporter {
    static let supportedExtensions: Set<String> = ["txt", "md", "markdown", "rtf", "doc", "docx"]

    enum ImportError: Error, Equatable {
        case unsupportedType(String)
        case unreadable
        case empty

        /// Shown in the Settings pane.
        var message: String {
            switch self {
            case .unsupportedType: "Only .txt, .md, .doc, .docx and .rtf files work here"
            case .unreadable: "Couldn't read that file"
            case .empty: "That file has no text in it"
            }
        }
    }

    static func importText(from url: URL) throws -> String {
        let ext = url.pathExtension.lowercased()
        guard supportedExtensions.contains(ext) else { throw ImportError.unsupportedType(ext) }

        let raw: String
        switch ext {
        case "txt": raw = try readPlain(url)
        case "md", "markdown": raw = stripMarkdown(try readPlain(url))
        default: raw = try readRich(url, ext: ext)
        }

        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ImportError.empty }
        return trimmed
    }

    private static func readPlain(_ url: URL) throws -> String {
        if let text = try? String(contentsOf: url, encoding: .utf8) { return text }
        // Not UTF-8: let Foundation detect the encoding (Latin-1, UTF-16...).
        var used = String.Encoding.utf8
        guard let text = try? String(contentsOf: url, usedEncoding: &used) else { throw ImportError.unreadable }
        return text
    }

    private static func readRich(_ url: URL, ext: String) throws -> String {
        let type: NSAttributedString.DocumentType = switch ext {
        case "rtf": .rtf
        case "doc": .docFormat
        default: .officeOpenXML
        }
        guard let attributed = try? NSAttributedString(url: url, options: [.documentType: type], documentAttributes: nil) else {
            throw ImportError.unreadable
        }
        return attributed.string
    }

    /// Light Markdown stripping: this is text to read aloud, not to render.
    /// Keeps content, drops the syntax around it.
    static func stripMarkdown(_ text: String) -> String {
        var inFence = false
        var out: [String] = []
        for rawLine in text.components(separatedBy: .newlines) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") { inFence.toggle(); continue }
            if inFence { out.append(rawLine); continue }
            if trimmed.range(of: #"^(-{3,}|\*{3,}|_{3,})$"#, options: .regularExpression) != nil { continue }

            var line = rawLine
            line = line.replacingOccurrences(of: #"^\s{0,3}#{1,6}\s+"#, with: "", options: .regularExpression)
            line = line.replacingOccurrences(of: #"^\s*>\s?"#, with: "", options: .regularExpression)
            line = line.replacingOccurrences(of: #"^\s*([-*+]|\d+\.)\s+"#, with: "", options: .regularExpression)
            line = line.replacingOccurrences(of: #"!\[([^\]]*)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
            line = line.replacingOccurrences(of: #"\[([^\]]*)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
            line = line.replacingOccurrences(of: #"(\*\*|__)(.+?)\1"#, with: "$2", options: .regularExpression)
            line = line.replacingOccurrences(of: #"\*(.+?)\*"#, with: "$1", options: .regularExpression)
            // Underscore emphasis only at word edges, so snake_case survives.
            line = line.replacingOccurrences(of: #"(?<!\w)_(.+?)_(?!\w)"#, with: "$1", options: .regularExpression)
            line = line.replacingOccurrences(of: "`", with: "")
            out.append(line)
        }
        return out.joined(separator: "\n")
    }
}
```

`Atelier/Teleprompter/ScriptStore.swift`:
```swift
import Foundation

/// Owns the one script the teleprompter reads: a plain-text file in
/// Application Support. `directory` is injected (like `ShelfStore`) so
/// tests use a real temp directory instead of a mock. The script library
/// (folders + search) later grows this into `ShelfStore`'s JSON-manifest
/// shape; for now a single file is all that's needed.
@MainActor
final class ScriptStore {
    /// Posted after every successful save so the model reloads.
    static let didChange = Notification.Name("AtelierTeleprompterScriptDidChange")

    static var defaultDirectory: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Atelier", isDirectory: true)
            .appendingPathComponent("Teleprompter", isDirectory: true)
    }

    static let shared = ScriptStore(directory: ScriptStore.defaultDirectory)

    let directory: URL
    private var fileURL: URL { directory.appendingPathComponent("script.txt") }

    init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func load() -> String {
        (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
    }

    func save(_ text: String) throws {
        try text.write(to: fileURL, atomically: true, encoding: .utf8)
        // `object: self` so a store's observers (and parallel tests) never
        // hear about a different store's saves.
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }
}
```

- [ ] **Step 4: Run to verify they pass**

Run the Step 2 command. Expected: PASS. If `brokenDocxIsUnreadableNotACrash` reports a different outcome on this macOS (some versions return an empty string instead of throwing), change that one expectation to `.empty` and add a one-line comment saying which behavior macOS 26 shows. Do not weaken the other tests.

- [ ] **Step 5: Full build + suite, commit**

Run the Task 1 Step 5 commands. Expected: green.
```bash
git add Atelier/Teleprompter AtelierTests/ScriptImporterTests.swift AtelierTests/ScriptStoreTests.swift
git commit -m "feat(teleprompter): script import (txt/md/rtf/doc/docx) and store (stage 1)

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 4: Line wrapper (CoreText)

**Files:**
- Create: `Atelier/Teleprompter/TeleprompterLineWrapper.swift`
- Test: `AtelierTests/TeleprompterLineWrapperTests.swift`

**Interfaces:**
- Consumes: `TeleprompterScript`, `TeleprompterLines`.
- Produces:
  - `enum TeleprompterFont { static func nsFont(size: Double, mono: Bool) -> NSFont; static func swiftUIFont(size: Double, mono: Bool) -> Font }`
  - `enum TeleprompterLineWrapper { static func lines(for script: TeleprompterScript, font: NSFont, width: CGFloat) -> TeleprompterLines }`

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import AppKit
@testable import Atelier

struct TeleprompterLineWrapperTests {
    private let font = TeleprompterFont.nsFont(size: 15, mono: false)
    private let sentence = "The quick brown fox jumps over the lazy dog and keeps on running far away"

    @Test func narrowerWidthMakesMoreLines() {
        let script = TeleprompterScript(text: sentence)
        let wide = TeleprompterLineWrapper.lines(for: script, font: font, width: 600)
        let narrow = TeleprompterLineWrapper.lines(for: script, font: font, width: 120)
        #expect(wide.count == 1)
        #expect(narrow.count > wide.count)
        #expect(narrow.totalWords == script.wordCount)
    }

    @Test func startsAreStrictlyAscendingAndBeginAtZero() {
        let script = TeleprompterScript(text: sentence)
        let lines = TeleprompterLineWrapper.lines(for: script, font: font, width: 120)
        #expect(lines.starts.first == 0)
        #expect(zip(lines.starts, lines.starts.dropFirst()).allSatisfy { $0 < $1 })
    }

    @Test func everyParagraphStartsANewLine() {
        let script = TeleprompterScript(text: "short one\nshort two\nshort three")
        let lines = TeleprompterLineWrapper.lines(for: script, font: font, width: 600)
        #expect(lines.starts == [0, 2, 4])
    }

    // Review Focus 2: an unbreakable word wider than the panel is one line.
    @Test func aWordWiderThanTheWidthIsASingleLineWithNoDuplicates() {
        let script = TeleprompterScript(text: "Supercalifragilisticexpialidocious")
        let lines = TeleprompterLineWrapper.lines(for: script, font: font, width: 20)
        #expect(lines.starts == [0])
    }

    @Test func emptyScriptAndZeroWidthAreSafe() {
        #expect(TeleprompterLineWrapper.lines(for: TeleprompterScript(text: ""), font: font, width: 300).count == 0)
        #expect(TeleprompterLineWrapper.lines(for: TeleprompterScript(text: sentence), font: font, width: 0).count == 0)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `xcodebuild test -scheme Atelier -destination 'platform=macOS' -only-testing:AtelierTests/TeleprompterLineWrapperTests 2>&1 | tail -6`
Expected: FAIL to compile.

- [ ] **Step 3: Implement**

`Atelier/Teleprompter/TeleprompterLineWrapper.swift`:
```swift
import AppKit
import CoreText
import SwiftUI

/// The one font the teleprompter uses, in both worlds. The wrapper
/// measures with the `NSFont`; the view draws with the matching SwiftUI
/// font, and each display line is its own single-line `Text`, so SwiftUI
/// never re-wraps what CoreText already wrapped.
enum TeleprompterFont {
    static func nsFont(size: Double, mono: Bool) -> NSFont {
        mono
            ? .monospacedSystemFont(ofSize: size, weight: .bold)
            : .systemFont(ofSize: size, weight: .bold)
    }

    static func swiftUIFont(size: Double, mono: Bool) -> Font {
        .system(size: size, weight: .bold, design: mono ? .monospaced : .default)
    }
}

/// Word-wraps a script into display lines for a width and font using
/// CoreText, and reports where each line starts as a word index. Each
/// source paragraph wraps on its own, so a paragraph always begins a new
/// line. Needs AppKit fonts, so it lives outside the pure `Notch/` layer.
enum TeleprompterLineWrapper {
    static func lines(for script: TeleprompterScript, font: NSFont, width: CGFloat) -> TeleprompterLines {
        guard width > 0, !script.isEmpty else {
            return TeleprompterLines(starts: [], totalWords: script.wordCount)
        }
        var starts: [Int] = []

        for paragraph in script.paragraphs {
            var text = ""
            var wordOffsets: [Int] = []           // UTF-16 offset of each word in `text`
            for (index, word) in script.words[paragraph].enumerated() {
                if index > 0 { text += " " }
                wordOffsets.append(text.utf16.count)
                text += word
            }

            let framesetter = CTFramesetterCreateWithAttributedString(
                NSAttributedString(string: text, attributes: [.font: font])
            )
            let path = CGPath(rect: CGRect(x: 0, y: 0, width: width, height: 1_000_000), transform: nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
            let ctLines = (CTFrameGetLines(frame) as? [CTLine]) ?? []

            for line in ctLines {
                let location = CTLineGetStringRange(line).location
                // Largest word whose offset is <= the line's first character.
                var lo = 0
                var hi = wordOffsets.count - 1
                while lo < hi {
                    let mid = (lo + hi + 1) / 2
                    if wordOffsets[mid] <= location { lo = mid } else { hi = mid - 1 }
                }
                let wordIndex = paragraph.lowerBound + lo
                // A single word wider than `width` is character-wrapped by
                // CoreText into several lines that all map to the same word;
                // keep one line for it (the view lets it overflow and clips).
                if starts.last != wordIndex { starts.append(wordIndex) }
            }
        }
        return TeleprompterLines(starts: starts, totalWords: script.wordCount)
    }
}
```

- [ ] **Step 4: Run to verify pass**

Run the Step 2 command. Expected: PASS.

- [ ] **Step 5: Full build + suite, commit**

```bash
git add Atelier/Teleprompter/TeleprompterLineWrapper.swift AtelierTests/TeleprompterLineWrapperTests.swift
git commit -m "feat(teleprompter): CoreText line wrapper (stage 2)

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 5: `TeleprompterModel`

**Files:**
- Create: `Atelier/Teleprompter/TeleprompterModel.swift`
- Test: `AtelierTests/TeleprompterModelTests.swift`

**Interfaces:**
- Consumes: `ScriptStore`, `TeleprompterScript`, `TeleprompterScroll`, `TeleprompterLines`, `TeleprompterLineWrapper`, `TeleprompterFont`, `AtelierSettings.teleprompterWPM`.
- Produces: `@MainActor final class TeleprompterModel: ObservableObject` with `static let shared`, `@Published private(set) var script: TeleprompterScript`, `lines: TeleprompterLines`, `scroll: TeleprompterScroll`, `isPlaying: Bool`, `pausedForPointer: Bool`, `var wantsNotchOpen: Bool`, and: `init(store: ScriptStore = .shared, persistsWPM: Bool = true)`, `reloadScript()`, `updateLayout(width: CGFloat, fontSize: Double, mono: Bool)`, `lineText(_ index: Int) -> String`, `play(now:)`, `pause(now:)`, `toggle(now:)`, `restart(now:)`, `setWPM(_:now:)`, `stepWPM(by:now:)`, `settle(now:)`, `setPointerInside(_:now:)`. All `now:` parameters default to `.now`.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import Foundation
@testable import Atelier

@MainActor
struct TeleprompterModelTests {
    private let t0 = Date(timeIntervalSinceReferenceDate: 5_000)

    private func makeModel(script: String = "one two three four five six seven eight nine ten") throws -> (TeleprompterModel, ScriptStore) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AtelierModelTests-\(UUID().uuidString)")
        let store = ScriptStore(directory: dir)
        try store.save(script)
        let model = TeleprompterModel(store: store, persistsWPM: false)
        model.updateLayout(width: 400, fontSize: 15, mono: false)
        return (model, store)
    }

    @Test func loadsTheStoredScript() throws {
        let (model, _) = try makeModel()
        #expect(model.script.wordCount == 10)
        #expect(model.lines.count >= 1)
    }

    @Test func playAndPauseToggleState() throws {
        let (model, _) = try makeModel()
        model.play(now: t0)
        #expect(model.isPlaying)
        model.pause(now: t0.addingTimeInterval(1))
        #expect(!model.isPlaying)
    }

    // Review Focus 1: Play on an empty script does nothing.
    @Test func playOnAnEmptyScriptIsANoOp() throws {
        let (model, _) = try makeModel(script: "  \n ")
        model.play(now: t0)
        #expect(!model.isPlaying)
    }

    // Review Focus 4: replacing the script mid-play stops and resets.
    @Test func editingTheScriptWhilePlayingResetsToTheTop() throws {
        let (model, store) = try makeModel()
        model.play(now: t0)
        model.pause(now: t0.addingTimeInterval(3))     // some progress
        model.play(now: t0.addingTimeInterval(3))
        try store.save("brand new script text")
        model.reloadScript()
        #expect(!model.isPlaying)
        #expect(model.script.wordCount == 4)
        #expect(model.scroll.position(at: t0.addingTimeInterval(60)) == 0)
    }

    @Test func settleStopsAScriptThatRanOffTheEnd() throws {
        let (model, _) = try makeModel()
        model.play(now: t0)
        model.settle(now: t0.addingTimeInterval(600))
        #expect(!model.isPlaying)
    }

    @Test func steppingWPMClampsAndKeepsPosition() throws {
        let (model, _) = try makeModel()
        model.play(now: t0)
        let mid = t0.addingTimeInterval(2)
        let before = model.scroll.position(at: mid)
        model.stepWPM(by: 10, now: mid)
        #expect(model.scroll.position(at: mid) == before)
        model.setWPM(9_999, now: mid)
        #expect(model.scroll.wpm == 300)
    }

    @Test func pointerEnteringPausesAndLeavingResumes() throws {
        let (model, _) = try makeModel()
        model.play(now: t0)
        model.setPointerInside(true, now: t0.addingTimeInterval(1))
        #expect(!model.isPlaying)
        #expect(model.pausedForPointer)
        #expect(model.wantsNotchOpen)          // hold-open must survive the hover-out
        model.setPointerInside(false, now: t0.addingTimeInterval(5))
        #expect(model.isPlaying)
        #expect(!model.pausedForPointer)
    }

    @Test func pointerDoesNothingIfItWasNotPlaying() throws {
        let (model, _) = try makeModel()
        model.setPointerInside(true, now: t0)
        model.setPointerInside(false, now: t0.addingTimeInterval(1))
        #expect(!model.isPlaying)
        #expect(!model.wantsNotchOpen)
    }

    @Test func lineTextJoinsTheWordsOfALine() throws {
        let (model, _) = try makeModel(script: "alpha beta\ngamma")
        #expect(model.lineText(0) == "alpha beta")
        #expect(model.lineText(1) == "gamma")
        #expect(model.lineText(99) == "")
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `xcodebuild test -scheme Atelier -destination 'platform=macOS' -only-testing:AtelierTests/TeleprompterModelTests 2>&1 | tail -6`
Expected: FAIL to compile.

- [ ] **Step 3: Implement**

`Atelier/Teleprompter/TeleprompterModel.swift`:
```swift
import AppKit
import Combine
import Foundation

/// State for the Teleprompter tab: the script, its wrapped lines, and the
/// time-anchored scroll. Nothing here ticks: the view asks
/// `scroll.position(at:)` on its own (capped) schedule, and the only timer
/// is one sleeping task that fires when a playing script reaches its end,
/// so a paused or finished teleprompter costs nothing.
@MainActor
final class TeleprompterModel: ObservableObject {
    static let shared = TeleprompterModel()

    @Published private(set) var script = TeleprompterScript(text: "")
    @Published private(set) var lines = TeleprompterLines.empty
    @Published private(set) var scroll: TeleprompterScroll
    @Published private(set) var isPlaying = false
    /// True while playback is paused only because the pointer is over the
    /// notch; it resumes on exit.
    @Published private(set) var pausedForPointer = false

    /// Playing, or about to resume when the pointer leaves. The hold-open
    /// rule and the "retract when done" logic use this, not `isPlaying`,
    /// so the hover-out that triggers the resume doesn't retract the notch.
    var wantsNotchOpen: Bool { isPlaying || pausedForPointer }

    private struct LayoutKey: Equatable {
        var width: CGFloat
        var fontSize: Double
        var mono: Bool
    }

    private let store: ScriptStore
    private var layout: LayoutKey?
    private var finishTask: Task<Void, Never>?
    private var scriptObserver: NSObjectProtocol?

    /// `persistsWPM` is false in tests: they run inside the real app
    /// process, and must not overwrite the user's saved speed.
    private let persistsWPM: Bool

    init(store: ScriptStore = .shared, persistsWPM: Bool = true) {
        self.store = store
        self.persistsWPM = persistsWPM
        scroll = TeleprompterScroll(totalWords: 0, wpm: AtelierSettings.teleprompterWPM)
        scriptObserver = NotificationCenter.default.addObserver(
            forName: ScriptStore.didChange, object: store, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reloadScript() }
        }
        reloadScript()
    }

    // MARK: Script and layout

    /// Re-reads the script and starts over, paused, at the top: a script
    /// edited mid-play must never leave the position past the new end.
    func reloadScript() {
        cancelFinishTask()
        script = TeleprompterScript(text: store.load())
        scroll = TeleprompterScroll(totalWords: script.wordCount, wpm: scroll.wpm)
        isPlaying = false
        pausedForPointer = false
        relayout()
    }

    func updateLayout(width: CGFloat, fontSize: Double, mono: Bool) {
        let key = LayoutKey(width: width, fontSize: fontSize, mono: mono)
        guard key != layout else { return }
        layout = key
        relayout()
    }

    private func relayout() {
        guard let layout else {
            lines = TeleprompterLines(starts: [], totalWords: script.wordCount)
            return
        }
        let font = TeleprompterFont.nsFont(size: layout.fontSize, mono: layout.mono)
        lines = TeleprompterLineWrapper.lines(for: script, font: font, width: layout.width)
    }

    func lineText(_ index: Int) -> String {
        guard lines.starts.indices.contains(index) else { return "" }
        let start = lines.starts[index]
        let end = index + 1 < lines.starts.count ? lines.starts[index + 1] : script.wordCount
        return script.words[start..<end].joined(separator: " ")
    }

    // MARK: Transport

    func play(now: Date = .now) {
        scroll.play(at: now)
        isPlaying = scroll.isPlaying(at: now)
        pausedForPointer = false
        scheduleFinish(now: now)
    }

    func pause(now: Date = .now) {
        scroll.pause(at: now)
        isPlaying = false
        pausedForPointer = false
        cancelFinishTask()
    }

    func toggle(now: Date = .now) {
        if isPlaying { pause(now: now) } else { play(now: now) }
    }

    func restart(now: Date = .now) {
        scroll.seek(to: 0, at: now)
        scheduleFinish(now: now)
    }

    func setWPM(_ wpm: Double, now: Date = .now) {
        scroll.setWPM(wpm, at: now)
        if persistsWPM { AtelierSettings.teleprompterWPM = scroll.wpm }
        scheduleFinish(now: now)
    }

    func stepWPM(by delta: Double, now: Date = .now) {
        setWPM(scroll.wpm + delta, now: now)
    }

    /// Called when a playing script has run off the end.
    func settle(now: Date = .now) {
        scroll.settle(at: now)
        isPlaying = scroll.isPlaying(at: now)
        scheduleFinish(now: now)   // reschedules only if somehow still playing
    }

    /// Pause while the pointer is over the notch, resume when it leaves,
    /// but only if it was playing when the pointer arrived. Pressing Play
    /// with the pointer already inside plays normally.
    func setPointerInside(_ inside: Bool, now: Date = .now) {
        if inside {
            guard isPlaying else { return }
            pause(now: now)
            pausedForPointer = true
        } else if pausedForPointer {
            play(now: now)
        }
    }

    // MARK: Finish timer

    private func scheduleFinish(now: Date) {
        cancelFinishTask()
        guard scroll.isPlaying(at: now) else { return }
        // A hair past the end so `settle` sees it as finished.
        let wait = scroll.secondsRemaining(at: now) + 0.05
        finishTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled else { return }
            self?.settle()
        }
    }

    private func cancelFinishTask() {
        finishTask?.cancel()
        finishTask = nil
    }
}
```

- [ ] **Step 4: Run to verify pass**

Run the Step 2 command. Expected: PASS.

- [ ] **Step 5: Full build + suite, commit**

```bash
git add Atelier/Teleprompter/TeleprompterModel.swift AtelierTests/TeleprompterModelTests.swift
git commit -m "feat(teleprompter): observable model with pointer-pause and finish timer (stage 2)

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 6: The tab (page, ring, control strip) and notch wiring

Manual-verification only (real notch, real pixels). Apply the project's UI review skills at the end.

**Files:**
- Create: `Atelier/UI/TeleprompterRing.swift`, `Atelier/UI/TeleprompterControlStrip.swift`, `Atelier/UI/TeleprompterPageView.swift`
- Modify: `Atelier/UI/NotchLayout.swift`, `Atelier/Notch/NotchViewModel.swift:47-56`, `Atelier/Notch/NotchController.swift:125,214-260`, `Atelier/UI/NotchRootView.swift` (lines 15, ~120-135, ~242, ~369, ~385-425)

**Interfaces:**
- Consumes: `TeleprompterModel`, `TeleprompterFont`, `TimeFormatting.mmss(_:)`, `NotchLayout.pageHorizontalInset`, `TeleprompterHoldOpen`.
- Produces: `NotchLayout.teleprompterHeight: CGFloat` (150), `NotchViewModel.teleprompterSize: CGSize`, views `TeleprompterRing(fraction:label:help:)`, `TeleprompterControlStrip(model:notchWidth:height:)`, `TeleprompterPageView(model:)`, and the helper `TeleprompterTicker`.

- [ ] **Step 1: Layout constant and view-model size**

`Atelier/UI/NotchLayout.swift` — add inside `enum NotchLayout`:
```swift
    /// Whole-panel height of the Teleprompter tab, notch band included
    /// (NotchPrompter's 150pt). Fits inside the player's footprint, so no
    /// other page's geometry changes.
    static let teleprompterHeight: CGFloat = 150
```

`Atelier/Notch/NotchViewModel.swift` — add a stored property next to `calendarSize` and a defaulted init parameter (so existing call sites and tests still compile):
```swift
    let teleprompterSize: CGSize
```
Change the init signature's end to `calendarSize: CGSize, teleprompterSize: CGSize = .zero)` and add `self.teleprompterSize = teleprompterSize` in its body.

`Atelier/Notch/NotchController.swift` — after `calendarSize` (line ~238):
```swift
        let teleprompterSize = CGSize(
            width: Self.expandedWidth,
            height: NotchLayout.teleprompterHeight
        )
```
pass `teleprompterSize: teleprompterSize` as the last argument of the `NotchViewModel(...)` call at line ~242, and change the footprint line (~254) to:
```swift
        let maxHeight = max(expandedSize.height, calendarSize.height, teleprompterSize.height)
```

- [ ] **Step 2: The ring and the ticker**

`Atelier/UI/TeleprompterRing.swift`:
```swift
import SwiftUI

/// A small Activity-style progress ring with the time centered inside.
/// Same track/progress construction as `RingGauge` in
/// `SystemMonitorPageView` (12 o'clock start, round cap, 15% track), but a
/// separate view: that one is private, 64pt, and carries an icon + label.
/// ~28pt is tight for text, so the label scales down; confirm on-device.
struct TeleprompterRing: View {
    let fraction: Double
    /// Centered text, e.g. "2:41" (time remaining).
    let label: String
    /// Tooltip / VoiceOver value, e.g. "0:32 of 3:10".
    let detail: String

    static let diameter: CGFloat = 28
    private static let lineWidth: CGFloat = 2.5

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.15), lineWidth: Self.lineWidth)
            Circle()
                .trim(from: 0, to: CGFloat(min(max(fraction, 0), 1)))
                .stroke(Color.white, style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(label)
                .font(.system(size: 8, weight: .semibold).monospacedDigit())
                .minimumScaleFactor(0.7)
                .lineLimit(1)
                .foregroundStyle(.white)
                .padding(Self.lineWidth + 1)
        }
        .frame(width: Self.diameter, height: Self.diameter)
        .help(detail)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Time remaining \(label)")
        .accessibilityValue(detail)
    }
}

/// Re-renders its content on a fixed schedule only while `active`. When
/// idle it renders once and costs nothing (the same "skip the ticking path
/// entirely" rule `MarqueeText` follows).
struct TeleprompterTicker<Content: View>: View {
    let interval: TimeInterval
    let active: Bool
    @ViewBuilder let content: (Date) -> Content

    var body: some View {
        if active {
            TimelineView(.periodic(from: .now, by: interval)) { context in
                content(context.date)
            }
        } else {
            content(.now)
        }
    }
}
```

- [ ] **Step 3: The control strip (lives in the notch band, flanking the camera)**

`Atelier/UI/TeleprompterControlStrip.swift`:
```swift
import SwiftUI

/// Play/pause + speed on the left of the camera cutout, ghost icon + the
/// time ring on the right, all inside the notch band (CueNotch's layout).
/// `notchWidth`/`height` are the real notch, so the flanks line up with it.
struct TeleprompterControlStrip: View {
    @ObservedObject var model: TeleprompterModel
    let notchWidth: CGFloat
    let height: CGFloat
    @AppStorage(AtelierSettings.ghostModeKey) private var ghostMode = false

    private static let speedPresets: [Int] = [60, 80, 100, 120, 140, 160, 180, 200, 240, 280]

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                playPauseButton
                speedMenu
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // The camera cutout: nothing to draw, nothing to click.
            Color.clear
                .frame(width: notchWidth)
                .allowsHitTesting(false)

            HStack(spacing: 8) {
                if ghostMode {
                    Image(systemName: "eye.slash")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                        .help("Ghost Mode is on: hidden from screen sharing")
                        .accessibilityLabel("Ghost Mode on")
                }
                ring
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .frame(height: height)
    }

    private var playPauseButton: some View {
        Button {
            model.toggle()
        } label: {
            Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(model.script.isEmpty)
        .opacity(model.script.isEmpty ? 0.35 : 1)
        .help(model.isPlaying ? "Pause" : "Play")
        .accessibilityLabel(model.isPlaying ? "Pause script" : "Play script")
    }

    private var speedMenu: some View {
        Menu {
            ForEach(Self.speedPresets, id: \.self) { wpm in
                Button("\(wpm) WPM") { model.setWPM(Double(wpm)) }
            }
        } label: {
            Text("\(Int(model.scroll.wpm))")
                .font(.system(size: 9, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.white.opacity(0.14)))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Reading speed, words per minute")
        .accessibilityLabel("Reading speed")
        .accessibilityValue("\(Int(model.scroll.wpm)) words per minute")
    }

    private var ring: some View {
        TeleprompterTicker(interval: 1, active: model.isPlaying) { now in
            let remaining = model.scroll.secondsRemaining(at: now)
            let elapsed = model.scroll.secondsElapsed(at: now)
            TeleprompterRing(
                fraction: model.scroll.progress(at: now),
                label: TimeFormatting.mmss(remaining),
                detail: "\(TimeFormatting.mmss(elapsed)) of \(TimeFormatting.mmss(model.scroll.secondsTotal))"
            )
        }
    }
}
```

- [ ] **Step 4: The reading view**

`Atelier/UI/TeleprompterPageView.swift`:
```swift
import SwiftUI

/// The Teleprompter tab's text area: a few display lines gliding upward at
/// the script's WPM, the current line brightest (Focus Guide), lines
/// already read dimmed, top/bottom edges faded. Only the visible window of
/// lines is built. Redraws at 30 fps while playing, 4 fps under Reduce
/// Motion (where the scroll steps line by line instead of gliding), and
/// not at all when paused.
struct TeleprompterPageView: View {
    @ObservedObject var model: TeleprompterModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(AtelierSettings.teleprompterFontSizeKey) private var fontSize = 15.0
    @AppStorage(AtelierSettings.teleprompterMonoFontKey) private var mono = false

    /// Lines shown above the current one (already read, dimmed).
    private static let readLinesAbove = 1.0
    private static let lineHeightFactor = 1.35

    var body: some View {
        GeometryReader { geo in
            Group {
                if model.script.isEmpty {
                    emptyState
                } else {
                    reader(height: geo.size.height)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .onAppear { model.updateLayout(width: geo.size.width, fontSize: fontSize, mono: mono) }
            .onChange(of: geo.size.width) { _, width in model.updateLayout(width: width, fontSize: fontSize, mono: mono) }
            .onChange(of: fontSize) { _, size in model.updateLayout(width: geo.size.width, fontSize: size, mono: mono) }
            .onChange(of: mono) { _, isMono in model.updateLayout(width: geo.size.width, fontSize: fontSize, mono: isMono) }
        }
        .padding(.horizontal, NotchLayout.pageHorizontalInset)
        .padding(.bottom, 8)
    }

    private func reader(height: CGFloat) -> some View {
        let lineHeight = fontSize * Self.lineHeightFactor
        let tick: TimeInterval = reduceMotion ? 0.25 : 1.0 / 30
        return TeleprompterTicker(interval: tick, active: model.isPlaying) { now in
            let wordPosition = model.scroll.position(at: now)
            let linePosition = model.lines.linePosition(forWord: wordPosition)
            // Reduce Motion: step whole lines instead of gliding.
            let shown = reduceMotion ? linePosition.rounded(.down) : linePosition
            let current = model.lines.currentLine(forWord: wordPosition)
            let visible = model.lines.visibleLines(
                around: shown, behind: 2, ahead: Int(height / lineHeight) + 2
            )
            ZStack(alignment: .topLeading) {
                ForEach(visible, id: \.self) { index in
                    Text(model.lineText(index))
                        .font(TeleprompterFont.swiftUIFont(size: fontSize, mono: mono))
                        .foregroundStyle(.white.opacity(Self.opacity(line: index, current: current)))
                        .lineLimit(1)
                        .fixedSize()
                        .offset(y: (Double(index) - shown + Self.readLinesAbove) * lineHeight)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .clipped()
            .mask(edgeFade)
        }
        // One element for VoiceOver: the current line, not every Text.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Teleprompter script")
        .accessibilityValue(model.lineText(model.lines.currentLine(forWord: model.scroll.position(at: .now))))
        .allowsHitTesting(false)
    }

    /// Focus Guide: current line full, read lines dim, upcoming lines mid.
    private static func opacity(line: Int, current: Int) -> Double {
        if line < current { return 0.35 }
        if line == current { return 1 }
        return 0.7
    }

    private var edgeFade: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.2),
                .init(color: .black, location: 0.8),
                .init(color: .clear, location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// The shared empty-state style: soft card, one SF Symbol, one short line.
    private var emptyState: some View {
        Button {
            SettingsWindowController.shared.show()
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                VStack(spacing: 6) {
                    Image(systemName: "text.alignleft")
                        .font(.system(size: 20, weight: .regular))
                    Text("Add a script in Settings")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(.white.opacity(0.5))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("No script. Open Settings to add one")
        .help("Open Settings")
    }
}
```

- [ ] **Step 5: Wire into `NotchRootView`**

Make these edits (line numbers are approximate; search for the anchor text):

1. Next to `@StateObject private var camera = CameraMirrorSource()` (line 15):
```swift
    @ObservedObject private var teleprompter = TeleprompterModel.shared
```
2. In `frameSize`, `.expanded` case, right before the final `return viewModel.currentSize`:
```swift
            if AtelierSettings.teleprompterEnabled, viewModel.currentPage == .teleprompter {
                return viewModel.teleprompterSize
            }
```
3. In the page `if/else if` chain, right after the camera branch's closing brace (before the final `else { ExpandedPlayerView(...) }`):
```swift
                        } else if AtelierSettings.teleprompterEnabled, viewModel.currentPage == .teleprompter {
                            TeleprompterPageView(model: teleprompter)
```
4. Attach the strip to the expanded `VStack` (the one that begins `VStack(spacing: 0) {` under `if viewModel.state == .expanded {`), as a modifier after the VStack's closing brace:
```swift
                    .overlay(alignment: .top) {
                        if AtelierSettings.teleprompterEnabled, viewModel.currentPage == .teleprompter {
                            TeleprompterControlStrip(
                                model: teleprompter,
                                notchWidth: viewModel.collapsedSize.width,
                                height: viewModel.collapsedSize.height
                            )
                        }
                    }
```
If the VStack doesn't fill the panel width so the strip is mispositioned, wrap the overlay in `.frame(width: viewModel.teleprompterSize.width)` and re-check on-device.
5. Pointer pause: in the hover handler, where `pointerInside = hovering` is set (line ~369), add directly after it:
```swift
                if AtelierSettings.teleprompterPauseOnHover {
                    teleprompter.setPointerInside(hovering)
                }
```
6. Hold-open: in the hover-out `else` branch, directly after the `CameraHoldOpen` `if ... { return }` block:
```swift
                    if TeleprompterHoldOpen.shouldSuppressRetract(
                        isPlaying: teleprompter.wantsNotchOpen,
                        currentPage: viewModel.currentPage,
                        state: viewModel.state
                    ) { return }
```
7. Pause on close/tab change (deliberately NOT on app-resign-active: you read while Zoom is frontmost). Add inside the existing handlers:
```swift
            .onChange(of: viewModel.state) { _, newState in
                if newState != .expanded { camera.stop(); teleprompter.pause() }
            }
            .onChange(of: viewModel.currentPage) { _, page in
                if page != .camera { camera.stop() }
                if page != .teleprompter { teleprompter.pause() }
            }
```
(merge into the existing `onChange` closures rather than duplicating them).
8. Retract when playback ends while the pointer is already outside (mirrors the camera's `.onChange(of: camera.isLive)`), placed right after that block:
```swift
            .onChange(of: teleprompter.wantsNotchOpen) { _, wants in
                guard !wants, !pointerInside, viewModel.state == .expanded, viewModel.currentPage == .teleprompter else { return }
                withAnimation(NotchAnimations.close) {
                    viewModel.handle(.hoverEnded(isPlaying: liveActivity.hasContent))
                }
            }
```

- [ ] **Step 6: Build and run the suite**

Run: `xcodebuild -scheme Atelier -configuration Debug build 2>&1 | grep -E "error:|BUILD" ; xcodebuild test -scheme Atelier -destination 'platform=macOS' 2>&1 | grep -E "Test run|TEST (SUCCEEDED|FAILED)"`
Expected: `BUILD SUCCEEDED`, tests green. Fix compile errors in the edited files only.

- [ ] **Step 7: On-device check (manual; say so plainly, no automated coverage)**

Ask Alicia to put a short multi-line script into `~/Library/Application Support/Atelier/Teleprompter/script.txt` (the Settings pane that edits it arrives in Task 7). Then `/build`, hover the notch, open the Teleprompter tab, and screenshot **every tab plus the teleprompter tab in these states**: empty, paused, playing, finished, Reduce Motion on. Check: strip sits in the flanks and doesn't overlap the camera cutout; ring text legible; 3-4 lines fit; edge fades look right; hold-open keeps it up while playing; hover-out/in behavior; tab dots still reachable.

- [ ] **Step 8: Run `ui-review-tahoe`** on the new views (project rule: proactively after any UI work) and apply findings that are clear wins; list the rest for Alicia.

- [ ] **Step 9: Commit**

```bash
git add -A Atelier
git commit -m "feat(teleprompter): Teleprompter tab, control strip, progress ring (stage 2)

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 7: Settings pane (editor, file drop, options)

Manual-verification only.

**Files:**
- Create: `Atelier/Settings/Panes/TeleprompterPane.swift`
- Modify: `Atelier/Settings/SettingsView.swift:3-50`

**Interfaces:**
- Consumes: `ScriptStore.shared`, `ScriptImporter`, `TeleprompterModel.shared.setWPM`, `AtelierSettings` keys.
- Produces: `SettingsPane.teleprompter`, `TeleprompterPane`.

- [ ] **Step 1: Add the pane**

`Atelier/Settings/Panes/TeleprompterPane.swift`:
```swift
import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Script editor + file drop + reading options. Edits save automatically
/// (debounced) to `ScriptStore`; the model reloads on the store's change
/// notification and restarts from the top.
struct TeleprompterPane: View {
    @AppStorage(AtelierSettings.teleprompterEnabledKey) private var enabled = true
    @AppStorage(AtelierSettings.teleprompterWPMKey) private var wpm = TeleprompterScroll.defaultWPM
    @AppStorage(AtelierSettings.teleprompterMonoFontKey) private var mono = false
    @AppStorage(AtelierSettings.teleprompterFontSizeKey) private var fontSize = 15.0
    @AppStorage(AtelierSettings.teleprompterPauseOnHoverKey) private var pauseOnHover = true
    @AppStorage(AtelierSettings.ghostModeKey) private var ghostMode = false
    @AppStorage(AtelierSettings.teleprompterHotkeysKey) private var hotkeys = false

    @State private var text = ""
    @State private var loaded = false
    @State private var saveTask: Task<Void, Never>?
    @State private var message: String?
    @State private var pendingImport: URL?
    @State private var dropTargeted = false

    var body: some View {
        Form {
            Section("Script") {
                TextEditor(text: $text)
                    .font(.body)
                    .frame(minHeight: 170)
                    .accessibilityLabel("Script")
                HStack {
                    Button("Choose File") { chooseFile() }
                    Text("or drop a .txt, .md, .doc, .docx or .rtf file anywhere here")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                if let message {
                    Text(message).font(.callout).foregroundStyle(.secondary)
                }
            }
            .disabled(!enabled)

            Section("Reading") {
                LabeledContent("Speed") {
                    Stepper(value: $wpm, in: TeleprompterScroll.wpmRange, step: 10) {
                        Text("\(Int(wpm)) WPM")
                    }
                }
                Picker("Font", selection: $mono) {
                    Text("Sans").tag(false)
                    Text("Mono").tag(true)
                }
                LabeledContent("Text size") {
                    Stepper(value: $fontSize, in: 12...22, step: 1) {
                        Text("\(Int(fontSize)) pt")
                    }
                }
                Toggle("Pause while the pointer is over the notch", isOn: $pauseOnHover)
            }
            .disabled(!enabled)

            Section("Privacy and shortcuts") {
                Toggle("Ghost Mode", isOn: $ghostMode)
                Text("Hides the whole notch from screen sharing and recordings. It is still visible to you.")
                    .font(.callout).foregroundStyle(.secondary)
                Toggle("Global shortcuts", isOn: $hotkeys)
                Text("⌃⌥P play or pause, ⌃⌥↑ faster, ⌃⌥↓ slower. Work while another app is in front.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            guard !loaded else { return }
            text = ScriptStore.shared.load()
            loaded = true
        }
        .onChange(of: text) { scheduleSave() }
        .onChange(of: wpm) { _, value in TeleprompterModel.shared.setWPM(value) }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            requestImport(url)
            return true
        } isTargeted: { dropTargeted = $0 }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 10).strokeBorder(Color.accentColor, lineWidth: 2).padding(4)
                    .allowsHitTesting(false)
            }
        }
        .confirmationDialog("Replace the current script?", isPresented: .init(
            get: { pendingImport != nil },
            set: { if !$0 { pendingImport = nil } }
        ), presenting: pendingImport) { url in
            Button("Replace") { importFile(url) }
            Button("Cancel", role: .cancel) {}
        } message: { url in
            Text("\(url.lastPathComponent) will replace what's in the editor.")
        }
    }

    /// Debounced so typing doesn't rewrite the file and reset playback on
    /// every keystroke.
    private func scheduleSave() {
        guard loaded else { return }
        saveTask?.cancel()
        let current = text
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            do { try ScriptStore.shared.save(current) }
            catch { message = "Couldn't save the script" }
        }
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = ScriptImporter.supportedExtensions
            .compactMap { UTType(filenameExtension: $0) }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        requestImport(url)
    }

    /// Never overwrites typed text without asking (Alicia's global rule).
    private func requestImport(_ url: URL) {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            importFile(url)
        } else {
            pendingImport = url
        }
    }

    private func importFile(_ url: URL) {
        do {
            text = try ScriptImporter.importText(from: url)
            message = "Imported \(url.lastPathComponent)"
        } catch let error as ScriptImporter.ImportError {
            message = error.message          // current script left untouched
        } catch {
            message = "Couldn't read that file"
        }
    }
}
```

- [ ] **Step 2: Add the sidebar entry**

`Atelier/Settings/SettingsView.swift` — add `case teleprompter = "Teleprompter"` between `widgets` and `permissions` in `SettingsPane`; add its symbol `case .teleprompter: "text.alignleft"`; add `case .teleprompter: TeleprompterPane()` to the pane `switch`.

- [ ] **Step 3: Build and suite**

Run the Task 6 Step 6 command. Expected: green.

- [ ] **Step 4: On-device check (manual)**

`/build`, open Settings > Teleprompter. Verify: typing saves (reopen Settings, the text is still there); the notch tab shows the new script from the top; Choose File and drop each import a `.txt`, `.md` and a real `.docx` (Review Focus 5: also drop a `.pdf` and an empty `.txt`: a message appears, the script is unchanged); dropping onto a non-empty editor asks to replace; speed stepper changes the chip in the notch; font Sans/Mono and size take effect. Screenshot the pane.

- [ ] **Step 5: Commit**

```bash
git add -A Atelier
git commit -m "feat(teleprompter): Settings pane with editor, file drop and options (stage 2)

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 8: Ghost Mode

Manual-verification only. **Risk gate:** Apple changed capture behavior in macOS 15; `sharingType = .none` may no longer hide a window from ScreenCaptureKit-based capture. The roadmap says to verify, not assume. If verification fails, STOP after Step 3 and report to Alicia; do not invent a workaround.

**Files:**
- Modify: `Atelier/Notch/NotchController.swift`, `Atelier/AtelierApp.swift:20-64`

**Interfaces:**
- Consumes: `AtelierSettings.ghostModeEnabled`, `AtelierSettings.ghostModeKey`.
- Produces: `NotchController.applyLiveSettings()` (Task 9 extends it).

- [ ] **Step 1: Apply Ghost Mode live**

`Atelier/Notch/NotchController.swift` — add a property near `private let panel = NotchPanel()`:
```swift
    private var settingsObserver: NSObjectProtocol?
```
Add this method to the class:
```swift
    /// Settings that take effect on the panel itself, applied at launch and
    /// again whenever any default changes (cheap and idempotent).
    /// `.none` hides the panel from screen sharing and recording; `.readOnly`
    /// is `NSWindow`'s normal default.
    private func applyLiveSettings() {
        panel.sharingType = AtelierSettings.ghostModeEnabled ? .none : .readOnly
    }
```
In `init`, directly after `panel.orderFrontRegardless()`:
```swift
        applyLiveSettings()
        settingsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.applyLiveSettings() }
        }
```

- [ ] **Step 2: Menu-bar toggle**

`Atelier/AtelierApp.swift` — add near the other `@AppStorage`:
```swift
    @AppStorage(AtelierSettings.ghostModeKey) private var ghostMode = false
```
and in the menu, above the `Button("Settings")` (after the color-picker block's `Divider`):
```swift
            Toggle("Ghost Mode", isOn: $ghostMode)

            Divider()
```

- [ ] **Step 3: Verify it really hides the notch (do not skip)**

1. `/build`. Turn Ghost Mode on from the menu bar.
2. Ask Alicia to run, in this session, `! screencapture -x ~/Downloads/dev-macos/atelier/.superpowers/ghost-test.png` (needs Screen Recording permission for the terminal), then open the image: is the notch/teleprompter present or absent? Repeat with Ghost Mode off (it must be present).
3. Then a real recording: QuickTime screen recording of the notch with Ghost Mode on, then off. Then, if she uses one, a Zoom/Meet screen share viewed from a second device or the recording.
4. Record the result (which capture paths hide it, which don't, macOS build) in the ADR in Task 10.
   - If any common path still shows the notch: **stop, report to Alicia with the evidence**, and let her decide (options include shipping with an honest caveat in Settings, or researching what CueNotch does). Do not mark Ghost Mode done.

- [ ] **Step 4: Full build + suite, commit** (only if Step 3 passed, or Alicia chose to ship with a caveat)

```bash
git add -A Atelier
git commit -m "feat(teleprompter): Ghost Mode via sharingType, menu-bar toggle (stage 3)

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 9: Global hotkeys

Manual-verification only. Carbon's `RegisterEventHotKey` needs no permission (unlike our Accessibility-gated event tap).

**Files:**
- Create: `Atelier/Teleprompter/GlobalHotkeys.swift`
- Modify: `Atelier/Notch/NotchController.swift` (`applyLiveSettings`)

**Interfaces:**
- Produces: `GlobalHotkeys.shared`, `GlobalHotkeys.Action { playPause, faster, slower }`, `register(handler:)`, `unregister()`.

- [ ] **Step 1: The hotkey wrapper**

`Atelier/Teleprompter/GlobalHotkeys.swift`:
```swift
import Carbon.HIToolbox

/// Global shortcuts via Carbon's `RegisterEventHotKey`: works while another
/// app is frontmost, needs no permission, and adds no dependency (the
/// reference app used the third-party `HotKey` package). Registered only
/// while the setting and the tab are both on. A key another app already
/// owns simply fails to register and is skipped.
///
/// Keys: ⌃⌥P play/pause, ⌃⌥↑ faster, ⌃⌥↓ slower. Deliberately not
/// ⌃⌥Space (macOS's input-source shortcut) or bare ⌘↑/⌘↓ (they'd break
/// text editing everywhere).
@MainActor
final class GlobalHotkeys {
    enum Action: UInt32 {
        case playPause = 1
        case faster = 2
        case slower = 3
    }

    static let shared = GlobalHotkeys()

    private var handler: ((Action) -> Void)?
    private var hotKeyRefs: [EventHotKeyRef] = []
    private var eventHandlerRef: EventHandlerRef?
    private var isRegistered = false

    private static let signature: OSType = 0x41544C52   // 'ATLR'

    func register(handler: @escaping (Action) -> Void) {
        self.handler = handler
        guard !isRegistered else { return }
        isRegistered = true

        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID
            )
            guard status == noErr else { return status }
            let id = hotKeyID.id
            DispatchQueue.main.async {
                MainActor.assumeIsolated { GlobalHotkeys.shared.fire(id) }
            }
            return noErr
        }, 1, &spec, nil, &eventHandlerRef)

        let modifiers = UInt32(controlKey | optionKey)
        let keys: [(Action, Int)] = [
            (.playPause, kVK_ANSI_P),
            (.faster, kVK_UpArrow),
            (.slower, kVK_DownArrow)
        ]
        for (action, keyCode) in keys {
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: Self.signature, id: action.rawValue)
            if RegisterEventHotKey(UInt32(keyCode), modifiers, id, GetApplicationEventTarget(), 0, &ref) == noErr,
               let ref {
                hotKeyRefs.append(ref)
            }
        }
    }

    func unregister() {
        guard isRegistered else { return }
        hotKeyRefs.forEach { UnregisterEventHotKey($0) }
        hotKeyRefs.removeAll()
        if let eventHandlerRef { RemoveEventHandler(eventHandlerRef) }
        eventHandlerRef = nil
        handler = nil
        isRegistered = false
    }

    private func fire(_ id: UInt32) {
        guard let action = Action(rawValue: id) else { return }
        handler?(action)
    }
}
```
If Swift 6 rejects the C callback's reference to `GlobalHotkeys.shared`, keep the `DispatchQueue.main.async { MainActor.assumeIsolated { ... } }` shape (only that closure touches the singleton) and adjust minimally; do not add `@unchecked Sendable` wrappers.

- [ ] **Step 2: Register from `applyLiveSettings`**

`NotchController.swift` — extend `applyLiveSettings()` (add `import SwiftUI` at the top of the file if `withAnimation` isn't already available):
```swift
    private func applyLiveSettings() {
        panel.sharingType = AtelierSettings.ghostModeEnabled ? .none : .readOnly

        if AtelierSettings.teleprompterEnabled, AtelierSettings.teleprompterHotkeysEnabled {
            GlobalHotkeys.shared.register { [weak self] action in self?.handleHotkey(action) }
        } else {
            GlobalHotkeys.shared.unregister()
        }
    }

    private func handleHotkey(_ action: GlobalHotkeys.Action) {
        let model = TeleprompterModel.shared
        switch action {
        case .playPause:
            // Open the notch on the Teleprompter tab first, so pressing the
            // key with the notch collapsed is visible. Opening resets the
            // page to the first tab, so select ours *after* it opens.
            if viewModel.state != .expanded {
                withAnimation(NotchAnimations.open) { viewModel.handle(.hoverStarted) }
            }
            viewModel.selectPage(.teleprompter)
            model.toggle()
        case .faster:
            model.stepWPM(by: 10)
        case .slower:
            model.stepWPM(by: -10)
        }
    }
```

- [ ] **Step 3: Build and suite**

Run the Task 6 Step 6 command. Expected: green.

- [ ] **Step 4: On-device check (manual)**

`/build`. Settings > Teleprompter > turn on Global shortcuts. With another app frontmost: ⌃⌥P opens the notch on the Teleprompter tab and plays; again pauses; ⌃⌥↑/↓ change the speed chip by 10; turning the setting off makes all three do nothing (and the keys work normally in other apps again).

- [ ] **Step 5: Commit**

```bash
git add -A Atelier
git commit -m "feat(teleprompter): opt-in global hotkeys via Carbon (stage 3)

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 10: Docs and stage bookkeeping

**Files:**
- Modify: `STAGES.md`, `README.md`, `CLAUDE.md` (Architecture table + "What's shipped" wording if present), `docs/ROADMAP.md` (Phase 17), `docs/superpowers/specs/2026-09-25-teleprompter-design.md`
- Create: `docs/decisions/0019-teleprompter-tab-and-ghost-mode.md`

- [ ] **Step 1: ADR 0019** (use the `recording-architecture-decisions` skill; match the tone/headings of `docs/decisions/0018-*.md`). Record: (1) tab in the notch panel rather than a separate window (and CueNotch/NotchPrompter/Avocado comparison); (2) time-anchored `TeleprompterScroll` rather than a tick loop, and no `PaceSource` protocol yet; (3) CoreText wrapping with one `Text` per line; (4) hold-open always on while playing, and the pointer-pause semantics; (5) Ghost Mode's `sharingType` scope (whole panel) and the **verification result from Task 8 Step 3**, exact macOS build; (6) Carbon hotkeys instead of the `HotKey` package, and why ⌃⌥P/↑/↓.

- [ ] **Step 2: Correct the spec.** In the spec's UI section replace "about 118pt is text" wording with: the tab-dot row sits under the notch band, so the text area is ~80-88pt (3-4 lines). Replace the `PaceSource` bullet with: pace sources are `TeleprompterScroll.play`/`position(at:)` (clock) and `seek(to:at:)` (speech, stage 4); a protocol is added only if stage 4 needs it. Note the Task 8 outcome.

- [ ] **Step 3: Update `STAGES.md`** with a Phase 17 section in the file's existing checklist format: stage 1 (pure logic + import + store), stage 2 (tab, ring, strip, Settings pane), stage 3 (Ghost Mode, hotkeys) marked done only if built, tested and device-verified; stage 4 (voice sync) "not started, own plan".

- [ ] **Step 4: Update `README.md`** (what the teleprompter is, how to add a script, Ghost Mode, hotkeys and their keys) and the `CLAUDE.md` architecture table (new `Teleprompter/*` row: manual-verification only except the pure `Notch/Teleprompter*` files; extend the Pure logic row) and the reference list if CueNotch/Avocado notes changed. Update the test count.

- [ ] **Step 5: Update `docs/ROADMAP.md` Phase 17:** tick scrolling script tab and Ghost Mode (per the verified result), leave script library, voice sync, coach, captions unticked; add the "Listening pill needs ~20pt below the panel" note to the voice-sync item.

- [ ] **Step 6: Run the `phase-completion-checklist` skill**, then the final full test run: `xcodebuild test -scheme Atelier -destination 'platform=macOS' 2>&1 | grep -E "Test run|TEST (SUCCEEDED|FAILED)"`. Expected: green.

- [ ] **Step 7: Commit**

```bash
git add -A STAGES.md README.md CLAUDE.md docs
git commit -m "docs: teleprompter stages 1-3, ADR 0019, roadmap sync

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

Do **not** push. Run `pre-push-docs-sync` and ask Alicia before any push.

---

## Self-review notes

- **Spec coverage:** scrolling tab, WPM speed, play/pause, control strip in notch band, time + ring, Focus Guide, edge fades, pause-on-hover, mono option, script editor + file drop (`.txt/.md/.doc/.docx/.rtf`), Ghost Mode (+ icon, menu-bar toggle), global hotkeys (Carbon), settings, docs: Tasks 1-10. Voice sync, `ScriptMatcher`, Listening pill, mic/speech permissions: deferred to the stage-4 plan by design.
- **Type consistency:** `wantsNotchOpen` (model) is what the root view passes to `TeleprompterHoldOpen` as `isPlaying`; `secondsTotal` is a property, `secondsRemaining(at:)`/`secondsElapsed(at:)` are methods; `setPointerInside(_:now:)` and `stepWPM(by:now:)` match their tests.
