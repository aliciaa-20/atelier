# Meeting Join Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Two minutes before a calendar event with a video-call link, the notch peeks with a Join button, then shows a countdown pill (hover it to get the Join peek back) until 5 minutes after the start.

**Architecture:** Two pure, unit-tested types (`MeetingLinkParser`, `MeetingSchedule`) decide *which link* and *which meeting/phase*. A new `MeetingSource: LiveActivitySource` owns its own `EKEventStore`, arms one timer for the next phase boundary, and publishes a `MeetingActivityContent`. A small, pure state-machine addition (`hoverPeekStarted`) plus a `hoversToPeek` content flag make the pill hover-to-peek.

**Tech Stack:** Swift 6 (strict concurrency, default MainActor isolation), SwiftUI, EventKit, Swift Testing (`import Testing`). No third-party dependencies.

**Spec:** `docs/superpowers/specs/2026-09-29-meeting-join-design.md` (read it first). Reference for link patterns: `leits/MeetingBar` (Apache-2.0) via `gh api` — adapt with credit, don't copy.

## Global Constraints

- Swift 6, strict concurrency. SwiftUI first, AppKit where SwiftUI can't reach. (`CLAUDE.md`)
- No third-party dependencies. (`CLAUDE.md`)
- `NotchState.swift` and the new pure types import **only Foundation/CoreGraphics** — no AppKit/EventKit. (Invariant 1)
- Never run or prompt anything while the Meeting Join toggle is off (zero idle cost). Opt-in, **off by default**.
- Join opens **only `https` URLs whose host is a known provider domain or a subdomain of one** (`zoom.us.evil.com` must not match).
- Lead time is 2 minutes; grace after start is 5 minutes; initial peek uses the normal 2.5 s peek length.
- New tokens (sizes, springs) go in `UI/NotchLayout.swift` / `UI/NotchAnimations.swift`, not inline.
- Icon-only controls get `.help()`; anything bouncy honours Reduce Motion (`NotchAnimations` reads it live).
- Build: `xcodebuild -scheme Atelier -configuration Debug build`. Tests: `xcodebuild test -scheme Atelier -destination 'platform=macOS'`. Single suite: add `-only-testing:AtelierTests/<SuiteName>`.
- New files under `Atelier/` and `AtelierTests/` are picked up by the project's file-system-synchronized groups; confirm with the first build and, if a file is missing from the target, add it to the Xcode project.
- Commit messages end with `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`. Never commit to `main`; never push without asking.

## Review Focus

Failure modes the spec implies but the main tests wouldn't otherwise pin (each has a test or a manual check in the owning task):

1. **Recurring events:** all occurrences share one `eventIdentifier`. Joining today's standup must not hide tomorrow's. → occurrence-id test (Task 2).
2. **Non-provider `url` must not shadow a good link in notes** (e.g. `url` = a company wiki page, notes contain the Zoom link). → parser test (Task 1).
3. **Two meetings starting at the same instant** pick deterministically, not by array order. → schedule test (Task 2).
4. **Hover-out must retract during the `imminent` phase** (the existing `transientHUD` path returns early on hover-exit and would leave the peek stuck), and the initial peek's decay timer must not retract under a hovering pointer. → manual checklist (Task 6).
5. **Calendar access revoked while enabled** must clear the pill, not leave a stale Join. → `MeetingSource.reload()` guard + manual check (Task 5/6).

---

### Task 1: `MeetingLinkParser` (pure)

**Files:**
- Create: `Atelier/Widgets/Meeting/MeetingLinkParser.swift`
- Test: `AtelierTests/MeetingLinkParserTests.swift`

**Interfaces:**
- Produces: `MeetingLinkParser.joinURL(url: URL?, location: String?, notes: String?) -> URL?` and `MeetingLinkParser.accept(_ url: URL) -> URL?`

- [ ] **Step 1: Create the branch**

```bash
cd /Users/aliciapereira/Downloads/dev-macos/atelier
git checkout -b feat/meeting-join   # from docs/roadmap-next-features, which carries the spec + plan commits
```

- [ ] **Step 2: Write the failing tests** — `AtelierTests/MeetingLinkParserTests.swift`

