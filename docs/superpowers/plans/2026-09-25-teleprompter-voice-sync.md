# Teleprompter Voice Sync (stage 4) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (Alicia chose native/inline execution for this feature; one fresh reviewer at the end) or superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The teleprompter follows the speaker's voice using on-device speech recognition, gliding toward the spoken position, waiting when the speaker stops.

**Architecture:** A pure `ScriptMatcher` aligns recognised words to the script (forward-only, windowed). `TeleprompterScroll` gains a pure "voice mode" (a glide target instead of a clock). `TeleprompterModel` owns voice-mode semantics and talks to a `SpeechWordSource` protocol (real impl `SpeechRecognizer`, fake in tests). Mic/recognizer run only while listening.

**Tech Stack:** Swift 6, SwiftUI + AppKit, `Speech` (`SFSpeechRecognizer`), `AVFoundation` (`AVAudioEngine`), Swift Testing. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-09-25-teleprompter-voice-sync-design.md` (read it first). Also `docs/decisions/0019-teleprompter-tab-and-ghost-mode.md`.

## Global Constraints

- Swift 6, strict concurrency, deployment target macOS 26.0. SwiftUI first, AppKit where needed.
- No third-party dependencies. No new packages.
- `ScriptMatcher` and `TeleprompterScroll` import **Foundation only** (Invariant 1 style: no AppKit).
- Test framework is Swift Testing (`import Testing`), not XCTest. Tests run inside the real app process and share the user's `UserDefaults`: pass explicit values (`TeleprompterModel(..., persistsWPM: false, persistsVoiceSync: false, initialWPM: 140)`); never depend on saved settings.
- Don't add tests beyond those listed here (Alicia's rule: no extra tests unless asked). Existing tests broken by an intentional change (Task 4) are updated, not deleted.
- Never hardcode secrets; none are involved.
- Info.plist gets `NSMicrophoneUsageDescription` + `NSSpeechRecognitionUsageDescription`; leave `NSAudioCaptureUsageDescription` alone. No entitlements file / sandbox exists; don't add one.
- C/audio-thread callbacks must not run MainActor-isolated closures (Swift 6 default MainActor isolation would trap): build tap/recognition callbacks in `nonisolated` helpers and hop to main with `DispatchQueue.main.async { MainActor.assumeIsolated { ... } }`.
- Battery discipline: mic + recognizer only while voice sync is on AND listening; view ticks only while gliding; no timers when idle.
- Voice-sync toggle default **off**. Settings copy must be honest about CPU/battery.
- Copy: no trailing "..." in labels; pill label is exactly "Listening". All icon-only controls get `.help()` and a VoiceOver label; Reduce Motion is honoured.
- Commit only when the suite is green, chained with `&&` (never `;`). Work on branch `feat/teleprompter-voice-sync`, never main. Commit messages end with `Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>`. Ask Alicia before pushing.
- Test command: `xcodebuild test -scheme Atelier -destination 'platform=macOS' 2>&1 | tail -40` (baseline: 239 tests). Focused: add `-only-testing:AtelierTests/<SuiteName>`. Build: `xcodebuild -scheme Atelier -configuration Debug build 2>&1 | tail -20`. The Xcode project uses synchronized folders, so new files under `Atelier/` and `AtelierTests/` are picked up automatically.

## Review Focus

Failure modes the spec implies but no obvious test covers; each is pinned by a test or a manual check in the task named:

1. Speaker re-reads an earlier line: script must not rewind or jump (Task 1 test `neverMovesBackwards`, `revisedPartialTranscriptDoesNotRewind`).
2. Recognizer returns empty/noise-only results (`""`, `"..."`): must be ignored, not crash on empty arrays (Task 1 `emptyOrNoiseInputIsIgnored`).
3. Script edited or replaced while listening: voice mode, cursor and listening must survive without a jump (Task 3 `editingTheScriptWhileListeningKeepsVoiceMode`).
4. Script empty when voice is switched on / play pressed: nothing must start the mic (Task 3 `playingAnEmptyScriptDoesNotStartTheMic`).
5. Audio device changes mid-read (AirPods connect/disconnect) or the recognizer dies: must fall back to manual with a visible cause, never a silently dead mic (Task 6 config-change observer + Task 3 `speechFailureMidReadFallsBack`; manual check).
6. Adding a fourth control changes the top-bar flanks: a side with three controls may overflow the ~100pt flank (Task 4 build + on-device check; tighten the layout rule to 2 | 2 if it overflows, and tell Alicia).

---

### Task 1: `ScriptMatcher` (pure)

**Files:**
- Create: `Atelier/Notch/ScriptMatcher.swift`
- Test: `AtelierTests/ScriptMatcherTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces (used by Task 3):
  - `struct ScriptMatcher: Equatable`
  - `init(scriptWords: [String], cursor: Int = 0)`
  - `private(set) var cursor: Int` (number of script words confirmed spoken = index of the next unread word)
  - `mutating func update(spoken: [String]) -> Int?` (`@discardableResult`; returns the new cursor when it advanced, else nil)
  - `mutating func reset(cursor: Int)`
  - `static func normalize(_ word: String) -> String`, `static func wordsMatch(_ a: String, _ b: String) -> Bool`

- [ ] **Step 1: Write the failing tests**

Create `AtelierTests/ScriptMatcherTests.swift`:

```swift
import Testing
@testable import Atelier

struct ScriptMatcherTests {
    // 0 the, 1 quick, 2 brown, 3 fox, 4 jumps, 5 over, 6 the, 7 lazy,
    // 8 dog, 9 and, 10 runs, 11 away, 12 from, 13 the, 14 farmer, 15 today
    private let script = "the quick brown fox jumps over the lazy dog and runs away from the farmer today"
        .split(separator: " ").map(String.init)

    /// 60 distinct long words that are never within edit distance 1 of each other.
    private var longScript: [String] {
        (0..<60).map { i in
            let a = Character(UnicodeScalar(UInt8(97 + i / 26)))
            let b = Character(UnicodeScalar(UInt8(97 + i % 26)))
            return "\(a)\(a)\(a)\(b)\(b)\(b)"
        }
    }

    @Test func exactMatchAdvancesToTheSpokenWord() {
        var matcher = ScriptMatcher(scriptWords: script)
        #expect(matcher.update(spoken: ["the", "quick", "brown"]) == 3)
        #expect(matcher.cursor == 3)
    }

    @Test func punctuationCaseAndAccentsAreIgnored() {
        var matcher = ScriptMatcher(scriptWords: ["Hello,", "World!", "Café"])
        #expect(matcher.update(spoken: ["hello", "world", "cafe"]) == 3)
    }

    @Test func aFuzzyMisheardLongWordStillMatches() {
        var matcher = ScriptMatcher(scriptWords: script)
        #expect(matcher.update(spoken: ["the", "quick", "brawn"]) == 3)
    }

    @Test func aMisheardMiddleWordStillAdvances() {
        var matcher = ScriptMatcher(scriptWords: script)
        #expect(matcher.update(spoken: ["the", "quik", "brown"]) == 3)
    }

    @Test func skippingAWordWithinTheWindowFollowsTheSpeaker() {
        var matcher = ScriptMatcher(scriptWords: script)
        // "over" was skipped.
        #expect(matcher.update(spoken: ["fox", "jumps", "the", "lazy"]) == 8)
    }

    @Test func aRepeatedPhraseOutsideTheWindowIsIgnored() {
        var matcher = ScriptMatcher(scriptWords: longScript)
        let far = [longScript[50], longScript[51]]
        #expect(matcher.update(spoken: far) == nil)
        #expect(matcher.cursor == 0)
        let near = [longScript[20], longScript[21]]
        #expect(matcher.update(spoken: near) == 22)
    }

    @Test func shortWordsAloneCannotAdvance() {
        var matcher = ScriptMatcher(scriptWords: script)
        #expect(matcher.update(spoken: ["the"]) == nil)
        #expect(matcher.cursor == 0)
    }

    @Test func revisedPartialTranscriptDoesNotRewind() {
        var matcher = ScriptMatcher(scriptWords: script)
        #expect(matcher.update(spoken: ["the", "quick"]) == 2)
        #expect(matcher.update(spoken: ["the", "quick", "brown", "fox"]) == 4)
        // The recognizer rewrites an earlier word: same end position, no move.
        #expect(matcher.update(spoken: ["a", "quick", "brown", "fox"]) == nil)
        #expect(matcher.cursor == 4)
    }

    @Test func neverMovesBackwards() {
        var matcher = ScriptMatcher(scriptWords: script)
        matcher.reset(cursor: 8)
        #expect(matcher.update(spoken: ["quick", "brown"]) == nil)
        #expect(matcher.cursor == 8)
    }

    @Test func emptyOrNoiseInputIsIgnored() {
        var matcher = ScriptMatcher(scriptWords: script)
        #expect(matcher.update(spoken: []) == nil)
        #expect(matcher.update(spoken: ["", "..."]) == nil)
        var empty = ScriptMatcher(scriptWords: [])
        #expect(empty.update(spoken: ["hello", "world"]) == nil)
    }

    @Test func resetClampsToTheScript() {
        var matcher = ScriptMatcher(scriptWords: script)
        matcher.reset(cursor: 999)
        #expect(matcher.cursor == script.count)
        matcher.reset(cursor: -3)
        #expect(matcher.cursor == 0)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `xcodebuild test -scheme Atelier -destination 'platform=macOS' -only-testing:AtelierTests/ScriptMatcherTests 2>&1 | tail -20`
Expected: build FAIL, "cannot find 'ScriptMatcher' in scope".

- [ ] **Step 3: Implement**

Create `Atelier/Notch/ScriptMatcher.swift`:

```swift
import Foundation

