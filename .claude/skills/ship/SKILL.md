---
name: ship
description: Use ONLY when explicitly asked to ship, push, publish, or open a PR for the current work. Runs pre-push-docs-sync, commits any outstanding changes, pushes the branch, and opens a PR with the standard template. Never invoke this on your own initiative — it has real, visible side effects (a push and a public PR) and requires the user's explicit request each time.
disable-model-invocation: true
---

# Ship

## Overview

The full "get this into a PR" sequence this project runs every time,
bundled into one skill instead of re-typed each session: docs sync,
commit, push, PR. Matches the `/pr` command's own steps but starts one
stage earlier (committing outstanding work), since "ship this" often means
there's still uncommitted work to fold in.

## When to Use

Only on an explicit request — "ship this", "push this", "open a PR",
"publish what we have". Not a good match for mid-task pauses where the
user hasn't said they're done; ask first if it's unclear whether they mean
"ship everything now" or "ship what's already committed."

## Procedure

1. **Check state.** `git status --short` — is there uncommitted work? If
   the changes span clearly unrelated concerns (e.g. an unrelated doc
   fix and a real feature), ask whether to split into separate commits
   rather than bundling them, per this repo's own commit conventions
   (`CLAUDE.md`: "Small, focused commits with a clear subject line").

2. **Run `pre-push-docs-sync`** — reconciles `docs/ROADMAP.md`, `CLAUDE.md`,
   `README.md`, scans for debug leftovers, confirms the test suite is
   green, and produces the chat summary this skill also needs for the PR
   body. Don't skip this even for a small change — that's exactly the case
   it exists for.

3. **Commit.** If there's outstanding work after step 2's doc updates,
   stage and commit it with a message describing the *why*, not just the
   *what* — matching this repo's existing commit style (see recent
   `git log` for tone/format). Never bundle unrelated changes into one
   commit.

4. **Push.** `git push` (or `git push -u origin <branch>` if the branch
   has no upstream yet).

5. **Check for an existing PR first** — `gh pr list --state open --head
   <branch>`. If one's already open, this push just updates it; report
   that instead of creating a duplicate.

6. **Otherwise open one** — `gh pr create --base main --head <branch>`
   with:
   - `## Summary` — 2-5 plain-language bullets covering what shipped and
     why, drawn from step 2's chat summary, not a raw commit-log dump
   - `## Test plan` — a checklist of what was actually verified; mark
     manual-only items as such
   - The standard attribution footer this session's own instructions
     specify for pull request descriptions

7. **Report** the PR URL and a one-paragraph plain-language summary of
   what shipped — the same content as step 2's chat summary, not a
   restatement of the commit log.

## What NOT to Do

- Don't run this speculatively "just in case" — it pushes to a shared
  remote and opens a public PR, both real side effects that need the
  user's explicit ask each time (see `disable-model-invocation` above).
- Don't skip `pre-push-docs-sync` because the change feels small — see
  that skill's own "What NOT to do" section for why that's exactly the
  case it exists to catch.
- Don't force-push, skip hooks, or bypass a failing test suite to get
  something out the door — stop and report the blocker instead.
