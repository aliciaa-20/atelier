---
description: Open a pull request for the current branch against main
---

Open a pull request for the current branch, using $ARGUMENTS (if given) as
extra context on what this PR is for — otherwise infer it from the diff.

1. Run the `pre-push-docs-sync` skill first, unless it already ran for this
   push (docs sync, debug-leftover scan, green test suite, chat summary).
2. Check what's actually going out: `git status --short` and
   `git log origin/main..HEAD --oneline` (or `origin/<branch>..HEAD` if the
   branch has already been pushed once before).
3. If there are uncommitted changes, stop and ask whether to commit them
   first — don't silently fold unrelated work into this PR.
4. Push: `git push` (or `git push -u origin <branch>` if it has no
   upstream yet).
5. Check for an existing open PR on this branch first
   (`gh pr list --state open --head <branch>`) — if one exists, report its
   URL instead of creating a duplicate.
6. Otherwise create one: `gh pr create --base main --head <branch>` with:
   - `## Summary` — 2-5 bullet points in plain language (not a commit-log
     dump), covering what changed and why
   - `## Test plan` — a checklist of what was actually verified; mark
     manual-only items as such rather than checking things off you can't
     confirm
   - The standard attribution footer this session's instructions specify
     for pull request descriptions
7. Report the PR URL.