/// Aligns the words the speech recognizer heard to the script, forward-only.
/// Pure and Foundation-only (Invariant 1 style) so it is unit-tested without
/// a microphone.
///
/// Why forward-only and windowed: one misheard word, or a phrase that also
/// appears far away in the script, must never teleport the reader. So only a
/// window of words after the cursor is searched, and the cursor never moves
/// back. The recognizer streams a growing transcript that it revises
/// retroactively, so only the last few spoken words (the "tail") are matched.
struct ScriptMatcher: Equatable {
    /// How many words ahead of the cursor are searched.
    static let windowSize = 30
    /// How many of the most recent spoken words are matched.
    static let tailLength = 4
    /// Matched-word weight needed to advance (long words weigh 1, short 0.5).
    static let minimumScore = 1.0

    private let script: [String]
    /// Number of script words confirmed spoken (= index of the next unread word).
    private(set) var cursor: Int

    init(scriptWords: [String], cursor: Int = 0) {
        script = scriptWords.map(Self.normalize)
        self.cursor = min(max(cursor, 0), scriptWords.count)
    }

    mutating func reset(cursor: Int) {
        self.cursor = min(max(cursor, 0), script.count)
    }

    /// Feeds the full spoken transcript so far. Returns the new cursor if it
    /// advanced, nil if the words didn't match with enough confidence.
    @discardableResult
    mutating func update(spoken: [String]) -> Int? {
        let tail = Array(spoken.map(Self.normalize).filter { !$0.isEmpty }.suffix(Self.tailLength))
        guard let last = tail.last, cursor < script.count else { return nil }

        let lastEnd = min(cursor + Self.windowSize, script.count)
        var best: (end: Int, score: Double)?
        for end in (cursor + 1)...lastEnd {
            // The word just spoken must be the word the cursor lands on.
            guard Self.wordsMatch(last, script[end - 1]) else { continue }
            var score = 0.0
            for (offset, word) in tail.reversed().enumerated() {
                let scriptIndex = end - 1 - offset
                guard scriptIndex >= 0 else { break }
                if Self.wordsMatch(word, script[scriptIndex]) { score += Self.weight(word) }
            }
            // Strictly greater: on a tie the nearest candidate wins.
            if score >= Self.minimumScore, score > (best?.score ?? 0) {
                best = (end, score)
            }
        }
        guard let best else { return nil }
        cursor = best.end
        return cursor
    }

    // MARK: Word comparison

    /// Lowercased, accents folded, letters and digits only.
    static func normalize(_ word: String) -> String {
        let folded = word.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        return String(folded.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }

    /// Equal, or (for longer words) within a small edit distance, so
    /// "recognise"/"recognize" match but "the"/"then" do not.
    static func wordsMatch(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        let shorter = min(a.count, b.count)
        guard shorter >= 5 else { return false }
        return editDistance(a, b) <= (shorter >= 9 ? 2 : 1)
    }

    private static func weight(_ word: String) -> Double {
        word.count >= 4 ? 1.0 : 0.5
    }

    private static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        var previous = Array(0...b.count)
        for i in 1...a.count {
            var current = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                current[j] = min(
                    previous[j] + 1,
                    current[j - 1] + 1,
                    previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1)
                )
            }
            previous = current
        }
        return previous[b.count]
    }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `xcodebuild test -scheme Atelier -destination 'platform=macOS' -only-testing:AtelierTests/ScriptMatcherTests 2>&1 | tail -20`
Expected: all `ScriptMatcherTests` PASS. If `skippingAWordWithinTheWindow...` or `aRepeatedPhrase...` fails, re-derive the expected index from the script comment at the top of the test before changing the algorithm.

- [ ] **Step 5: Full suite, then commit**

Run: `xcodebuild test -scheme Atelier -destination 'platform=macOS' 2>&1 | tail -15 && git add Atelier/Notch/ScriptMatcher.swift AtelierTests/ScriptMatcherTests.swift && git commit -m "feat(teleprompter): ScriptMatcher, forward-only fuzzy word alignment (stage 4, task 1)" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"`
Expected: 250 tests pass (239 + 11), commit created.

---

### Task 2: Voice mode in `TeleprompterScroll` (pure)

**Files:**
- Modify: `Atelier/Notch/TeleprompterScroll.swift`
- Test: `AtelierTests/TeleprompterScrollTests.swift` (append a new `struct TeleprompterScrollVoiceTests` at the end of the file)

**Interfaces:**
- Consumes: nothing new.
- Produces (used by Task 3):
  - `var isVoiceMode: Bool`
  - `static let voiceCatchUpSeconds: Double = 1.5`
  - `mutating func enterVoiceMode(at: Date)`, `mutating func exitVoiceMode(at: Date)`
  - `mutating func setTarget(_ word: Double, at: Date)` (no-op unless in voice mode; never moves backwards; clamps to `totalWords`)
  - `func isGliding(at: Date) -> Bool`, `func glideSecondsRemaining(at: Date) -> TimeInterval`
  - Changed semantics in voice mode: `isPlaying(at:)` == `isGliding(at:)`; `play(at:)` is ignored; `pause(at:)` freezes; `seek(to:at:)` leaves voice mode.

- [ ] **Step 1: Write the failing tests**

Append to `AtelierTests/TeleprompterScrollTests.swift`:

