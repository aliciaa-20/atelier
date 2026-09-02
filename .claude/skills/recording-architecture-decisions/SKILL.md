---
name: recording-architecture-decisions
description: Use when a non-obvious architectural or design choice was just made or reversed in Atelier — a window/panel behavior flag, a state-machine shape, a data-source seam, a rejected alternative — even if the user hasn't asked for a written record.
---

# Recording Architecture Decisions

## Overview

Atelier already has a decision log: `docs/decisions/000X-*.md`, three ADRs so
far. The value of an ADR comes from writing it once a decision is confirmed
correct — not mid-investigation, and not only when explicitly asked.

**Failure mode this addresses:** during the Phase 4 click-handling debug, an
ADR draft for the `canBecomeKey` fix was started before the fix was actually
confirmed working on-device. Writing the ADR before verification risks
recording a decision that gets reversed an hour later, and conflates
"investigation notes" with "accepted decision."

## When to Use

Write an ADR when, after the fact, you can point at:
- A choice between real alternatives (not "the only way to do it")
- A reason a first attempt was wrong, and what replaced it
- A constraint that will look arbitrary to a future reader without context
  (e.g. "why does `canBecomeKey` return `true` when the comment above it
  used to say the opposite?")
- A decision `CLAUDE.md`'s invariants section implicitly depends on

Do **not** write one for:
- Routine implementation that follows an already-recorded decision
- An in-progress investigation — wait for confirmation first (see below)
- Pure preference with no rejected alternative behind it

## When NOT Yet — Verification Gate

```
Made a change that fixes something?
  -> Confirmed on-device / tests green?
       -> yes: write the ADR now, while the reasoning is fresh
       -> no: do NOT write the ADR yet. Finish verifying first.
```

An ADR describes an *accepted* decision. A decision isn't accepted until the
fix has been checked against reality (build + manual verification for
window/UI behavior, or the relevant test suite for logic) — see
`CLAUDE.md`'s testing section for what counts as verified for a given layer.

## Procedure

1. Confirm the change actually works (build, run, or test as appropriate).
2. Copy the shape of an existing ADR — `docs/decisions/0003-*.md` is a good
   recent template: Status/Date, Context, Investigation (if there was one),
   Decision, Consequences (include what still needs manual re-checking).
3. Number it sequentially (`000{N}-kebab-case-title.md`).
4. Link it from wherever it's relevant — `CLAUDE.md`'s invariants list,
   `docs/ROADMAP.md`'s phase notes, or a code comment near the affected file
   (as ADR 0002 is linked from the Spotify parsing invariant).
5. Keep it short. These are decision records, not design docs — a page or
   less, evidence-based (what was actually observed), not speculative.

## Quick Reference

| Signal | Action |
|---|---|
| Fix confirmed working, alternatives were considered | Write the ADR now |
| Fix just applied, not yet verified | Wait — verify first |
| Following an existing ADR's decision | No new ADR needed |
| Reversing a prior ADR | New ADR, and update the old one's Status to "Superseded by 000N" |

## Common Mistakes

- Starting the ADR as a running log during debugging instead of after
  confirmation — it turns into narrative, not a decision record, and risks
  documenting a wrong turn as the accepted answer.
- Skipping the ADR because "it wasn't asked for" — the point of this skill
  is to write it proactively when the decision qualifies, not to wait for
  a request.
