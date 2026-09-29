# Meeting Join — design

**Status:** approved 2026-09-29 (updated same day for hover-to-peek).
**Roadmap:** first item in the ROADMAP Backlog's "Next-features queue".
**Reference:** [leits/MeetingBar](https://github.com/leits/MeetingBar) (Apache-2.0) — pull real source for link-detection patterns before implementing (`check-reference-apps-first`); adapt with credit.

## Goal

Two minutes before a calendar event that has a video-call link, the notch
peeks once with the event title, a countdown and a **Join** button, then
retracts to a slim pill that stays until 5 minutes after the start.
Solves: fumbling for the link and joining late.

## Decisions (settled with Alicia)

- **Opt-in**, off by default: a "Meeting Join" toggle in Settings → Widgets.
  Turning it on requests Calendar access (existing `CalendarPermission`) and
  starts watching. Nothing runs, and no prompt appears, while it is off.
- **Lead time:** peek at 2 minutes before start (fixed for now).
- **Button only** — never auto-opens a link.
- **Join stays reachable via hover (decided 2026-09-29):** the initial peek
  keeps the normal 2.5 s length, then the countdown lives in the slim pill.
  Hovering the pill brings the compact peek (with Join) back and holds it
  while the pointer is over it. Rejected: a long-lived peek (covers the menu
  bar for minutes) and click-the-pill-to-join (tiny target, easy to
  mis-click into a call). Tradeoff accepted: while a meeting pill is up,
  hovering shows Join instead of opening the now-playing player.
- **Approach:** a separate `MeetingSource` (`LiveActivitySource`) with its own
  `EKEventStore`, independent of `CalendarSource`'s lazy tab lifecycle.
  Rejected: extending `CalendarSource` — it is built around "the week on
  screen" and would couple Meeting Join to the Calendar tab.

## Components

**Pure, unit-tested (Foundation only, no AppKit/EventKit — mirrors Invariant 1):**

- `MeetingLinkParser` — input: an event's `url`, `location`, `notes`;
  output: a join `URL?`. Recognizes Zoom, Google Meet, Teams, Webex.
  **Only `https` URLs whose host equals a known provider domain or is a
  subdomain of one** are accepted (`zoom.us.evil.com` must not match).
  Event notes can contain links from any inviter, so unknown hosts get no Join.
  Precedence: `url` field, then `location`, then `notes`; first match wins.
- `MeetingSchedule` — input: `[MeetingCandidate]` (id, title, start, end,
  link, isAllDay, isCancelled, isDeclined) and `now`; output: the next
  joinable meeting and its phase: `upcoming` (before -2 min), `imminent`
  (-2 min to start), `started` (start to +5 min), else none. Also returns the
  next `Date` at which the phase will change (used to arm the timer).
  Ignores all-day, cancelled, declined and link-less events. Overlaps: the
  nearest start wins; a joined/dismissed/expired meeting yields to the next.

**Side-effecting, manual-verification only (like `System/*.swift`):**

- `MeetingSource: LiveActivitySource` (`Widgets/Meeting/`) — loads the next
  few hours of events from its own `EKEventStore`, respecting
  `AtelierSettings.hiddenCalendarIDs`; maps `EKEvent` to `MeetingCandidate`
  (adding declined/cancelled status, which `CalendarEventItem` lacks); asks
  `MeetingSchedule` for the phase; arms **one timer** for the next phase
  change. Re-arms on `.EKEventStoreChanged`, system wake, and
  `NSSystemClockDidChange`. No polling. Publishes `LiveActivityContent?`.
  Gets a new slot in `NotchLiveActivityPriority` (value chosen at plan time
  after reading the existing ranking).
- `MeetingActivityContent` (`Widgets/Meeting/`) — the `LiveActivityContent`:
  pill (video glyph + countdown) and compact peek (title, countdown, Join).
  Countdown is `Text(timerInterval:)` over a fixed range, so nothing of ours
  ticks. Join opens the URL via `NSWorkspace` and hides that occurrence
  (in-memory). No dismiss button — the peek self-retracts and the pill is
  slim.
- **Hover-to-peek wiring** (touches core hover code, so verify on-device):
  new `LiveActivityContent.hoversToPeek` flag (default false); new pure
  `NotchEvent.hoverPeekStarted` (collapsed/pill → peeking, else unchanged;
  unit-tested); `NotchRootView`'s hover guard lets `hoversToPeek` content
  through and sends `.hoverPeekStarted` instead of `.hoverStarted`;
  `hoversToPeek` content is excluded from `transientHUD` (otherwise hover-out
  would be skipped while it's on top); `NotchController`'s peek-decay task
  skips retracting while the pointer is inside for such content
  (`NotchViewModel.pointerInside`).
- Settings → Widgets toggle; when access is denied the toggle stays off and
  shows a hint linking to the Permissions pane.

## Behaviour

| Time | Notch |
|---|---|
| before -2 min | nothing |
| at -2 min | peeks once (title, countdown, Join) for 2.5 s, then retracts to a pill |
| -2 min to +5 min | slim pill with countdown / "Started"; hover it -> compact peek with Join, held while hovered |
| after +5 min, or after Join | pill removed; next meeting takes over |

## Accessibility and feel

VoiceOver: one combined label ("Standup starts in 2 minutes, Join"), Join
has `.help()` and press feedback, peek honours Reduce Motion via
`NotchAnimations`. Tokens go in `NotchLayout`/`NotchAnimations`, not inline.
Run `ui-review-tahoe` after the UI is built.

## Performance

Idle cost is one armed timer and an `EKEventStoreChanged` observer; zero
when the toggle is off. Countdown ticking only while the pill/peek is visible.

## Testing

- **Unit:** `MeetingLinkParser` (each provider's URL shapes, lookalike hosts,
  multiple links in notes, precedence, non-https rejected) and
  `MeetingSchedule` (phase boundaries at exactly -2 min/start/+5 min,
  overlaps, declined/cancelled/all-day/link-less, next-change date).
- **Manual, on-device (stated plainly, no coverage claimed):** permission
  flow, peek/pill appearance, Join opening the link, moved/deleted event
  re-arming, sleep/wake re-arm. Use a test calendar event a few minutes out.

## Out of scope

Configurable lead time, snooze, dismiss button, auto-join, non-video (in-person) events,
Reminders. Add via ROADMAP if wanted.