```swift
struct TeleprompterScrollVoiceTests {
    private let t0 = Date(timeIntervalSinceReferenceDate: 1_000)

    /// 120 wpm = 2 words/sec; catch-up is 1.5s, so a gap of 90 words glides at 60 words/sec.
    private func voiceScroll(total: Int = 1_000) -> TeleprompterScroll {
        var scroll = TeleprompterScroll(totalWords: total, wpm: 120)
        scroll.enterVoiceMode(at: t0)
        return scroll
    }

    @Test func aSmallGapGlidesAtTheReadingSpeed() {
        var scroll = voiceScroll()
        scroll.setTarget(1, at: t0)
        #expect(scroll.position(at: t0.addingTimeInterval(0.25)) == 0.5)
        #expect(scroll.position(at: t0.addingTimeInterval(5)) == 1)
    }

    @Test func aLargeGapCatchesUpWithinTheCatchUpTime() {
        var scroll = voiceScroll()
        scroll.setTarget(90, at: t0)
        #expect(scroll.position(at: t0.addingTimeInterval(0.75)) == 45)
        #expect(scroll.position(at: t0.addingTimeInterval(1.5)) == 90)
        #expect(scroll.position(at: t0.addingTimeInterval(60)) == 90)
    }

    @Test func retargetingMidGlideDoesNotJump() {
        var scroll = voiceScroll()
        scroll.setTarget(90, at: t0)
        let mid = t0.addingTimeInterval(0.75)
        scroll.setTarget(100, at: mid)
        #expect(scroll.position(at: mid) == 45)
        #expect(scroll.position(at: mid.addingTimeInterval(60)) == 100)
    }

    @Test func neverGoesBackwards() {
        var scroll = voiceScroll()
        scroll.setTarget(50, at: t0)
        let later = t0.addingTimeInterval(60)
        scroll.setTarget(10, at: later)
        #expect(scroll.position(at: later.addingTimeInterval(60)) == 50)
    }

    @Test func aTargetPastTheEndClampsAndFinishes() {
        var scroll = voiceScroll(total: 100)
        scroll.setTarget(500, at: t0)
        let later = t0.addingTimeInterval(60)
        #expect(scroll.position(at: later) == 100)
        #expect(scroll.isFinished(at: later))
    }

    @Test func playingMeansGlidingInVoiceMode() {
        var scroll = voiceScroll()
        #expect(!scroll.isPlaying(at: t0))
        scroll.setTarget(90, at: t0)
        #expect(scroll.isGliding(at: t0.addingTimeInterval(0.5)))
        #expect(scroll.isPlaying(at: t0.addingTimeInterval(0.5)))
        #expect(!scroll.isGliding(at: t0.addingTimeInterval(2)))
        #expect(!scroll.isPlaying(at: t0.addingTimeInterval(2)))
    }

    @Test func glideSecondsRemainingCountsDownToArrival() {
        var scroll = voiceScroll()
        scroll.setTarget(90, at: t0)
        #expect(scroll.glideSecondsRemaining(at: t0) == 1.5)
        #expect(scroll.glideSecondsRemaining(at: t0.addingTimeInterval(0.75)) == 0.75)
        #expect(scroll.glideSecondsRemaining(at: t0.addingTimeInterval(5)) == 0)
    }

    @Test func pauseFreezesTheGlide() {
        var scroll = voiceScroll()
        scroll.setTarget(90, at: t0)
        scroll.pause(at: t0.addingTimeInterval(0.5))
        #expect(scroll.position(at: t0.addingTimeInterval(60)) == 30)
        #expect(!scroll.isGliding(at: t0.addingTimeInterval(60)))
    }

    @Test func playIsIgnoredInVoiceMode() {
        var scroll = voiceScroll()
        scroll.play(at: t0)
        #expect(scroll.position(at: t0.addingTimeInterval(100)) == 0)
    }

    @Test func seekLeavesVoiceMode() {
        var scroll = voiceScroll()
        scroll.setTarget(90, at: t0)
        scroll.seek(to: 10, at: t0.addingTimeInterval(5))
        #expect(!scroll.isVoiceMode)
        #expect(scroll.position(at: t0.addingTimeInterval(100)) == 10)
    }

    @Test func leavingVoiceModeKeepsThePositionAndTheClockResumes() {
        var scroll = voiceScroll()
        scroll.setTarget(90, at: t0)
        let mid = t0.addingTimeInterval(0.75)
        scroll.exitVoiceMode(at: mid)
        #expect(scroll.position(at: mid.addingTimeInterval(100)) == 45)
        scroll.play(at: mid.addingTimeInterval(100))
        // 2 words/sec.
        #expect(scroll.position(at: mid.addingTimeInterval(101)) == 47)
    }

    @Test func enteringVoiceModeWhilePlayingKeepsThePosition() {
        var scroll = TeleprompterScroll(totalWords: 1_000, wpm: 120)
        scroll.play(at: t0)
        let mid = t0.addingTimeInterval(30)
        scroll.enterVoiceMode(at: mid)
        #expect(scroll.position(at: mid.addingTimeInterval(100)) == 60)
    }

    @Test func changingWPMMidGlideDoesNotJump() {
        var scroll = voiceScroll()
        scroll.setTarget(90, at: t0)
        let mid = t0.addingTimeInterval(0.75)
        scroll.setWPM(60, at: mid)
        #expect(scroll.position(at: mid) == 45)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `xcodebuild test -scheme Atelier -destination 'platform=macOS' -only-testing:AtelierTests/TeleprompterScrollVoiceTests 2>&1 | tail -20`
Expected: build FAIL, `enterVoiceMode` not found.

- [ ] **Step 3: Implement**

In `Atelier/Notch/TeleprompterScroll.swift`:

1. Update the doc comment's last sentence to: `the stage-4 speech source drives it through voice mode (setTarget) instead of the clock.`

2. Add stored state and constants after `private var anchorDate: Date?`:

```swift
    /// Non-nil in voice mode: the word index the speech recognizer says the
    /// speaker has reached. `position(at:)` then glides from the anchor toward
    /// it instead of following the clock, and stops on arrival (so a silent
    /// speaker = a still script, with nothing ticking).
    private var target: Double?

    /// However big the gap, the glide arrives within this many seconds, so a
    /// fast reader doesn't watch the script lag behind.
    static let voiceCatchUpSeconds: Double = 1.5

    var isVoiceMode: Bool { target != nil }
```

3. Replace `position(at:)` with:

```swift
    func position(at date: Date) -> Double {
        guard let anchorDate else { return anchorPosition }
        let elapsed = max(0, date.timeIntervalSince(anchorDate))
        if let target {
            return min(target, anchorPosition + elapsed * glideRate(gap: target - anchorPosition))
        }
        return min(Double(totalWords), anchorPosition + elapsed * wpm / 60)
    }

    /// Words per second while gliding: at least the reading speed, faster when
    /// the gap is large enough that it wouldn't arrive within the catch-up time.
    private func glideRate(gap: Double) -> Double {
        max(wpm / 60, max(0, gap) / Self.voiceCatchUpSeconds)
    }

    func isGliding(at date: Date) -> Bool {
        guard let target else { return false }
        return position(at: date) < target
    }

    func glideSecondsRemaining(at date: Date) -> TimeInterval {
        guard let target, anchorDate != nil else { return 0 }
        let rate = glideRate(gap: target - anchorPosition)
        return max(0, target - position(at: date)) / rate
    }
```

4. Replace `isPlaying(at:)` with:

```swift
    /// Playing means running and not yet at the end. In voice mode it means
    /// gliding toward the spoken position.
    func isPlaying(at date: Date) -> Bool {
        if target != nil { return isGliding(at: date) }
        return anchorDate != nil && !isFinished(at: date)
    }
```

5. In `play(at:)` change the first guard to `guard totalWords > 0, target == nil else { return }`.

6. In `pause(at:)` append, after `anchorDate = nil`:

```swift
        if target != nil { target = anchorPosition }
```

7. Replace `seek(to:at:)` with:

```swift
    /// A hand-scroll or explicit jump. Leaves voice mode (the model re-enters
    /// it when listening resumes), so a leftover glide can't undo the jump.
    mutating func seek(to word: Double, at date: Date) {
        let wasVoice = target != nil
        target = nil
        anchorPosition = min(max(word, 0), Double(totalWords))
        if wasVoice {
            anchorDate = nil
        } else if anchorDate != nil {
            anchorDate = date
        }
    }
```

8. Add the voice-mode mutators before `settle`:

```swift
    /// Switches to voice mode where the script currently is: nothing moves
    /// until the first `setTarget`.
    mutating func enterVoiceMode(at date: Date) {
        anchorPosition = position(at: date)
        anchorDate = nil
        target = anchorPosition
    }

    mutating func exitVoiceMode(at date: Date) {
        anchorPosition = position(at: date)
        anchorDate = nil
        target = nil
    }

    /// The speaker has reached `word`: glide there. Ignored outside voice
    /// mode; never moves backwards; clamped to the end of the script.
    mutating func setTarget(_ word: Double, at date: Date) {
        guard target != nil else { return }
        anchorPosition = position(at: date)
        target = min(max(word, anchorPosition), Double(totalWords))
        anchorDate = date
    }
```

- [ ] **Step 4: Run to verify pass**

Run: `xcodebuild test -scheme Atelier -destination 'platform=macOS' -only-testing:AtelierTests/TeleprompterScrollVoiceTests -only-testing:AtelierTests/TeleprompterScrollTests 2>&1 | tail -20`
Expected: all voice tests and all original scroll tests PASS.

- [ ] **Step 5: Full suite, then commit**

Run: `xcodebuild test -scheme Atelier -destination 'platform=macOS' 2>&1 | tail -15 && git add Atelier/Notch/TeleprompterScroll.swift AtelierTests/TeleprompterScrollTests.swift && git commit -m "feat(teleprompter): voice mode in TeleprompterScroll, glide toward a spoken target (stage 4, task 2)" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"`
Expected: 263 tests pass (250 + 13), commit created.

---

### Task 3: Model voice mode + `SpeechWordSource` seam

**Files:**
- Create: `Atelier/Teleprompter/SpeechWordSource.swift`
- Modify: `Atelier/Teleprompter/TeleprompterModel.swift`
- Modify: `Atelier/AtelierSettings.swift` (add the voice-sync key, needed for persistence)
- Test: `AtelierTests/TeleprompterModelTests.swift` (append a new `TeleprompterModelVoiceTests` suite)

**Interfaces:**
- Consumes: `ScriptMatcher` (Task 1), voice-mode `TeleprompterScroll` API (Task 2).
- Produces (used by Tasks 4, 6, 7):
  - `@MainActor protocol SpeechWordSource: AnyObject { var onWords: (([String]) -> Void)? { get set }; var onFailure: ((String) -> Void)? { get set }; func prepare() async -> String?; func start(); func stop() }` (`prepare()` returns nil when ready, else a user-facing reason)
  - `AtelierSettings.teleprompterVoiceSyncKey` / `teleprompterVoiceSync: Bool` (default false)
  - `TeleprompterModel.init(store:speech:persistsWPM:persistsVoiceSync:initialWPM:)` (`speech: SpeechWordSource? = nil`, `persistsVoiceSync: Bool = true`)
  - `@Published private(set) var voiceSyncEnabled: Bool`, `@Published private(set) var voiceUnavailableReason: String?`, `@Published private(set) var isGliding: Bool`
  - `var isAnimating: Bool` (voice: gliding; manual: playing), used by views to decide whether to tick
  - `func setVoiceSync(_ on: Bool, now: Date = .now) async`
  - `func applySpeech(words: [String], now: Date = .now)`, `func applySpeechPosition(_ cursor: Int, now: Date = .now)`