```swift
import Foundation
import Testing
@testable import Atelier

struct MeetingLinkParserTests {
    private func url(_ s: String) -> URL { URL(string: s)! }

    @Test func acceptsProviderLinkInURLField() {
        let u = url("https://us02web.zoom.us/j/123456789?pwd=abc")
        #expect(MeetingLinkParser.joinURL(url: u, location: nil, notes: nil) == u)
    }

    @Test func recognisesEachProvider() {
        for s in [
            "https://zoom.us/j/1",
            "https://meet.google.com/abc-defg-hij",
            "https://teams.microsoft.com/l/meetup-join/xyz",
            "https://teams.live.com/meet/9876",
            "https://acme.webex.com/meet/room",
        ] {
            #expect(MeetingLinkParser.accept(url(s)) != nil, "should accept \(s)")
        }
    }

    @Test func rejectsLookalikeHosts() {
        #expect(MeetingLinkParser.accept(url("https://zoom.us.evil.com/j/1")) == nil)
        #expect(MeetingLinkParser.accept(url("https://evilzoom.us/j/1")) == nil)
        #expect(MeetingLinkParser.accept(url("https://meet.google.com.evil.io/x")) == nil)
    }

    @Test func rejectsNonHTTPS() {
        #expect(MeetingLinkParser.accept(url("http://zoom.us/j/1")) == nil)
        #expect(MeetingLinkParser.accept(url("zoommtg://zoom.us/join?confno=1")) == nil)
    }

    @Test func hostMatchIsCaseInsensitive() {
        #expect(MeetingLinkParser.accept(url("https://ZOOM.US/j/1")) != nil)
    }

    @Test func precedenceIsURLThenLocationThenNotes() {
        let fromURL = url("https://zoom.us/j/1")
        let result = MeetingLinkParser.joinURL(
            url: fromURL,
            location: "https://meet.google.com/aaa-bbbb-ccc",
            notes: "https://acme.webex.com/meet/room")
        #expect(result == fromURL)

        let fromLocation = MeetingLinkParser.joinURL(
            url: nil,
            location: "https://meet.google.com/aaa-bbbb-ccc",
            notes: "https://acme.webex.com/meet/room")
        #expect(fromLocation == url("https://meet.google.com/aaa-bbbb-ccc"))
    }

    // Review Focus 2: a non-provider url must fall through, not block.
    @Test func nonProviderURLFallsThroughToNotes() {
        let result = MeetingLinkParser.joinURL(
            url: url("https://wiki.example.com/standup"),
            location: nil,
            notes: "Agenda: https://wiki.example.com/a\nJoin: https://zoom.us/j/555")
        #expect(result == url("https://zoom.us/j/555"))
    }

    @Test func picksFirstProviderLinkAmongManyInNotes() {
        let notes = "Doc https://docs.google.com/d/1 then https://teams.microsoft.com/l/meetup-join/a and https://zoom.us/j/2"
        #expect(MeetingLinkParser.joinURL(url: nil, location: nil, notes: notes)
            == url("https://teams.microsoft.com/l/meetup-join/a"))
    }

    @Test func returnsNilWhenNoProviderLink() {
        #expect(MeetingLinkParser.joinURL(url: nil, location: "Room 4B", notes: "see https://example.com") == nil)
        #expect(MeetingLinkParser.joinURL(url: nil, location: nil, notes: nil) == nil)
    }
}
```

- [ ] **Step 3: Run to verify it fails**

Run: `xcodebuild test -scheme Atelier -destination 'platform=macOS' -only-testing:AtelierTests/MeetingLinkParserTests`
Expected: FAIL to compile — `cannot find 'MeetingLinkParser' in scope`.

- [ ] **Step 4: Implement** — `Atelier/Widgets/Meeting/MeetingLinkParser.swift`

```swift
import Foundation

/// Finds a video-call join link in a calendar event's fields -- Foundation
/// only, like `CalendarMath`, so it's testable without EventKit.
///
/// Event notes can contain links from anyone who invited you, so a link is
/// only accepted when it is `https` and its host is a known provider domain
/// or a subdomain of one. `zoom.us.evil.com` and `evilzoom.us` both fail.
/// Provider set informed by leits/MeetingBar's link regexes (Apache-2.0).
enum MeetingLinkParser {
    static let providerDomains = [
        "zoom.us", "zoomgov.com",
        "meet.google.com",
        "teams.microsoft.com", "teams.live.com",
        "webex.com",
    ]

    /// Precedence: the event's `url`, then `location`, then `notes`. The first
    /// *accepted* link wins, so a non-provider `url` falls through.
    static func joinURL(url: URL?, location: String?, notes: String?) -> URL? {
        if let url, let accepted = accept(url) { return accepted }
        for text in [location, notes] {
            if let text, let found = firstAcceptedLink(in: text) { return found }
        }
        return nil
    }

    static func accept(_ url: URL) -> URL? {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else { return nil }
        for domain in providerDomains where host == domain || host.hasSuffix("." + domain) {
            return url
        }
        return nil
    }

    private static let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    private static func firstAcceptedLink(in text: String) -> URL? {
        let range = NSRange(text.startIndex..., in: text)
        for match in detector?.matches(in: text, range: range) ?? [] {
            if let url = match.url, let accepted = accept(url) { return accepted }
        }
        return nil
    }
}
```

- [ ] **Step 5: Run to verify it passes**

Run: same `-only-testing` command. Expected: PASS (all 9 tests). Confirms the new files are in the synchronized groups; if "cannot find" persists, add the files to the Xcode targets.

- [ ] **Step 6: Commit**

