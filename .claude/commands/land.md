---
description: After a PR is merged - sync main, delete the merged branch, refresh memory
---

Clean up after a merged PR (use $ARGUMENTS as the PR number/branch if given, else the current branch):

1. Confirm the PR is actually merged: `gh pr view <n> --json state,mergedAt`. If not merged, stop.
   (Merging itself is the user's step; auto mode may block `gh pr merge`.)
2. `git checkout main && git pull origin main`, then show `git log --oneline -1`.
3. Delete the merged branch locally with `git branch -d <branch>` (safe form only; if it refuses, stop and ask).
4. Ask before deleting the remote branch, then `git push origin --delete <branch>` if approved.
5. List leftover branches/worktrees (`git branch`) and just report them; never remove without asking.
6. Update the relevant memory file and its `MEMORY.md` line to say what merged and what is next.
7. Report in 2-3 lines.