- [ ] **Step 1: Add the settings key**

In `Atelier/AtelierSettings.swift`, next to the other teleprompter keys add:

```swift
    static let teleprompterVoiceSyncKey = "teleprompterVoiceSync"
```

Next to the other teleprompter accessors add:

```swift
    /// Voice sync: the script follows the speaker's voice. Off by default
    /// (it uses the microphone and on-device speech recognition).
    static var teleprompterVoiceSync: Bool {
        get { UserDefaults.standard.bool(forKey: teleprompterVoiceSyncKey) }
        set { UserDefaults.standard.set(newValue, forKey: teleprompterVoiceSyncKey) }
    }
```

(A missing key reads `false`, so no `register(defaults:)` entry is needed.)

- [ ] **Step 2: Create the protocol**

Create `Atelier/Teleprompter/SpeechWordSource.swift`:

```swift
import Foundation

/// Where spoken words come from. `SpeechRecognizer` is the real one; tests use
/// a fake, so the model's voice-mode rules are unit-tested without a microphone.
@MainActor
protocol SpeechWordSource: AnyObject {
    /// The full transcript so far, as words (it grows and is revised).
    var onWords: (([String]) -> Void)? { get set }
    /// The source can't continue (device lost, recognizer died). Argument: why.
    var onFailure: ((String) -> Void)? { get set }
    /// Asks for permissions and checks the recognizer is usable. Returns nil
    /// when ready, otherwise a short user-facing reason.
    func prepare() async -> String?
    /// Starts capturing. Only ever called while listening.
    func start()
    /// Stops capturing and releases the microphone.
    func stop()
}
```

- [ ] **Step 3: Write the failing tests**

Append to `AtelierTests/TeleprompterModelTests.swift`:

```swift
@MainActor
final class FakeSpeech: SpeechWordSource {
    var onWords: (([String]) -> Void)?
    var onFailure: ((String) -> Void)?
    var prepareResult: String?
    private(set) var isRunning = false
    private(set) var startCount = 0

    func prepare() async -> String? { prepareResult }
    func start() { isRunning = true; startCount += 1 }
    func stop() { isRunning = false }
    func hear(_ words: [String]) { onWords?(words) }
    func fail(_ reason: String) { onFailure?(reason) }
}

@MainActor
struct TeleprompterModelVoiceTests {
    private let script = "one two three four five six seven eight nine ten"

    private func makeModel(script text: String? = nil) throws -> (TeleprompterModel, FakeSpeech, ScriptStore) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AtelierVoiceTests-\(UUID().uuidString)")
        let store = ScriptStore(directory: dir)
        try store.save(text ?? script)
        let speech = FakeSpeech()
        let model = TeleprompterModel(store: store, speech: speech, persistsWPM: false, persistsVoiceSync: false, initialWPM: 140)
        model.updateLayout(width: 400, fontSize: 15, mono: false)
        return (model, speech, store)
    }

    private func later(_ seconds: TimeInterval = 10) -> Date { Date().addingTimeInterval(seconds) }

    @Test func enablingVoiceSyncEntersVoiceModeWithoutListening() async throws {
        let (model, speech, _) = try makeModel()
        await model.setVoiceSync(true)
        #expect(model.voiceSyncEnabled)
        #expect(model.scroll.isVoiceMode)
        #expect(!model.isPlaying)
        #expect(!speech.isRunning)
    }

    @Test func playStartsListeningAndPauseStops() async throws {
        let (model, speech, _) = try makeModel()
        await model.setVoiceSync(true)
        model.play()
        #expect(model.isPlaying && speech.isRunning)
        #expect(model.wantsNotchOpen)
        model.pause()
        #expect(!model.isPlaying && !speech.isRunning)
    }

    @Test func heardWordsMoveTheScrollTarget() async throws {
        let (model, speech, _) = try makeModel()
        await model.setVoiceSync(true)
        model.play()
        speech.hear(["one", "two", "three"])
        #expect(model.scroll.position(at: later()) == 3)
        #expect(model.isGliding)
        #expect(model.isAnimating)
    }

    @Test func silenceOrNoiseDoesNothing() async throws {
        let (model, speech, _) = try makeModel()
        await model.setVoiceSync(true)
        model.play()
        speech.hear([])
        speech.hear(["", "..."])
        #expect(model.scroll.position(at: later()) == 0)
    }

    @Test func wordsHeardWhileNotListeningAreIgnored() async throws {
        let (model, speech, _) = try makeModel()
        await model.setVoiceSync(true)
        speech.hear(["one", "two", "three"])
        #expect(model.scroll.position(at: later()) == 0)
    }

    @Test func thePointerLeavingDoesNotStopListening() async throws {
        let (model, speech, _) = try makeModel()
        await model.setVoiceSync(true)
        model.play()
        model.setPointerInside(true)
        #expect(model.isPlaying && speech.isRunning)
        model.setPointerInside(false)
        #expect(model.isPlaying && speech.isRunning)
    }

    @Test func readingToTheEndFinishesAndStopsListening() async throws {
        let (model, speech, _) = try makeModel()
        await model.setVoiceSync(true)
        model.play()
        speech.hear(["seven", "eight", "nine", "ten"])
        let end = later()
        model.settle(now: end)
        #expect(!model.isPlaying)
        #expect(!speech.isRunning)
        #expect(model.hasFinished(now: end))
    }

    @Test func deniedPermissionFallsBackToManualWithAReason() async throws {
        let (model, speech, _) = try makeModel()
        speech.prepareResult = "Microphone access is off."
        await model.setVoiceSync(true)
        #expect(!model.voiceSyncEnabled)
        #expect(model.voiceUnavailableReason == "Microphone access is off.")
        model.play()
        #expect(model.isPlaying)
        #expect(!speech.isRunning)
        #expect(!model.scroll.isVoiceMode)
    }

    @Test func aMissingSpeechSourceFallsBackToo() async throws {
        let store = ScriptStore(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("AtelierVoiceTests-\(UUID().uuidString)"))
        let model = TeleprompterModel(store: store, speech: nil, persistsWPM: false, persistsVoiceSync: false, initialWPM: 140)
        await model.setVoiceSync(true)
        #expect(!model.voiceSyncEnabled)
        #expect(model.voiceUnavailableReason != nil)
    }

    @Test func speechFailureMidReadFallsBack() async throws {
        let (model, speech, _) = try makeModel()
        await model.setVoiceSync(true)
        model.play()
        speech.fail("The microphone changed.")
        #expect(model.voiceUnavailableReason == "The microphone changed.")
        #expect(!model.voiceSyncEnabled)
        #expect(!speech.isRunning && !model.isPlaying)
        #expect(!model.scroll.isVoiceMode)
    }

    @Test func disablingVoiceSyncReturnsToManual() async throws {
        let (model, speech, _) = try makeModel()
        await model.setVoiceSync(true)
        model.play()
        await model.setVoiceSync(false)
        #expect(!model.voiceSyncEnabled)
        #expect(!speech.isRunning && !model.isPlaying)
        #expect(!model.scroll.isVoiceMode)
        #expect(model.voiceUnavailableReason == nil)
    }

    @Test func resumingListeningKeepsTrackingFromThePausedPlace() async throws {
        let (model, speech, _) = try makeModel()
        await model.setVoiceSync(true)
        model.play()
        speech.hear(["one", "two", "three"])
        model.pause()
        model.play()
        #expect(speech.startCount == 2)
        speech.hear(["four", "five", "six"])
        #expect(model.scroll.position(at: later()) == 6)
    }

    @Test func playingAnEmptyScriptDoesNotStartTheMic() async throws {
        let (model, speech, _) = try makeModel(script: "")
        await model.setVoiceSync(true)
        model.play()
        #expect(!speech.isRunning && !model.isPlaying)
    }

    @Test func editingTheScriptWhileListeningKeepsVoiceMode() async throws {
        let (model, speech, store) = try makeModel()
        await model.setVoiceSync(true)
        model.play()
        speech.hear(["one", "two", "three"])
        try store.save(script + " eleven twelve")
        model.reloadScript()
        #expect(model.voiceSyncEnabled && model.scroll.isVoiceMode)
        #expect(model.isPlaying && speech.isRunning)
        speech.hear(["eleven", "twelve"])
        #expect(model.scroll.position(at: later()) == 12)
    }
}
```

- [ ] **Step 4: Run to verify failure**

