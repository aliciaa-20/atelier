---
name: resuming-work
description: Use when starting or resuming an Atelier session and it's unclear what state the repo is in or what to work on next — reconciles local git state against origin, uncommitted/stashed changes, test status, and the project docs (ROADMAP.md, FEATURES.md, CLAUDE.md, decisions/) into one concrete recommendation.
---

# Resuming Work

## Overview

At the start of a session, "what's the state and what's next" has two
independent failure modes: the **repo** can be out of sync (behind origin,
uncommitted WIP, a forgotten stash) and the **docs** can be out of sync with
the repo (`ROADMAP.md`'s "Where we are" line lagging behind what's actually
merged). Recommending a next step from either alone risks re-doing shipped
work or missing it entirely — this happened for real: a session's local
`main` was 6 commits behind origin, including a fully shipped phase, while
`ROADMAP.md` read as current.

## When to Use

Session start, after a time gap, or on "where are we" / "what should we do
next" — before recommending or starting any new work.

## Procedure

1. **Sync check.** `git fetch`, then compare local vs. `origin/<branch>`. If
   fast-forwardable, pull — but `git status`/`git stash -u` first if there's
   anything uncommitted (see step 2), never pull over unstashed changes.
2. **Working-tree check.** `git status` and `git stash list`. Anything
   uncommitted or stashed is an unfinished decision — inspect each diff, and
   for each one decide: still needed (keep/reapply), already shipped
   elsewhere (drop), or genuinely new work (finish it). Don't treat the repo
   as clean until this resolves.
3. **Test state.** Don't trust a roadmap's claimed test count — run
   `xcodebuild test -scheme Atelier -destination 'platform=macOS'` if it's
   been more than a session or two, or before recommending work that builds
   on "tests are green."
4. **Docs pass.** Read, in this order: `docs/ROADMAP.md`'s "Where we are"
   line and current phase, `docs/FEATURES.md`'s backlog, `CLAUDE.md`'s
   architecture table and invariants, and any `docs/decisions/*.md` newer
   than the last session's context — ADRs carry the *why* behind a choice
   that `git log` alone won't surface (a rejected alternative, a flagged
   risk, a deferred item).
5. **Cross-reference docs against actual git state.** Does `git log
   origin/<branch> -20 --oneline` actually match what `ROADMAP.md` claims is
   shipped? Docs drift; commits don't. Trust the log over the prose when
   they disagree, and flag the drift rather than silently trusting either.
6. **Recommend one concrete next action**, not a menu. Prefer, in order:
   (a) resolve any real inconsistency found above (unfinished stash, failing
   test, stale doc) before new work; (b) continue a phase already in
   progress; (c) pick the next backlog item per `FEATURES.md`'s ordering and
   confirm it with the user before starting. State the recommendation
   plainly — "do X next, because Y" — don't just list options.

## Quick Reference

| Check | Command / where |
|---|---|
| Remote sync | `git fetch && git log HEAD..origin/<branch> --oneline` |
| Working tree | `git status`, `git stash list` |
| Tests | `xcodebuild test -scheme Atelier -destination 'platform=macOS'` |
| Roadmap state | `docs/ROADMAP.md` ("Where we are" + phase list) |
| Backlog | `docs/FEATURES.md` |
| Architecture/invariants | `CLAUDE.md` |
| Non-obvious past decisions | `docs/decisions/*.md` |

## Common Mistakes

- Recommending backlog work from `FEATURES.md` without first checking
  whether origin has commits local `main` doesn't — the backlog item may
  already be shipped there.
- Trusting `ROADMAP.md`'s "Where we are" line at face value instead of
  confirming it against `git log` — the two can and have drifted.
- Popping or dropping a stash without reading its diff — it may contain a
  real fix (like a Swift 6 concurrency correction) mixed with changes
  already superseded upstream; resolve per-file, not all-or-nothing.
- Treating "no uncommitted changes" as sufficient without checking
  `git stash list` too — stashed WIP is easy to forget entirely.
