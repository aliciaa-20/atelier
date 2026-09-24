---
name: pre-push-docs-sync
description: Use before any `git push` in this repo — syncs docs/ROADMAP.md, CLAUDE.md, and README.md (plus any other docs a shipped change touches, e.g. FEATURES.md or a decisions/ ADR) with what actually shipped, scans for leftover debug code, confirms tests are green, and posts a status summary in chat before the push happens.
---

# Pre-Push Docs Sync

## Overview

It's easy for `docs/ROADMAP.md` to drift from reality mid-session — phases
get checkboxed only when someone remembers, and a run of small polish
commits (padding tweaks, animation timing, a corner radius) rarely earns
its own roadmap update even though it adds up. This skill is the checkpoint
that catches the drift **right before it goes to GitHub**, not weeks later.

## When to Use

Immediately before running `git push` (or opening a PR) for this repo.
Not needed for a purely local commit that isn't being pushed yet.

**Skip the whole thing** (don't even start the procedure) for a push that
can't contain doc-relevant changes:
- `git push origin --delete <branch>` or any other branch/tag deletion.
- A push of a tag only (no commits).
- A push where `git log origin/<branch>..HEAD --oneline` is empty (nothing
  new to sync docs against — e.g. re-pushing after a force-push of the same
  tip, or pushing a branch that's already up to date).

These showed up in practice as the skill firing on every `git push*`
match regardless of what was being pushed, including plain branch
cleanup — pure waste, since there's no diff to reconcile docs against.

## Fast path — small pushes whose docs are already in the diff

Added 2026-09-24 to save tokens: on small branches the docs were usually
updated in the same commits, so re-reading ROADMAP/CLAUDE.md/FEATURES again
is pure repeat cost. Use the fast path only when **all** of these hold:

- the branch is small (roughly <= 5 commits) and touches no new top-level file
  under `Atelier/`, no `### Invariants` bullet, no permission / Info.plist key,
  and no new architectural decision (no ADR needed);
- `git diff origin/main..HEAD --stat` already shows the relevant doc files
  (ROADMAP/README/CLAUDE.md/FEATURES/ADR) changed in this branch, or the change
  is code-only polish with nothing doc-worthy.

Then do only this, and skip steps 4-8 below:

1. `git log origin/<branch>..HEAD --oneline` (step 1).
2. Debug-print scan (step 2) and the full unit suite (step 3).
3. `grep -n "tests passing" README.md` -- fix the count if the suite's number
   changed (the one doc line that drifts on almost every push).
4. A **2-3 line** chat summary (what shipped, what's deferred) -- step 9, short.
5. Push.

If any condition fails, or you're unsure, run the full procedure. Pushes that
add a phase, change the architecture table, add a permission, or record a
decision are never fast-path. The fast path only changes how much is
*re-read*; it never skips the tests or the debug scan.

## Procedure

Run through these in order:

1. **Diff since the last push.** `git log origin/<branch>..HEAD --oneline`
   (or `origin/main..HEAD` if the branch tracks nothing yet) to see exactly
   what's about to go out.

2. **Scan for leftover debug instrumentation.** `grep -rn "\[TIMING\]\|print(" Atelier/ AtelierTests/`
   and eyeball the hits — temporary `print()` diagnostics (like the ones
   added mid-session to trace the artwork-cache latency bug) are easy to
   forget to strip before committing. Remove anything that was clearly a
   throwaway diagnostic, not a real log line the app wants long-term.

3. **Run the unit suite.** `xcodebuild test -scheme Atelier -destination 'platform=macOS'`.
   Don't push on a red or unverified suite — see `CLAUDE.md`'s Testing
   section for what's actually covered (geometry/state/parsing) versus
   what's manual-only.

4. **Reconcile `docs/ROADMAP.md` against the diff.** Start from step 1's
   diff, not a fresh read of the whole file: `grep -n "^### "
   docs/ROADMAP.md` to find the phase heading(s) the diff's commits
   actually touch, then read only those sections (plus the "Where we are"
   line near the top) rather than the entire file. For each shipped
   change, ask: does an existing phase's checkbox need checking off? Does
   the phase need to move from "Upcoming" to "Completed" with a commit
   hash? Does "Where we are" still match reality? Use the
   `phase-completion-checklist` skill's own gate here too — don't check
   off a manual-verification bullet unless it was actually exercised
   on-device this session, not just "should work."

5. **Check whether `CLAUDE.md` needs updating.** New files, a changed
   invariant, or a shifted architectural seam (new corner-radius rules, the
   `ArtworkImageCache` seam, the `MarqueeText` redesign, etc.) belong in the
   Architecture table or invariants list if they're the kind of thing a
   future session would need to know without re-deriving it. Most pushes
   don't touch this — a quick check is whether step 1's diff added any new
   top-level file under `Atelier/` or changed an `### Invariants` bullet;
   if not, this step is usually a no-op and doesn't need a full read.

6. **Check whether `README.md` needs updating.** It's the first thing
   anyone (including future-you) sees, and it drifts just as easily as
   `docs/ROADMAP.md` — a stale "Status" line (this repo shipped a whole
   push once with README still reading "Phase 0 — scaffolding" long after
   Phase 8 landed) is worse than a missing one, since it actively
   misinforms. `grep -n "tests passing\|## Status"  README.md` first — if
   the test count already matches what step 3 just ran and the Status line
   already mentions this push's work, that's enough; only read the whole
   file when something looks stale. Also check any Permissions section (a
   new TCC grant this push added, like Accessibility for the media-key
   tap) and Requirements if the deployment target or toolchain changed.

7. **Check other docs a shipped change actually touches.** Not every push
   needs this, but don't skip checking: `docs/FEATURES.md` if a feature
   from its survey shipped or changed scope, and any file under
   `docs/decisions/` if step 8 below is about to add a new ADR (link it
   from `CLAUDE.md`'s reference-apps list or elsewhere if that's where
   ADRs get indexed in this repo).

8. **Check for un-recorded architectural decisions.** If this session made
   a real "we tried X, it didn't work, we did Y instead" call — run
   `recording-architecture-decisions` before pushing, not after.

9. **Post a chat summary before pushing** — not after. Cover:
   - what shipped in this push, in plain language (not a commit-log dump)
   - which phase(s) this moves the roadmap forward on, if any
   - what's still open / explicitly deferred ("bottom padding could be
     perfected further, held off for now" is a real example worth stating,
     not glossing over)
   - any doc files this skill actually changed

10. **Then push.** If the summary surfaces something that should block the
    push (failing tests, an unresolved regression), say so and stop instead
    of pushing anyway.

## What NOT to do

- Don't invent roadmap progress that didn't happen — an in-progress phase
  stays in "Upcoming" even if a push includes real work toward it, unless
  its actual checklist items are done.
- Don't bundle the docs-sync commit with unrelated code changes — a small
  `docs: ...` commit on top is fine and keeps the history legible.
- Don't skip step 9 (the chat summary) because the changes feel "minor" —
  a run of small polish commits is exactly the case this skill exists for;
  it's the large, obviously-a-milestone commits that already get
  summarized without prompting.
- Don't skip checking README.md just because it "doesn't change often" —
  that's exactly why it drifts furthest when it does need a change.

## Quick Reference

| Check | Command / Where |
|---|---|
| What's about to push | `git log origin/<branch>..HEAD --oneline` |
| Debug leftovers | `grep -rn "\[TIMING\]\|print(" Atelier/ AtelierTests/` |
| Tests | `xcodebuild test -scheme Atelier -destination 'platform=macOS'` |
| Roadmap | `docs/ROADMAP.md` — see `phase-completion-checklist` |
| Architecture/invariants | `CLAUDE.md` |
| First impression / status / permissions | `README.md` |
| Feature survey scope | `docs/FEATURES.md` (if a surveyed feature shipped/changed) |
| Non-obvious decisions | `recording-architecture-decisions` skill, `docs/decisions/*.md` |
