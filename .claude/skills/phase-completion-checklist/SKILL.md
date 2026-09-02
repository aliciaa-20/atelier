---
name: phase-completion-checklist
description: Use when about to claim an Atelier roadmap phase is done, before committing that claim — checks tests, manual verification steps, ROADMAP.md checkboxes, and README/CLAUDE.md consistency against what actually shipped.
---

# Phase Completion Checklist

## Overview

`docs/ROADMAP.md` defines Atelier's phases, each with its own checkbox list
and a "Manual verification" line. A phase isn't done because the code
compiles — it's done when every checkbox is true and verification actually
happened, not assumed.

## When to Use

Before saying "Phase N is done," committing a phase-completion commit, or
moving on to the next phase's roadmap items.

## Checklist

Run through these in order — each gates the next:

1. **Unit tests green.** Run the actual command, don't recall a prior run:
   ```sh
   xcodebuild test -scheme Atelier -destination 'platform=macOS'
   ```
   Only pure-logic layers (`NotchGeometry`, `NotchState`, parsing) are
   covered here — see `CLAUDE.md`'s Testing section for what's in vs. out.

2. **Manual verification steps actually exercised.** Every phase in
   `docs/ROADMAP.md` ends with a "Manual verification" bullet — e.g. Phase 4:
   "play a track, confirm artwork/title/artist/scrubber, exercise every
   transport control, drag the scrubber." Do each one on-device. Don't mark
   it done from reading the code — AppKit/window behavior in particular has
   burned this project before (ADR 0003).

3. **`docs/ROADMAP.md` checkboxes updated.** Check off completed `- [ ]`
   items for the phase, move the phase from "Upcoming" to "Completed" with
   its commit hash, update the "Where we are" line at the top, and advance
   the 🔜 marker to the next phase.

4. **`CLAUDE.md` updated if invariants or architecture changed.** New files,
   new invariants, or a changed seam (like the `NotchPanel` focus behavior
   in ADR 0003) need the corresponding section updated — the Architecture
   table, the invariants list, or both.

5. **New non-obvious decisions have an ADR.** See
   `recording-architecture-decisions` — don't let this checklist substitute
   for that one; run it too if this phase produced a real architectural
   choice.

6. **Commit.** Small, focused, clear subject line, per `CLAUDE.md`
   conventions — not bundled with unrelated cleanup.

## Quick Reference

| Check | Where |
|---|---|
| Tests | `xcodebuild test -scheme Atelier -destination 'platform=macOS'` |
| Manual verification | `docs/ROADMAP.md`, phase's own bullet list |
| Checkboxes / phase status | `docs/ROADMAP.md` |
| Architecture/invariants | `CLAUDE.md` |
| Non-obvious decisions | `recording-architecture-decisions` skill |

## Common Mistakes

- Marking manual-verification bullets done because the code "should" work —
  AppKit window/focus/click behavior in this project has repeatedly not
  matched intuition (see ADR 0003). Actually run the app.
- Updating `docs/ROADMAP.md` checkboxes without updating the "Where we are"
  summary line at the top, leaving it stale.
- Treating "tests pass" as sufficient for phases that are mostly UI/AppKit
  work — the unit suite only covers `NotchGeometry`/`NotchState`/parsing by
  design; UI and window behavior are manual by design too.