```bash
git add Atelier/Widgets/Meeting/MeetingLinkParser.swift AtelierTests/MeetingLinkParserTests.swift
git commit -m "Meeting Join: MeetingLinkParser (https + provider-host allowlist)

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 2: `MeetingSchedule` (pure)

**Files:**
- Create: `Atelier/Widgets/Meeting/MeetingSchedule.swift`
- Test: `AtelierTests/MeetingScheduleTests.swift`

**Interfaces:**
- Produces:
  - `struct MeetingCandidate: Equatable { id, title, start, end, joinURL: URL?, isAllDay, isCancelled, isDeclined }` and `static func occurrenceID(eventID: String, start: Date) -> String`
  - `enum MeetingPhase: Equatable { case imminent, started }`
  - `struct MeetingSnapshot: Equatable { meeting: MeetingCandidate, phase: MeetingPhase }`
  - `MeetingSchedule.leadTime` (120 s), `.graceAfterStart` (300 s), `.current(candidates:now:excluding:) -> MeetingSnapshot?`, `.nextChange(candidates:now:excluding:) -> Date?`

- [ ] **Step 1: Write the failing tests** — `AtelierTests/MeetingScheduleTests.swift`

```swift
import Foundation
import Testing
@testable import Atelier

struct MeetingScheduleTests {
    private let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)
    private let link = URL(string: "https://zoom.us/j/1")!

    private func meeting(
        _ id: String = "a", startOffset: TimeInterval = 600, link: URL? = URL(string: "https://zoom.us/j/1"),
        allDay: Bool = false, cancelled: Bool = false, declined: Bool = false
    ) -> MeetingCandidate {
        MeetingCandidate(
            id: id, title: "Standup", start: t0.addingTimeInterval(startOffset),
            end: t0.addingTimeInterval(startOffset + 1800), joinURL: link,
            isAllDay: allDay, isCancelled: cancelled, isDeclined: declined)
    }

    private func phase(_ c: [MeetingCandidate], at offset: TimeInterval, excluding: Set<String> = []) -> MeetingSnapshot? {
        MeetingSchedule.current(candidates: c, now: t0.addingTimeInterval(offset), excluding: excluding)
    }

    @Test func nothingBeforeTheLeadWindow() {
        // start at +600; window opens at +480
        #expect(phase([meeting()], at: 479) == nil)
    }

    @Test func imminentFromExactlyTwoMinutesBefore() {
        #expect(phase([meeting()], at: 480)?.phase == .imminent)
        #expect(phase([meeting()], at: 599)?.phase == .imminent)
    }

    @Test func startedFromTheStartUntilFiveMinutesAfter() {
        #expect(phase([meeting()], at: 600)?.phase == .started)
        #expect(phase([meeting()], at: 899)?.phase == .started)
    }

    @Test func expiredFiveMinutesAfterStart() {
        #expect(phase([meeting()], at: 900) == nil)
    }

    @Test func ignoresAllDayCancelledDeclinedAndLinkless() {
        let bad = [
            meeting("d", allDay: true), meeting("c", cancelled: true),
            meeting("x", declined: true), meeting("n", link: nil),
        ]
        #expect(phase(bad, at: 500) == nil)
    }

    @Test func overlapPicksNearestStart() {
        // now = +500: "old" started 180 s ago (still in grace), "soon" starts in 60 s.
        let old = meeting("old", startOffset: 320)   // started 180 s before now
        let soon = meeting("soon", startOffset: 560) // starts in 60 s
        #expect(phase([old, soon], at: 500)?.meeting.id == "soon")
        #expect(phase([soon, old], at: 500)?.meeting.id == "soon")
    }

    // Review Focus 3: identical start times must not depend on array order.
    @Test func simultaneousStartsAreDeterministic() {
        let a = meeting("a"), b = meeting("b")
        #expect(phase([a, b], at: 500)?.meeting.id == "a")
        #expect(phase([b, a], at: 500)?.meeting.id == "a")
    }

    @Test func excludedMeetingYieldsToTheNext() {
        let first = meeting("first", startOffset: 560)
        let second = meeting("second", startOffset: 600)
        #expect(phase([first, second], at: 500, excluding: ["first"])?.meeting.id == "second")
    }

    // Review Focus 1: recurring occurrences share an event id; the occurrence
    // id must differ so joining one doesn't hide the next.
    @Test func occurrenceIDsDifferPerStart() {
        let d1 = Date(timeIntervalSinceReferenceDate: 100)
        let d2 = Date(timeIntervalSinceReferenceDate: 100 + 86_400)
        #expect(MeetingCandidate.occurrenceID(eventID: "E", start: d1)
            != MeetingCandidate.occurrenceID(eventID: "E", start: d2))
    }

    @Test func nextChangeIsTheEarliestFutureBoundary() {
        let c = [meeting(startOffset: 600)] // boundaries: 480, 600, 900
        func next(_ now: TimeInterval) -> TimeInterval? {
            MeetingSchedule.nextChange(candidates: c, now: t0.addingTimeInterval(now), excluding: [])
                .map { $0.timeIntervalSince(t0) }
        }
        #expect(next(0) == 480)
        #expect(next(480) == 600)   // strictly after now
        #expect(next(600) == 900)
        #expect(next(900) == nil)
    }

    @Test func nextChangeIgnoresIneligibleMeetings() {
        #expect(MeetingSchedule.nextChange(candidates: [meeting(declined: true)], now: t0, excluding: []) == nil)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `xcodebuild test -scheme Atelier -destination 'platform=macOS' -only-testing:AtelierTests/MeetingScheduleTests`
Expected: FAIL to compile — `cannot find 'MeetingCandidate' in scope`.

- [ ] **Step 3: Implement** — `Atelier/Widgets/Meeting/MeetingSchedule.swift`

```swift
import Foundation

/// One calendar event as Meeting Join needs it -- a plain value so this file
/// (and its tests) never touch `EKEvent`. Foundation only, like `CalendarMath`.
struct MeetingCandidate: Equatable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let joinURL: URL?
    let isAllDay: Bool
    let isCancelled: Bool
    let isDeclined: Bool

    /// Recurring events share one `eventIdentifier` across occurrences, so
    /// the start date is part of the identity -- joining today's standup must
    /// not hide tomorrow's.
    static func occurrenceID(eventID: String, start: Date) -> String {
        "\(eventID)|\(Int(start.timeIntervalSinceReferenceDate))"
    }
}

enum MeetingPhase: Equatable {
    /// Within `leadTime` before the start.
    case imminent
    /// From the start until `graceAfterStart` later.
    case started
}

struct MeetingSnapshot: Equatable {
    let meeting: MeetingCandidate
    let phase: MeetingPhase
}

/// Decides which meeting (if any) the notch should be offering to join, and
/// when that answer will next change -- so the source can arm one timer
/// instead of polling.
enum MeetingSchedule {
    static let leadTime: TimeInterval = 120
    static let graceAfterStart: TimeInterval = 300

    /// Ignores all-day, cancelled, declined, link-less and `excluding` events.
    /// If several are in their window, the one whose start is nearest `now`
    /// wins; ties break by `id` so the result never depends on array order.
    static func current(candidates: [MeetingCandidate], now: Date, excluding: Set<String>) -> MeetingSnapshot? {
        let inWindow = eligible(candidates, excluding: excluding).filter {
            now >= $0.start.addingTimeInterval(-leadTime) && now < $0.start.addingTimeInterval(graceAfterStart)
        }
        guard let pick = inWindow.min(by: { lhs, rhs in
            let l = abs(lhs.start.timeIntervalSince(now)), r = abs(rhs.start.timeIntervalSince(now))
            return l != r ? l < r : lhs.id < rhs.id
        }) else { return nil }
        return MeetingSnapshot(meeting: pick, phase: now < pick.start ? .imminent : .started)
    }

    /// The earliest boundary strictly after `now` across all eligible meetings.
    static func nextChange(candidates: [MeetingCandidate], now: Date, excluding: Set<String>) -> Date? {
        eligible(candidates, excluding: excluding)
            .flatMap { [$0.start.addingTimeInterval(-leadTime), $0.start, $0.start.addingTimeInterval(graceAfterStart)] }
            .filter { $0 > now }
            .min()
    }

    private static func eligible(_ candidates: [MeetingCandidate], excluding: Set<String>) -> [MeetingCandidate] {
        candidates.filter {
            $0.joinURL != nil && !$0.isAllDay && !$0.isCancelled && !$0.isDeclined && !excluding.contains($0.id)
        }
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: same `-only-testing:AtelierTests/MeetingScheduleTests`. Expected: PASS (11 tests).

- [ ] **Step 5: Commit**

```bash
git add Atelier/Widgets/Meeting/MeetingSchedule.swift AtelierTests/MeetingScheduleTests.swift
git commit -m "Meeting Join: MeetingSchedule (phase + next-change, pure)

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Hover-to-peek in the pure state machine

**Files:**
- Modify: `Atelier/Notch/NotchState.swift` (add event + reducer case)
- Modify: `Atelier/Notch/LiveActivitySource.swift` (add `hoversToPeek` to `LiveActivityContent` + default)
- Test: `AtelierTests/NotchStateTests.swift` (append)

**Interfaces:**
- Produces: `NotchEvent.hoverPeekStarted`; `LiveActivityContent.hoversToPeek: Bool` (default `false`).

- [ ] **Step 1: Write the failing tests** — append to `AtelierTests/NotchStateTests.swift` (match that file's existing `struct`/`@Test` style; read its first 15 lines first)

```swift
    @Test func hoverPeekStartedPeeksFromRestingStates() {
        #expect(NotchStateMachine.reduce(.pill, on: .hoverPeekStarted) == .peeking)
        #expect(NotchStateMachine.reduce(.collapsed, on: .hoverPeekStarted) == .peeking)
    }

    @Test func hoverPeekStartedDoesNotDisturbActiveStates() {
        #expect(NotchStateMachine.reduce(.expanded, on: .hoverPeekStarted) == .expanded)
        #expect(NotchStateMachine.reduce(.peeking, on: .hoverPeekStarted) == .peeking)
        #expect(NotchStateMachine.reduce(.shelf, on: .hoverPeekStarted) == .shelf)
    }

    @Test func hoverEndedRetractsAHoverPeek() {
        let peeking = NotchStateMachine.reduce(.pill, on: .hoverPeekStarted)
        #expect(NotchStateMachine.reduce(peeking, on: .hoverEnded(isPlaying: true)) == .pill)
    }
```

- [ ] **Step 2: Run to verify it fails**

Run: `xcodebuild test -scheme Atelier -destination 'platform=macOS' -only-testing:AtelierTests/NotchStateTests`
Expected: FAIL to compile — `type 'NotchEvent' has no member 'hoverPeekStarted'`.

- [ ] **Step 3: Implement**

In `Atelier/Notch/NotchState.swift`, add to `enum NotchEvent` after `hoverEnded`:

```swift
    /// Hover over a pill whose content opts in via
    /// `LiveActivityContent.hoversToPeek` (e.g. Meeting Join's countdown):
    /// shows that content's peek instead of the full player. Exit reuses
    /// `.hoverEnded`, which already resolves any state to pill/collapsed.
    case hoverPeekStarted
```

and to `NotchStateMachine.reduce`, after the `.hoverEnded` case:

```swift
        case .hoverPeekStarted:
            switch state {
            case .collapsed, .pill:
                return .peeking
            case .expanded, .peeking, .shelf:
                return state
            }
```

In `Atelier/Notch/LiveActivitySource.swift`, add to `protocol LiveActivityContent` (after `peeksOnChange`):

```swift
    /// Whether hovering the pill while this content is on top should bring
    /// its `peekView()` back (held while hovered) instead of ignoring hover
    /// (non-expandable default) or opening the full player. For content whose
    /// peek has a control the user must be able to reach after the initial
    /// peek decays (Meeting Join's Join button).
    var hoversToPeek: Bool { get }
```

and to the extension: `var hoversToPeek: Bool { false }`.

- [ ] **Step 4: Run to verify it passes, then run the full suite**

Run: `-only-testing:AtelierTests/NotchStateTests` → PASS. Then `xcodebuild test -scheme Atelier -destination 'platform=macOS'` → all green (nothing else conforms differently; the default covers existing content types).

- [ ] **Step 5: Commit**

```bash
git add Atelier/Notch/NotchState.swift Atelier/Notch/LiveActivitySource.swift AtelierTests/NotchStateTests.swift
git commit -m "Notch: hoverPeekStarted event + LiveActivityContent.hoversToPeek

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Setting, priority slot, and Settings toggle

**Files:**
- Modify: `Atelier/AtelierSettings.swift` (key, default, accessor)
- Modify: `Atelier/NowPlaying/NowPlayingLiveActivitySource.swift` (`NotchLiveActivityPriority.meeting`)
- Modify: `Atelier/Settings/Panes/WidgetsPane.swift`

**Interfaces:**
- Produces: `AtelierSettings.meetingJoinEnabledKey`, `AtelierSettings.meetingJoinEnabled: Bool` (default false), `NotchLiveActivityPriority.meeting`.

- [ ] **Step 1: Add the setting.** In `AtelierSettings.swift`: add `static let meetingJoinEnabledKey = "meetingJoinEnabled"` beside `colorPickerEnabledKey`; add `meetingJoinEnabledKey: false,` to the registered-defaults dictionary (beside `colorPickerEnabledKey: true`, with a one-line comment: off by default -- opt-in, nothing runs or prompts until enabled); add the accessor beside `colorPickerEnabled`:

```swift
    /// Opt-in: Meeting Join reads Calendar and arms a timer only while this is
    /// on. Off by default so no Calendar prompt or background work appears
    /// until the user asks for it.
    static var meetingJoinEnabled: Bool {
        UserDefaults.standard.bool(forKey: meetingJoinEnabledKey)
    }
```

- [ ] **Step 2: Add the priority.** In `NotchLiveActivityPriority`, between `colorPicker = 11` and `screenRecording = 15`:

```swift
    /// Above `colorPicker` and `nowPlaying` so the countdown pill isn't hidden
    /// by music for the ~7 minute window, below the volume/brightness HUDs so
    /// a key press still interrupts. Tradeoff: a picked-colour peek is
    /// suppressed while a meeting pill is up.
    static let meeting = 12
```

- [ ] **Step 3: Add the toggle.** In `WidgetsPane.swift` add `@AppStorage(AtelierSettings.meetingJoinEnabledKey) private var meetingJoinEnabled = false` and `@State private var meetingAccessDenied = false`, and a section after "Color Picker":

```swift
            Section("Meeting Join") {
                Toggle("Show a Join button before video calls", isOn: $meetingJoinEnabled)
                    .onChange(of: meetingJoinEnabled) { _, on in
                        guard on else { meetingAccessDenied = false; return }
                        guard CalendarPermission.status != .fullAccess else { return }
                        Task {
                            if await !CalendarPermission.requestAccess() {
                                meetingJoinEnabled = false
                                meetingAccessDenied = true
                            }
                        }
                    }
                if meetingAccessDenied {
                    Text("Calendar access is off, so Meeting Join can't see your events.")
                        .foregroundStyle(.secondary)
                    Button("Open System Settings") { CalendarPermission.openSystemSettings() }
                }
            }
```

- [ ] **Step 4: Build.** Run: `xcodebuild -scheme Atelier -configuration Debug build`. Expected: BUILD SUCCEEDED. (Manual check deferred to Task 6.)

- [ ] **Step 5: Commit**

```bash
git add Atelier/AtelierSettings.swift Atelier/NowPlaying/NowPlayingLiveActivitySource.swift Atelier/Settings/Panes/WidgetsPane.swift
git commit -m "Meeting Join: opt-in setting, priority slot, Widgets toggle

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 5: `MeetingActivityContent` + `MeetingSource`

**Files:**
- Create: `Atelier/Widgets/Meeting/MeetingActivityContent.swift`
- Create: `Atelier/Widgets/Meeting/MeetingSource.swift`

**Interfaces:**
- Consumes: `MeetingCandidate`, `MeetingPhase`, `MeetingSchedule`, `MeetingLinkParser` (Tasks 1-2); `LiveActivityContent.hoversToPeek` (Task 3); `NotchLiveActivityPriority.meeting`, `AtelierSettings.hiddenCalendarIDs`, `CalendarPermission` (existing).
- Produces: `MeetingActivityContent(meeting:phase:notchHeight:onJoin:)`; `MeetingSource(notchHeight:)` with `func setEnabled(_ enabled: Bool)`.

- [ ] **Step 1: Read a sibling for style.** Read `Atelier/Widgets/ColorPicker/ColorPickerActivityContent.swift` (already used as the pattern below) and skim `NotchLayout.swift` for `peekHorizontalPadding` / `peekEdgeGap`.

- [ ] **Step 2: Write `MeetingActivityContent.swift`**

```swift
import SwiftUI

/// Meeting Join's pill + compact peek. The countdown is
/// `Text(timerInterval:)` over a *fixed* range, so nothing of ours ticks and
/// a re-evaluated body can never build an inverted range.
struct MeetingActivityContent: LiveActivityContent {
    let meeting: MeetingCandidate
    let phase: MeetingPhase
    /// Same reasoning as `PeekPlayerView.notchHeight`.
    let notchHeight: CGFloat
    let onJoin: () -> Void

    /// Phase is part of the id: `.imminent` -> `.started` is a content change,
    /// but `peeksOnChange` is false for `.started` so it never re-peeks.
    var id: String { "meeting:\(meeting.id):\(phase)" }
    var peeksOnChange: Bool { phase == .imminent }
    var hoversToPeek: Bool { true }

    private var countdownRange: ClosedRange<Date> {
        meeting.start.addingTimeInterval(-MeetingSchedule.leadTime)...meeting.start
    }

    private var spokenLabel: String {
        switch phase {
        case .imminent: "\(meeting.title), video call starting soon. Join available."
        case .started: "\(meeting.title), video call started. Join available."
        }
    }

    @ViewBuilder private var countdown: some View {
        switch phase {
        case .imminent: Text(timerInterval: countdownRange, countsDown: true, showsHours: false)
        case .started: Text("Started")
        }
    }

    func pillView() -> AnyView {
        AnyView(
            HStack(spacing: 5) {
                Image(systemName: "video.fill").font(.system(size: 9, weight: .semibold))
                countdown
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spokenLabel)
        )
    }

    func peekView() -> AnyView {
        AnyView(
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(meeting.title)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    countdown
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.7))
                }
                Spacer(minLength: 8)
                Button("Join", action: onJoin)
                    .buttonStyle(MeetingJoinButtonStyle())
                    .help("Open the meeting link")
            }
            .foregroundStyle(.white)
            .padding(.horizontal, NotchLayout.peekHorizontalPadding)
            .padding(.bottom, NotchLayout.peekEdgeGap)
            .padding(.top, notchHeight + NotchLayout.peekEdgeGap)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(spokenLabel)
        )
    }
}

/// Capsule button with press feedback (scale via `NotchAnimations.press`).
private struct MeetingJoinButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.green))
            .foregroundStyle(.black)
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(NotchAnimations.press, value: configuration.isPressed)
    }
}
```

- [ ] **Step 3: Write `MeetingSource.swift`**

```swift
import AppKit
import Combine
import EventKit
import Foundation

/// Publishes Meeting Join's pill/peek. Own `EKEventStore` (calendar access is
/// app-wide, so no second prompt) and independent of `CalendarSource`'s lazy
/// tab lifecycle. Lightweight by design (CLAUDE.md): while disabled nothing
/// is observed or scheduled; while enabled it holds ONE timer, armed for the
/// next phase boundary, plus push observers -- no polling. Timer-fire, store
/// changes, wake and clock changes all funnel into `reload()`.
/// Reference: leits/MeetingBar (Apache-2.0) for what event fields carry links.
@MainActor
final class MeetingSource: LiveActivitySource {
    let id = "meeting"
    let priority = NotchLiveActivityPriority.meeting

    private let subject = CurrentValueSubject<LiveActivityContent?, Never>(nil)
    private let notchHeight: CGFloat
    private let store = EKEventStore()
    private var candidates: [MeetingCandidate] = []
    private var joinedIDs: Set<String> = []
    private var timer: Timer?
    private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []
    private(set) var isRunning = false

    var contentPublisher: AnyPublisher<LiveActivityContent?, Never> {
        subject.eraseToAnyPublisher()
    }

    init(notchHeight: CGFloat) {
        self.notchHeight = notchHeight
    }

    /// Idempotent -- `NotchController.applyLiveSettings` calls this on every
    /// UserDefaults change.
    func setEnabled(_ enabled: Bool) {
        guard enabled != isRunning else { return }
        enabled ? start() : stop()
    }

    private func start() {
        // Never prompt from here -- the Settings toggle owns the request. If
        // access isn't granted, stay stopped so a later setEnabled(true) retries.
        guard CalendarPermission.status == .fullAccess else { return }
        isRunning = true
        observe(.EKEventStoreChanged, on: .default, object: store)
        observe(NSWorkspace.didWakeNotification, on: NSWorkspace.shared.notificationCenter)
        observe(.NSSystemClockDidChange, on: .default)
        reload()
    }

    private func stop() {
        isRunning = false
        timer?.invalidate()
        timer = nil
        observers.forEach { $0.center.removeObserver($0.token) }
        observers = []
        candidates = []
        joinedIDs = []
        subject.send(nil)
    }

    private func observe(_ name: Notification.Name, on center: NotificationCenter, object: AnyObject? = nil) {
        let token = center.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
        observers.append((center, token))
    }

    private func reload() {
        guard isRunning else { return }
        // Review Focus 5: access revoked while enabled -> clear, don't go stale.
        guard CalendarPermission.status == .fullAccess else {
            candidates = []
            refresh()
            return
        }
        let now = Date()
        let hidden = AtelierSettings.hiddenCalendarIDs
        let calendars = store.calendars(for: .event).filter { !hidden.contains($0.calendarIdentifier) }
        guard !calendars.isEmpty else {
            candidates = []
            refresh()
            return
        }
        // From "still inside the grace window" to a few hours ahead; the timer
        // re-runs this at least hourly so the horizon never goes stale.
        let predicate = store.predicateForEvents(
            withStart: now.addingTimeInterval(-MeetingSchedule.graceAfterStart),
            end: now.addingTimeInterval(6 * 3600),
            calendars: calendars)
        candidates = store.events(matching: predicate).map { event in
            MeetingCandidate(
                id: MeetingCandidate.occurrenceID(eventID: event.eventIdentifier ?? event.title ?? "?", start: event.startDate),
                title: event.title ?? "Meeting",
                start: event.startDate,
                end: event.endDate,
                joinURL: MeetingLinkParser.joinURL(url: event.url, location: event.location, notes: event.notes),
                isAllDay: event.isAllDay,
                isCancelled: event.status == .canceled,
                isDeclined: event.attendees?.contains { $0.isCurrentUser && $0.participantStatus == .declined } ?? false)
        }
        refresh()
    }

    /// Republish the current answer and re-arm the single timer.
    private func refresh() {
        let now = Date()
        if let snapshot = MeetingSchedule.current(candidates: candidates, now: now, excluding: joinedIDs),
           let url = snapshot.meeting.joinURL {
            subject.send(MeetingActivityContent(
                meeting: snapshot.meeting, phase: snapshot.phase, notchHeight: notchHeight,
                onJoin: { [weak self] in self?.join(snapshot.meeting, url: url) }))
        } else {
            subject.send(nil)
        }
        timer?.invalidate()
        let next = MeetingSchedule.nextChange(candidates: candidates, now: now, excluding: joinedIDs)
        let fire = min(next ?? .distantFuture, now.addingTimeInterval(3600))
        let t = Timer(fire: fire, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
        t.tolerance = 1
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func join(_ meeting: MeetingCandidate, url: URL) {
        NSWorkspace.shared.open(url)
        joinedIDs.insert(meeting.id)
        refresh()
    }
}
```

- [ ] **Step 4: Build.** Run: `xcodebuild -scheme Atelier -configuration Debug build`. Expected: BUILD SUCCEEDED. Fix any Swift 6 isolation diagnostics in `MeetingSource` (the `observers` tuple array and `Timer` closures are the likely spots) without weakening the design.

- [ ] **Step 5: Commit**

```bash
git add Atelier/Widgets/Meeting/MeetingActivityContent.swift Atelier/Widgets/Meeting/MeetingSource.swift
git commit -m "Meeting Join: MeetingSource + MeetingActivityContent

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Wire into the notch (registration + hover) and verify on-device

**Files:**
- Modify: `Atelier/Notch/NotchController.swift`
- Modify: `Atelier/Notch/NotchViewModel.swift`
- Modify: `Atelier/UI/NotchRootView.swift`

**Interfaces:**
- Consumes: `MeetingSource.setEnabled(_:)`, `NotchEvent.hoverPeekStarted`, `LiveActivityContent.hoversToPeek`.
- Produces: `NotchViewModel.pointerInside: Bool` (plain var, not `@Published`).

- [ ] **Step 1: Register the source.** In `NotchController.swift`, mirror every occurrence of `colorPickerSource`: add `private let meetingSource: MeetingSource` beside its declaration (line ~33); construct `let meetingSource = MeetingSource(notchHeight: 0)` in the fallback branch (~line 182) and `MeetingSource(notchHeight: collapsedRect.height)` in the main branch (~line 243), assign `self.meetingSource = meetingSource` where `colorPickerSource` is assigned, and add `meetingSource,` to **both** `LiveActivityCoordinator(sources: [...])` arrays (~lines 196 and 257). Then in `applyLiveSettings()` add:

```swift
        meetingSource.setEnabled(AtelierSettings.meetingJoinEnabled)
```

- [ ] **Step 2: Pointer flag.** In `NotchViewModel.swift` add `var pointerInside = false` (plain stored property, with a one-line comment: set by `NotchRootView`'s hover handler; read by `NotchController`'s peek decay so a hover-peek isn't retracted under the cursor).

- [ ] **Step 3: Hover handler.** In `NotchRootView.swift` at the hover handler (~line 576), set the flag first and let `hoversToPeek` content through:

```swift
                viewModel.pointerInside = hovering
                let hoverPeeks = liveActivity.topContent?.hoversToPeek == true
                guard viewModel.state == .expanded || hoverPeeks || (liveActivity.topContent?.isExpandable ?? true) else { return }

                if hovering {
                    animateStateChange(NotchAnimations.open) {
                        viewModel.handle(hoverPeeks && viewModel.state != .expanded ? .hoverPeekStarted : .hoverStarted)
                    }
                } else {
```

(keep the existing `else` branch unchanged). Then exclude such content from the HUD path (~line 864):

```swift
        guard let content = liveActivity.topContent, !content.isExpandable, content.peeksOnChange, !content.hoversToPeek else { return nil }
```

- [ ] **Step 4: Decay must not retract under the pointer.** In `NotchController.triggerPeek` decay task, right after `guard !Task.isCancelled, let self else { return }`:

```swift
            // A hover-peek (Meeting Join) is held while the pointer is over
            // it; `.hoverEnded` retracts it afterwards.
            if liveActivityCoordinator.topContent?.hoversToPeek == true, viewModel.pointerInside { return }
```

- [ ] **Step 5: Build and run all tests.** `xcodebuild -scheme Atelier -configuration Debug build` then `xcodebuild test -scheme Atelier -destination 'platform=macOS'`. Expected: both green (pre-existing count + 9 + 11 + 3 new).

- [ ] **Step 6: Relaunch (`/build`) and run the manual checklist.** Create a test calendar event ~4 minutes out with `https://zoom.us/j/123` in its URL field. State plainly in the report which of these passed — none of this is unit-tested:
  - [ ] Toggle off by default; turning it on prompts (or, if already granted, no prompt); denying leaves the toggle off with the System Settings hint.
  - [ ] Nothing shows before -2:00.
  - [ ] At -2:00 the notch peeks with title, countdown, Join; retracts after ~2.5 s to the pill with the countdown.
  - [ ] Hover the pill → compact peek returns, stays while hovered; **hover-out retracts to the pill** (Review Focus 4). Also hover *during* the first 2.5 s peek → it must not retract under the cursor, and retracts after you leave.
  - [ ] Clicking Join opens the link and removes the pill.
  - [ ] At the start time the pill switches to "Started" without a new peek; disappears 5 minutes later.
  - [ ] Edit the event's time while enabled → timing follows (store-change re-arm).
  - [ ] Put the Mac to sleep past -2:00 and wake → pill appears (wake re-arm).
  - [ ] Turn the toggle off mid-window → pill vanishes; revoke Calendar access in System Settings → pill clears (Review Focus 5).
  - [ ] Music playing: meeting pill outranks now-playing during the window; volume keys still interrupt.
  - [ ] Long event title truncates cleanly in the peek.

  Ask Alicia for a screenshot of each state (pill, peek, hover-peek), per the project's screenshot-review lesson.

- [ ] **Step 7: Commit**

```bash
git add Atelier/Notch/NotchController.swift Atelier/Notch/NotchViewModel.swift Atelier/UI/NotchRootView.swift
git commit -m "Meeting Join: register source, hover-to-peek wiring

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 7: UI review, ADR, docs

**Files:**
- Create: `docs/decisions/0028-hover-to-peek-live-activity-content.md` (check `ls docs/decisions` first — the unpushed audio-tap branch already holds 0027; pick the next free number)
- Modify: `docs/ROADMAP.md` (mark item 1 of the Next-features queue shipped; add a Phase entry if the roadmap uses one), `CLAUDE.md` (Widgets row: add `Meeting/` — `MeetingLinkParser`/`MeetingSchedule` pure + unit-tested, `MeetingSource` manual-verification; Invariants/lessons only if something new was learned), `README.md` (feature list + Meeting Join setting), `docs/FEATURES.md` (§6 Productivity widgets row)

- [ ] **Step 1: Run `ui-review-tahoe`** on `MeetingActivityContent.swift` (VoiceOver, keyboard/focus, press/hover feedback, depth, Reduce Motion); apply the findings as a small follow-up commit.
- [ ] **Step 2: Write the ADR** (`recording-architecture-decisions` skill): why `hoversToPeek` + `.hoverPeekStarted` instead of a long-lived peek or click-the-pill; the rejected alternatives and the accepted tradeoff (hover shows Join, not the player, while a meeting pill is up); the `transientHUD` exclusion and why (hover-exit would be skipped).
- [ ] **Step 3: Update the docs listed above** with what actually shipped, including the manual-verification statement.
- [ ] **Step 4: Run the `phase-completion-checklist` skill**, then the full test suite one more time.
- [ ] **Step 5: Commit**

```bash
git add docs CLAUDE.md README.md
git commit -m "docs: Meeting Join ADR, ROADMAP/FEATURES/README/CLAUDE.md sync

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

Do **not** push. Before any push run `pre-push-docs-sync` and ask Alicia first.