Run: `xcodebuild test -scheme Atelier -destination 'platform=macOS' -only-testing:AtelierTests/TeleprompterModelVoiceTests 2>&1 | tail -20`
Expected: build FAIL (`init(store:speech:...)` and `setVoiceSync` don't exist).

- [ ] **Step 5: Implement in `TeleprompterModel.swift`**

Edits, top to bottom:

1. Add published state after `pausedForPointer`:

```swift
    /// Voice sync is on: the script follows the speaker's voice, and
    /// "playing" means *listening*, not "the clock is running".
    @Published private(set) var voiceSyncEnabled = false
    /// Why voice sync couldn't be used (permission denied, no on-device
    /// model, device lost); nil when there is nothing to report. The model
    /// then runs on the manual WPM pace.
    @Published private(set) var voiceUnavailableReason: String?
    /// Voice mode only: the script is currently gliding toward the spoken
    /// position. Views tick only while this is true.
    @Published private(set) var isGliding = false

    /// Whether views need to redraw continuously: the clock is running
    /// (manual) or a glide is in flight (voice).
    var isAnimating: Bool { voiceSyncEnabled ? isGliding : isPlaying }
```

2. Add private state after `scriptObserver`:

```swift
    private let speech: SpeechWordSource?
    private let persistsVoiceSync: Bool
    private var matcher = ScriptMatcher(scriptWords: [])
    private var glideTask: Task<Void, Never>?
    private var isPreparingVoice = false
```

3. Replace the `init` signature/body start:

```swift
    init(
        store: ScriptStore = .shared,
        speech: SpeechWordSource? = nil,
        persistsWPM: Bool = true,
        persistsVoiceSync: Bool = true,
        initialWPM: Double = AtelierSettings.teleprompterWPM
    ) {
        self.store = store
        self.speech = speech
        self.persistsWPM = persistsWPM
        self.persistsVoiceSync = persistsVoiceSync
        scroll = TeleprompterScroll(totalWords: 0, wpm: initialWPM)
        speech?.onWords = { [weak self] words in self?.applySpeech(words: words) }
        speech?.onFailure = { [weak self] reason in self?.failVoiceSync(reason) }
        scriptObserver = ...  // unchanged from here
```

(Keep the existing `scriptObserver = NotificationCenter...` block and `reloadScript()` call exactly as they are.)

4. In `reloadScript`, replace the three lines after `if wasPlaying, ... { scroll.play(at: now) }`:

```swift
        if voiceSyncEnabled {
            glideTask?.cancel()
            isGliding = false
            scroll.enterVoiceMode(at: now)
            matcher = ScriptMatcher(scriptWords: reloaded.words, cursor: Int(scroll.position(at: now)))
            isPlaying = wasPlaying && !scroll.isFinished(at: now)
            if !isPlaying { speech?.stop() }
        } else {
            if wasPlaying, !scroll.isFinished(at: now) { scroll.play(at: now) }
            isPlaying = scroll.isPlaying(at: now)
        }
        relayout()
        scheduleFinish(now: now)
```

(i.e. the old `if wasPlaying...`, `isPlaying = ...` lines move into the `else`; `relayout()` and `scheduleFinish` stay after.)

5. Replace `play`, `pause`, and `settle`:

```swift
    func play(now: Date = .now) {
        if voiceSyncEnabled { startListening(now: now); return }
        scroll.play(at: now)
        isPlaying = scroll.isPlaying(at: now)
        pausedForPointer = false
        scheduleFinish(now: now)
    }

    func pause(now: Date = .now) {
        if voiceSyncEnabled { speech?.stop() }
        scroll.pause(at: now)
        isPlaying = false
        isGliding = false
        pausedForPointer = false
        glideTask?.cancel()
        cancelFinishTask()
    }
```

```swift
    func settle(now: Date = .now) {
        scroll.settle(at: now)
        if voiceSyncEnabled {
            // Voice mode: finished only once the glide has reached the end.
            guard scroll.isFinished(at: now) else { return }
            speech?.stop()
            isPlaying = false
            isGliding = false
            return
        }
        isPlaying = scroll.isPlaying(at: now)
        scheduleFinish(now: now)   // reschedules only if somehow still playing
    }
```

6. In `setPointerInside`, add as the first line: `guard !voiceSyncEnabled else { return }` (a pointer leaving must not kill the mic mid-read). Keep the rest.

7. Replace `scheduleFinish`:

```swift
    private func scheduleFinish(now: Date) {
        cancelFinishTask()
        // Voice mode: only once the speaker has reached the last word; a
        // silent speaker mid-script must never "finish".
        if voiceSyncEnabled, matcher.cursor < script.wordCount { return }
        guard scroll.isPlaying(at: now) else { return }
        // A hair past the end so `settle` sees it as finished.
        let seconds = voiceSyncEnabled ? scroll.glideSecondsRemaining(at: now) : scroll.secondsRemaining(at: now)
        let wait = seconds + 0.05
        finishTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled else { return }
            self?.settle()
        }
    }
```

8. Add a new `// MARK: Voice sync` section before `// MARK: Finish timer`:

```swift
    // MARK: Voice sync

    /// Turns voice sync on or off. Turning on asks for permissions (once) and
    /// checks the recognizer; on any problem it stays off with a reason and
    /// the model keeps working on the manual WPM pace.
    func setVoiceSync(_ on: Bool, now: Date = .now) async {
        guard on != voiceSyncEnabled, !isPreparingVoice else { return }
        if on {
            guard let speech else {
                failVoiceSync("Voice sync isn't available on this Mac.", now: now)
                return
            }
            isPreparingVoice = true
            let problem = await speech.prepare()
            isPreparingVoice = false
            if let problem {
                failVoiceSync(problem, now: now)
                return
            }
            pause(now: now)
            voiceUnavailableReason = nil
            voiceSyncEnabled = true
            scroll.enterVoiceMode(at: now)
            matcher = ScriptMatcher(scriptWords: script.words, cursor: Int(scroll.position(at: now)))
        } else {
            pause(now: now)   // stops the mic while still in voice mode
            voiceSyncEnabled = false
            voiceUnavailableReason = nil
            scroll.exitVoiceMode(at: now)
        }
        if persistsVoiceSync { AtelierSettings.teleprompterVoiceSync = on }
    }

    /// Falls back to manual pace, keeping the reason so the UI can say why.
    private func failVoiceSync(_ reason: String, now: Date = .now) {
        if voiceSyncEnabled {
            pause(now: now)
            voiceSyncEnabled = false
            scroll.exitVoiceMode(at: now)
        }
        voiceUnavailableReason = reason
        if persistsVoiceSync { AtelierSettings.teleprompterVoiceSync = false }
    }

    private func startListening(now: Date) {
        guard let speech, !script.isEmpty else { return }
        if scroll.isFinished(at: now) { scroll.seek(to: 0, at: now) }
        scroll.enterVoiceMode(at: now)
        matcher.reset(cursor: Int(scroll.position(at: now)))
        isPlaying = true
        pausedForPointer = false
        speech.start()
    }

    /// Speech recognizer output: words heard so far -> matcher -> scroll target.
    func applySpeech(words: [String], now: Date = .now) {
        guard voiceSyncEnabled, isPlaying, let cursor = matcher.update(spoken: words) else { return }
        applySpeechPosition(cursor, now: now)
    }

    /// The speaker has reached word `cursor` of the script: glide there.
    func applySpeechPosition(_ cursor: Int, now: Date = .now) {
        scroll.setTarget(Double(cursor), at: now)
        isGliding = true
        glideTask?.cancel()
        let wait = scroll.glideSecondsRemaining(at: now) + 0.05
        glideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled else { return }
            self?.isGliding = false
        }
        scheduleFinish(now: now)
    }
```

- [ ] **Step 6: Run to verify pass**

Run: `xcodebuild test -scheme Atelier -destination 'platform=macOS' -only-testing:AtelierTests/TeleprompterModelVoiceTests -only-testing:AtelierTests/TeleprompterModelTests -only-testing:AtelierTests/TeleprompterHoldOpenTests 2>&1 | tail -25`
Expected: all PASS, including every pre-existing model test.

If `readingToTheEndFinishesAndStopsListening` fails because the finish task fired first, that is fine as long as the assertions hold; if `hasFinished` is false, check that `applySpeechPosition` target reached `totalWords` (the ten-word script's last four words are "seven eight nine ten").

- [ ] **Step 7: Full suite, then commit**

Run: `xcodebuild test -scheme Atelier -destination 'platform=macOS' 2>&1 | tail -15 && git add Atelier/Teleprompter/SpeechWordSource.swift Atelier/Teleprompter/TeleprompterModel.swift Atelier/AtelierSettings.swift AtelierTests/TeleprompterModelTests.swift && git commit -m "feat(teleprompter): model voice mode, listen/stop semantics, fallback (stage 4, task 3)" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"`
Expected: 277 tests pass (263 + 14), commit created.

---

### Task 4: Voice control in the top bar + Settings toggle (build-verified)

**Files:**
- Modify: `Atelier/Notch/TeleprompterControlLayout.swift` (add the `voice` case)
- Modify: `AtelierTests/TeleprompterControlLayoutTests.swift` (intentional expectation updates)
- Modify: `Atelier/UI/TeleprompterControlStrip.swift` (voice button)
- Modify: `Atelier/Settings/Panes/TeleprompterPane.swift` (toggle, titles/icons)
- Modify: `Atelier/Notch/NotchController.swift` (`applyLiveSettings` applies the setting)

**Interfaces:**
- Consumes: `TeleprompterModel.setVoiceSync`, `.voiceSyncEnabled`, `.voiceUnavailableReason`, `AtelierSettings.teleprompterVoiceSync(Key)` (Task 3).
- Produces: `TeleprompterControl.voice`; top-bar order now has 5 rows (4 controls + notch).

- [ ] **Step 1: Add the enum case and update the expectations first (tests drive the change)**

Edit `AtelierTests/TeleprompterControlLayoutTests.swift`. Each of these existing tests encodes "three controls"; with a fourth control the correct expectations are:

- `emptyStoredOrderGivesTheDefaultLayout`: `layout.right == [.ring, .voice]` (left stays `[.play, .speed]`).
- `followsTheStoredOrderAndSplitsAtTheNotch`: `layout.left == [.ring]`, `layout.right == [.speed, .play, .voice]`.
- `unknownNamesAndDuplicatesAreIgnored`: `layout.left == [.speed, .play]`, `layout.right == [.ring, .voice]`.
- `controlsMissingFromTheStoredListAreAppended`: `layout.left.count + layout.right.count == 4`.
- `normalizedAlwaysListsAllFourRowsWithTheNotchInTheMiddle`: rename to `normalizedAlwaysListsAllFiveRowsWithTheNotchInTheMiddle`; `order.count == 5`; `Set(order) == ["play", "speed", "ring", "voice", "notch"]`; `[1, 2, 3].contains(order.firstIndex(of: "notch")!)`.
- `movingARowDownPutsItAfterTheTarget`: `order == ["speed", "notch", "play", "ring", "voice"]`.
- `movingARowUpPutsItBeforeTheTarget`: `order.first == "ring"` and `order.count == 5`.
- `movingOntoItselfOrAnUnknownRowChangesNothing`: `let start = ["play", "speed", "notch", "ring", "voice"]`.

Add one new test to the same file, pinning the migration of an order saved before this feature:

```swift
    @Test func anOrderSavedBeforeVoiceSyncGetsTheNewControlAppended() {
        let layout = TeleprompterControlLayout.resolve(stored: ["play", "speed", "notch", "ring"])
        #expect(layout.left == [.play, .speed])
        #expect(layout.right == [.ring, .voice])
    }
```

- [ ] **Step 2: Run to verify failure**

Run: `xcodebuild test -scheme Atelier -destination 'platform=macOS' -only-testing:AtelierTests/TeleprompterControlLayoutTests 2>&1 | tail -20`
Expected: build FAIL (`.voice` doesn't exist).

- [ ] **Step 3: Implement the layout change**

In `TeleprompterControlLayout.swift` add `case voice` after `case ring` in `TeleprompterControl`. Update the two doc comments that say "three controls"/"four-row order" to "four controls"/"five-row order (four controls plus the notch marker)". The logic needs no other change: `normalized` already appends missing controls and clamps the marker between the first and last control.

Run the layout tests again. Expected: all PASS.

- [ ] **Step 4: Settings pane**

In `TeleprompterPane.swift`:
- Add `@AppStorage(AtelierSettings.teleprompterVoiceSyncKey) private var voiceSync = false` and `@ObservedObject private var model = TeleprompterModel.shared` with the other properties.
- In `title(for:)` add `case "voice": "Voice sync"`; in the icon function add `case "voice": "mic.fill"`.
- Add a new section between "Reading" and "Top bar":

```swift
            Section("Voice") {
                Toggle("Follow my voice", isOn: $voiceSync)
                Text("The script follows what you say, and waits when you stop. Uses the microphone and on-device speech recognition, which costs some CPU and battery while listening. Nothing leaves your Mac.")
                    .font(.callout).foregroundStyle(.secondary)
                if let reason = model.voiceUnavailableReason {
                    Text(reason).font(.callout).foregroundStyle(.orange)
                }
            }
            .disabled(!enabled)
```

- [ ] **Step 5: Apply the setting live**

In `NotchController.applyLiveSettings()` (after the `teleprompterEnabled` pause line) add:

```swift
        // Voice sync: the setting is the persisted preference, the model owns
        // the effective state (it flips the setting back off if permission or
        // the recognizer isn't available). No-op when they already agree.
        if AtelierSettings.teleprompterEnabled {
            Task { await TeleprompterModel.shared.setVoiceSync(AtelierSettings.teleprompterVoiceSync) }
        }
```

- [ ] **Step 6: The strip button**

In `TeleprompterControlStrip.swift` add to `controlView`: `case .voice: voiceButton`, and this view (same size/press style as play/pause):

```swift
    private var voiceButton: some View {
        let on = model.voiceSyncEnabled
        let problem = model.voiceUnavailableReason
        return Button {
            Task { await model.setVoiceSync(!on) }
        } label: {
            Image(systemName: on ? "mic.fill" : (problem == nil ? "mic" : "mic.slash"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: Self.controlSize, height: Self.controlSize)
                .background(Circle().fill(Color.white.opacity(on ? 0.30 : 0.14)))
                .contentShape(Circle())
        }
        .buttonStyle(TeleprompterPressStyle())
        .help(problem ?? (on ? "Voice sync on: the script follows your voice" : "Voice sync: let the script follow your voice"))
        .accessibilityLabel("Voice sync")
        .accessibilityValue(on ? "On" : "Off")
        .accessibilityAddTraits(.isToggle)
    }
```

Also change the ring's ticker from `active: model.isPlaying` to `active: model.isAnimating`.

- [ ] **Step 7: Build, full suite, commit**

Run: `xcodebuild -scheme Atelier -configuration Debug build 2>&1 | tail -20 && xcodebuild test -scheme Atelier -destination 'platform=macOS' 2>&1 | tail -15`
Expected: build succeeds, 278 tests pass (277 + 1). Then:

`git add Atelier AtelierTests && git commit -m "feat(teleprompter): voice-sync top-bar control and Settings toggle (stage 4, task 4)" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"`

Manual check for Alicia (Review Focus 6): open the Teleprompter tab in Settings > Top bar; reorder so three controls share one side and see if the notch flank overflows. If it does, tighten `normalized` so each side holds at most two controls (2 | 2) and say so in the commit.

---

### Task 5: Microphone + Speech permissions (build-verified, manual)

**Files:**
- Create: `Atelier/System/MicrophonePermission.swift`
- Create: `Atelier/System/SpeechPermission.swift`
- Modify: `Atelier/Settings/Panes/PermissionsPane.swift`
- Modify: `Atelier/Info.plist`

**Interfaces:**
- Produces (used by Task 6): `MicrophonePermission.status: AVAuthorizationStatus`, `requestAccess() async -> Bool`, `openSystemSettings()`; `SpeechPermission.status: SFSpeechRecognizerAuthorizationStatus`, `requestAccess() async -> Bool`, `openSystemSettings()`.

- [ ] **Step 1: Create the two helpers** (same thin shape as `CameraPermission`)

`Atelier/System/MicrophonePermission.swift`:

```swift
import AppKit
import AVFoundation

/// Microphone TCC helper, same shape as `CameraPermission`: a live status
/// read (never cached) plus a deep link to the right pane.
enum MicrophonePermission {
    static var status: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .audio)
    }

    static func requestAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    static func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") else { return }
        NSWorkspace.shared.open(url)
    }
}
```

`Atelier/System/SpeechPermission.swift` (`nonisolated`: the system calls the completion on an arbitrary queue, and under default MainActor isolation a MainActor-inferred closure would trap):

```swift
import AppKit
import Speech

/// Speech Recognition TCC helper for the teleprompter's voice sync.
nonisolated enum SpeechPermission {
    static var status: SFSpeechRecognizerAuthorizationStatus {
        SFSpeechRecognizer.authorizationStatus()
    }

    static func requestAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    @MainActor
    static func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition") else { return }
        NSWorkspace.shared.open(url)
    }
}
```

- [ ] **Step 2: Info.plist**

Add next to the other usage strings in `Atelier/Info.plist` (leave `NSAudioCaptureUsageDescription` untouched):

```xml
	<key>NSMicrophoneUsageDescription</key>
	<string>Atelier listens through the microphone so the teleprompter can follow your voice. Audio is only captured while voice sync is listening, is processed on this Mac, and is never recorded or saved.</string>
	<key>NSSpeechRecognitionUsageDescription</key>
	<string>Atelier uses on-device speech recognition to work out where you are in your script. Nothing is sent to Apple or anyone else.</string>
```

- [ ] **Step 3: Permissions pane**

In `PermissionsPane.swift`:
- `PermissionSnapshot`: add `let microphone: PermissionState` and `let speech: PermissionState`; in `current()` add, after `camera`:

```swift
            microphone: {
                switch MicrophonePermission.status {
                case .authorized: .granted
                case .notDetermined: .notDetermined
                default: .denied
                }
            }(),
            speech: {
                switch SpeechPermission.status {
                case .authorized: .granted
                case .notDetermined: .notDetermined
                default: .denied
                }
            }(),
```

- `needsAnything`: also `|| snapshot.microphone == .notDetermined || snapshot.speech == .notDetermined`.
- After the Camera row add:

```swift
                PermissionRow(
                    title: "Microphone",
                    detail: "Voice sync in the Teleprompter",
                    state: snapshot.microphone,
                    grant: {
                        _ = await MicrophonePermission.requestAccess()
                        snapshot = .current()
                    },
                    openSettings: MicrophonePermission.openSystemSettings
                )
                PermissionRow(
                    title: "Speech Recognition",
                    detail: "Voice sync in the Teleprompter (on-device)",
                    state: snapshot.speech,
                    grant: {
                        _ = await SpeechPermission.requestAccess()
                        snapshot = .current()
                    },
                    openSettings: SpeechPermission.openSystemSettings
                )
```

- `grantAll()`: after the camera line add `if snapshot.microphone == .notDetermined { _ = await MicrophonePermission.requestAccess() }` and `if snapshot.speech == .notDetermined { _ = await SpeechPermission.requestAccess() }`.

- [ ] **Step 4: Build, full suite, commit**

Run: `xcodebuild -scheme Atelier -configuration Debug build 2>&1 | tail -20 && xcodebuild test -scheme Atelier -destination 'platform=macOS' 2>&1 | tail -15`
Expected: build succeeds; 278 tests pass. If Swift 6 complains about `SpeechPermission.openSystemSettings` isolation or `requestAuthorization`'s closure, keep the `nonisolated` on the type and fix the specific diagnostic; don't loosen anything else.

`git add Atelier && git commit -m "feat(teleprompter): microphone + speech permissions, Permissions pane rows (stage 4, task 5)" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"`

Manual (Alicia, later, with Task 6): rows show Not Determined / Granted / Denied correctly; Grant All asks for both; deep links open the right pane.

---

### Task 6: `SpeechRecognizer` (real `SpeechWordSource`; manual verification only)

**Files:**
- Create: `Atelier/Teleprompter/SpeechRecognizer.swift`
- Modify: `Atelier/Teleprompter/TeleprompterModel.swift` (`shared` uses the real recognizer)

**Interfaces:**
- Consumes: `SpeechWordSource` (Task 3), `MicrophonePermission`/`SpeechPermission` (Task 5).
- Produces (used by Task 7): `SpeechRecognizer.shared`, `@Published private(set) var level: Float` (0...1, ~15 fps, only while running).

- [ ] **Step 1: Write the recognizer**

Create `Atelier/Teleprompter/SpeechRecognizer.swift`:

```swift
import AVFoundation
import Foundation
import Speech

/// Streaming on-device speech recognition for voice sync. Alive only while the
/// teleprompter is listening (`start`/`stop`), so the microphone indicator and
/// CPU cost track exactly what the user sees. Manual-verification only, like
/// the other `System/*` pieces: it needs a real mic and a TCC grant.
///
/// Threading: the audio tap and the recognition callback run on background
/// queues. Under Swift 6's default MainActor isolation a closure written
/// inside this class would be MainActor-isolated and trap on those queues, so
/// both callbacks are built in `nonisolated` helpers and hop to the main
/// actor explicitly.
@MainActor
final class SpeechRecognizer: ObservableObject, SpeechWordSource {
    static let shared = SpeechRecognizer()

    var onWords: (([String]) -> Void)?
    var onFailure: ((String) -> Void)?
    /// Microphone loudness 0...1 for the "Listening" pill, ~15 fps, while running.
    @Published private(set) var level: Float = 0

    private let engine = AVAudioEngine()
    private let box = RequestBox()
    private var recognizer: SFSpeechRecognizer?
    private var task: SFSpeechRecognitionTask?
    private var running = false
    /// Bumped on every (re)start/stop so a cancelled task's late callback is ignored.
    private var generation = 0
    private var quickFailures = 0
    private var configObserver: NSObjectProtocol?

    // MARK: SpeechWordSource

    func prepare() async -> String? {
        if MicrophonePermission.status == .notDetermined { _ = await MicrophonePermission.requestAccess() }
        guard MicrophonePermission.status == .authorized else {
            return "Microphone access is off. Turn it on in System Settings > Privacy & Security."
        }
        if SpeechPermission.status == .notDetermined { _ = await SpeechPermission.requestAccess() }
        guard SpeechPermission.status == .authorized else {
            return "Speech Recognition is off. Turn it on in System Settings > Privacy & Security."
        }
        guard let recognizer = SFSpeechRecognizer(locale: .current), recognizer.isAvailable else {
            return "Speech recognition isn't available for your language right now."
        }
        // On-device only: never send the user's voice to a server.
        guard recognizer.supportsOnDeviceRecognition else {
            return "Your language has no on-device speech model, so voice sync stays off to keep your voice private."
        }
        self.recognizer = recognizer
        return nil
    }

    func start() {
        guard !running, let recognizer else { return }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            fail("No microphone was found.")
            return
        }
        running = true
        quickFailures = 0
        beginTask(recognizer)
        input.installTap(onBus: 0, bufferSize: 1024, format: format, block: Self.makeTap(box: box) { [weak self] level in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.level = level } }
        })
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            // The audio route changed (AirPods connected, device unplugged):
            // the engine has stopped. Say so instead of leaving a dead mic.
            MainActor.assumeIsolated { self?.fail("The audio device changed, so voice sync stopped.") }
        }
        do {
            engine.prepare()
            try engine.start()
        } catch {
            fail("The microphone couldn't start: \(error.localizedDescription)")
        }
    }

    func stop() {
        guard running else { return }
        running = false
        generation += 1
        task?.cancel()
        task = nil
        box.set(nil)
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
        configObserver = nil
        level = 0
    }

    // MARK: Recognition task

    private func beginTask(_ recognizer: SFSpeechRecognizer) {
        generation += 1
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        request.taskHint = .dictation
        box.set(request)
        let current = generation
        task = Self.makeTask(recognizer: recognizer, request: request) { [weak self] words, isFinal, failed in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.handle(words: words, isFinal: isFinal, failed: failed, generation: current) }
            }
        }
    }

    private func handle(words: [String]?, isFinal: Bool, failed: Bool, generation gen: Int) {
        guard running, gen == generation else { return }
        if let words, !words.isEmpty {
            quickFailures = 0
            onWords?(words)
        }
        guard isFinal || failed else { return }
        // Recognition tasks end after about a minute, or on a hiccup. Start a
        // fresh request; the matcher's cursor lives in the model, so nothing
        // is lost. Repeated failures with no words in between = give up.
        if failed, words?.isEmpty ?? true { quickFailures += 1 }
        if quickFailures >= 3 {
            fail("Speech recognition stopped working.")
            return
        }
        task?.cancel()
        if let recognizer { beginTask(recognizer) }
    }

    private func fail(_ reason: String) {
        stop()
        onFailure?(reason)
    }

    // MARK: Background-queue helpers (nonisolated on purpose)

    nonisolated private static func makeTap(box: RequestBox, onLevel: @escaping @Sendable (Float) -> Void) -> AVAudioNodeTapBlock {
        var buffers = 0
        return { buffer, _ in
            box.append(buffer)
            buffers += 1
            // ~1024 frames per buffer: every 3rd buffer is roughly 15 per second.
            guard buffers % 3 == 0, let samples = buffer.floatChannelData?[0] else { return }
            let count = Int(buffer.frameLength)
            guard count > 0 else { return }
            var sum: Float = 0
            for i in 0..<count { sum += samples[i] * samples[i] }
            let rms = (sum / Float(count)).squareRoot()
            onLevel(min(1, rms * 8))
        }
    }

    nonisolated private static func makeTask(
        recognizer: SFSpeechRecognizer,
        request: SFSpeechAudioBufferRecognitionRequest,
        deliver: @escaping @Sendable ([String]?, Bool, Bool) -> Void
    ) -> SFSpeechRecognitionTask {
        recognizer.recognitionTask(with: request) { result, error in
            deliver(result?.bestTranscription.segments.map(\.substring), result?.isFinal ?? false, error != nil)
        }
    }
}

/// Hands the current recognition request to the audio thread safely; the tap
/// is installed once per start while requests are swapped on restarts.
private nonisolated final class RequestBox: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?

    func set(_ new: SFSpeechAudioBufferRecognitionRequest?) {
        lock.lock(); defer { lock.unlock() }
        request?.endAudio()
        request = new
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        let current = request
        lock.unlock()
        current?.append(buffer)
    }
}
```

(Swift 6 may object to specific isolation details, for example capturing the non-Sendable `SFSpeechRecognizer` or the `var buffers` counter inside the tap closure. Fix each diagnostic narrowly, keeping the rule: nothing MainActor-isolated runs on the audio or recognition queue. `buffers` being mutated only from the audio thread is safe as written; if the compiler insists, wrap it in a tiny `@unchecked Sendable` counter class.)

- [ ] **Step 2: Use it for the shared model**

In `TeleprompterModel.swift` change `static let shared = TeleprompterModel()` to:

```swift
    static let shared = TeleprompterModel(speech: SpeechRecognizer.shared)
```

- [ ] **Step 3: Build, full suite, commit**

Run: `xcodebuild -scheme Atelier -configuration Debug build 2>&1 | tail -20 && xcodebuild test -scheme Atelier -destination 'platform=macOS' 2>&1 | tail -15`
Expected: build succeeds; 278 tests pass (no new tests; this file is manual-verification only).

`git add Atelier && git commit -m "feat(teleprompter): SpeechRecognizer, on-device streaming voice source (stage 4, task 6)" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"`

- [ ] **Step 4: On-device smoke test (Alicia runs `/build`)**

Ask Alicia to: open Settings > Teleprompter > turn on "Follow my voice" (permission prompts appear), open the notch on the Teleprompter tab, press play, read a few lines aloud. Expected: the script follows, waits when she stops, the orange mic dot appears only while listening and disappears on pause. Ask for a screenshot and any misbehaviour (mishears, lag). Tuning constants if needed: `ScriptMatcher.windowSize/tailLength/minimumScore`, `TeleprompterScroll.voiceCatchUpSeconds`.

---

### Task 7: "Listening" pill, panel footprint, view ticking (manual + UI review)

**Files:**
- Create: `Atelier/UI/TeleprompterListeningPill.swift`
- Modify: `Atelier/UI/NotchLayout.swift` (pill height constant)
- Modify: `Atelier/Notch/NotchController.swift` (max footprint includes the pill)
- Modify: `Atelier/UI/NotchRootView.swift` (place the pill)
- Modify: `Atelier/UI/TeleprompterPageView.swift` (tick only while animating)

**Interfaces:**
- Consumes: `SpeechRecognizer.shared.level`, `TeleprompterModel.voiceSyncEnabled/isPlaying/isAnimating`.

- [ ] **Step 1: Layout constant and panel footprint**

In `NotchLayout.swift`, next to `teleprompterHeight`:

```swift
    /// The "Listening" pill hangs this far below the teleprompter page. The
    /// panel is always the maximum footprint (Invariant 3), so it includes it.
    static let teleprompterPillHeight: CGFloat = 20
```

In `NotchController.swift` change the max height to:

```swift
        let maxHeight = max(expandedSize.height, calendarSize.height, teleprompterSize.height + NotchLayout.teleprompterPillHeight)
```

- [ ] **Step 2: The pill**

Create `Atelier/UI/TeleprompterListeningPill.swift`:

```swift
import SwiftUI

/// Small black pill hanging below the teleprompter while voice sync is
/// listening: a live waveform plus a mono "Listening" label (CueNotch look).
/// It exists only while listening, so its level updates cost nothing otherwise.
struct TeleprompterListeningPill: View {
    @ObservedObject var speech: SpeechRecognizer
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let barWeights: [CGFloat] = [0.5, 0.8, 1.0, 0.7, 0.45]

    var body: some View {
        HStack(spacing: 7) {
            HStack(spacing: 2) {
                ForEach(Self.barWeights.indices, id: \.self) { index in
                    Capsule()
                        .fill(.white.opacity(0.85))
                        .frame(width: 2, height: barHeight(Self.barWeights[index]))
                }
            }
            .frame(height: 12)
            Text("Listening")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.8))
        }
        .padding(.horizontal, 14)
        .frame(height: NotchLayout.teleprompterPillHeight)
        .background(
            UnevenRoundedRectangle(bottomLeadingRadius: 10, bottomTrailingRadius: 10)
                .fill(.black)
        )
        .animation(reduceMotion ? nil : .linear(duration: 0.08), value: speech.level)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Listening for your voice")
    }

    /// Reduce Motion: a fixed, calm shape instead of a live waveform.
    private func barHeight(_ weight: CGFloat) -> CGFloat {
        if reduceMotion { return 4 + 4 * weight }
        return 3 + 9 * weight * CGFloat(speech.level)
    }
}
```

- [ ] **Step 3: Place it and stop idle ticking**

In `NotchRootView.swift`, read the teleprompter branch around lines 255-330 (the `TeleprompterPageView` and `TeleprompterControlStrip` sit inside the notch shape container). Add the pill as an overlay on the container **outside the notch shape's clip**, so it can sit below the shape:

```swift
            .overlay(alignment: .bottom) {
                if AtelierSettings.teleprompterEnabled, viewModel.currentPage == .teleprompter,
                   viewModel.state == .expanded, teleprompter.voiceSyncEnabled, teleprompter.isPlaying {
                    TeleprompterListeningPill(speech: .shared)
                        .offset(y: NotchLayout.teleprompterPillHeight)
                        .transition(.opacity)
                        .allowsHitTesting(false)   // Invariant 4
                }
            }
```

This step needs on-device iteration: if the pill is clipped by `NotchShape`, move the overlay one level outward; if the panel's max height clips it, re-check Step 1. Also check the "soft inner corners" join with the panel edge and adjust corner radii to taste.

In `TeleprompterPageView.swift` change `TeleprompterTicker(interval: tick, active: model.isPlaying)` to `active: model.isAnimating`, so a still (waiting) script costs nothing, and update the doc comment ("Redraws ... while playing") to say "while playing or gliding to the spoken position".

- [ ] **Step 4: Build, full suite, run the UI review**

Run: `xcodebuild -scheme Atelier -configuration Debug build 2>&1 | tail -20 && xcodebuild test -scheme Atelier -destination 'platform=macOS' 2>&1 | tail -15`
Expected: build succeeds; 278 tests pass.

Then invoke the `ui-review-tahoe` skill (project rule: proactively after UI work) over the changed UI files, and fix what it finds in one pass (VoiceOver labels, `.help()`, Reduce Motion, press feedback, depth).

- [ ] **Step 5: Commit, then ask Alicia for on-device checks**

`git add Atelier && git commit -m "feat(teleprompter): Listening pill, footprint, tick only while gliding (stage 4, task 7)" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"`

Ask Alicia (via `/build`) for screenshots of every state: voice off, voice on + listening (pill visible, panel not clipped), paused (pill gone), permission denied (mic.slash + tooltip, Settings note), and the other tabs (regression check). Also ask her to check Activity Monitor: CPU ~0% while paused and while waiting between sentences, and the macOS mic indicator off when paused.

---

### Task 8: Docs, ADR, and phase completion

**Files:**
- Create: `docs/decisions/0020-teleprompter-voice-sync.md`
- Modify: `STAGES.md`, `README.md`, `docs/ROADMAP.md` (Phase 17), `FEATURES.md` if it lists voice sync, `CLAUDE.md` (Teleprompter row in the architecture table)

- [ ] **Step 1: ADR 0020** (use the `recording-architecture-decisions` skill for the format matching 0019). Record: voice is the only position source and WPM becomes glide speed (rejected: clock + voice nudging, two sources of truth); forward-only windowed matcher (rejected: global search, teleport risk); on-device only, no server fallback (privacy over locale coverage); pointer-leave no-op in voice mode; permissions requested on first enable.

- [ ] **Step 2: Update the docs.** `STAGES.md`: tick stage 4 with the test count and note that the on-device checks below were done. `README.md`: what voice sync does, the two new permissions, how to turn it on. `docs/ROADMAP.md` Phase 17: tick voice sync. `CLAUDE.md`: add `ScriptMatcher` (pure, unit-tested) to the Teleprompter pure list and `SpeechRecognizer`/`SpeechWordSource`/`System/{Microphone,Speech}Permission` and the pill to the manual-verification list.

- [ ] **Step 3: Run the `phase-completion-checklist` skill**, then confirm the manual verification list from the spec with Alicia: recognition quality on a real script, request-cap restart (read for over 1 minute without pausing), pill height on the notch, permission flows (grant/deny/revoke), VoiceOver on the strip control and pill, Reduce Motion, AirPods connecting mid-read (expect a fallback note, not a dead mic), Activity Monitor CPU, mic indicator off when paused.

- [ ] **Step 4: Final verification and commit**

Run: `xcodebuild test -scheme Atelier -destination 'platform=macOS' 2>&1 | tail -15 && git add -A docs STAGES.md README.md CLAUDE.md FEATURES.md && git commit -m "docs: teleprompter stage 4 voice sync (ADR 0020, STAGES, README, ROADMAP)" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"`
(Drop `FEATURES.md` from the `git add` if it wasn't changed.)

Then dispatch one fresh reviewer over the whole branch (`superpowers:requesting-code-review`). Ask Alicia before pushing; never push or open the PR without her OK (use `/pr` when she says go).
