# ADR 0028 — Live-activity content can opt in to hover-to-peek (Meeting Join)

- **Status:** Accepted
- **Date:** 2026-09-29

## Context

Meeting Join shows a countdown pill before a video call and needs a **Join
button** the user can still reach after the initial peek (2.5 s,
`NotchController.peekDuration`) has decayed. But hover over a pill whose
content is non-expandable did nothing: `NotchRootView`'s hover guard returns
early unless the content `isExpandable` (that early return is what keeps the
volume/brightness scrub bar draggable). So with the obvious design, Join was
clickable for 2.5 seconds and then unreachable.

## Decision

`LiveActivityContent` gains `hoversToPeek` (default `false`). For content
that sets it, hovering the pill sends a new pure event,
`NotchEvent.hoverPeekStarted` (collapsed/pill -> peeking, everything else
unchanged; unit-tested in `NotchStateTests`), which brings the content's
`peekView()` back. Hover-out reuses `.hoverEnded`, which already resolves any
state to pill/collapsed. Two supporting rules:

- `hoversToPeek` content is **excluded from `transientHUD`**. That path
  returns early on hover-exit ("don't close under the HUD"), which would have
  left a hover-peek stuck open while the content was on top.
- `NotchController`'s peek-decay task skips retracting while
  `NotchViewModel.pointerInside` is true for such content, so the initial peek
  isn't pulled away under a pointer that is already over it. `.hoverEnded`
  retracts it afterwards.

## Alternatives rejected

- **A long-lived peek** (e.g. 90 s): covers the menu bar for minutes.
- **Click the pill to join:** tiny target hugging the notch; easy to
  mis-click into starting a call.

## Consequences

- While a Meeting Join pill is up (about 7 minutes per meeting), hovering
  shows Join instead of opening the now-playing player. Accepted.
- It touches core hover code (`NotchRootView` hover handler), so it is
  manual-verification only beyond the state-machine unit tests.
- The meeting priority (12, above `colorPicker`/`nowPlaying`) suppresses a
  picked-colour peek while a meeting pill is up. Stacked live activities
  (ROADMAP queue #8) is the planned fix for pills competing for one slot.

## Follow-ups from the final review (same day)

- The hover-guard and peek-setting decisions moved into a pure, tested
  `NotchHoverPolicy` (`Notch/`). It also lets *leaving* a peek always retract
  unless a HUD owns it: without that, a hover-peek that outlived its content
  (Join clicked, grace expired) with non-expandable Battery underneath stayed
  open. Hover-peek content is exempt from the "Peek on track change" setting.
- Keyboard path: an opt-in ⌃⌥J (`MeetingHotkey`, Carbon) joins the offered
  meeting. Registered only while a meeting pill/peek is up, and separate from
  `GlobalHotkeys`, which is all-or-nothing and tied to the teleprompter.
- The pill shows a compact locale-aware `2m` / `44s` (`MeetingCountdown`)
  because each flank fits ~20pt of digits; the peek keeps the exact `m:ss`.
