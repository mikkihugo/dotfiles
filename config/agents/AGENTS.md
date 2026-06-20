# User Agent Git Hygiene

Do not use `git stash` as durable storage. Stash is only a same-turn parking
lot. If work must survive interruption, create a branch or WIP commit. If a
stash is unavoidable, anchor it before ending the turn:

```bash
git branch "wip/stash-<n>-<topic>" "stash@{<n>}"
```

Never use `git stash pop`; use `git stash apply`, verify the result, then drop
manually.

For branch-scale or swarm work, use one `git worktree` per editing lane. Branch
names must carry lifecycle prefixes:

- `work/<topic>` active implementation
- `wip/<topic>` interrupted work
- `review/<topic>` ready for review
- `archive/<date>-<topic>` retained inactive work

Merged local branches are cleanup candidates, not durable storage. Delete them
after confirmation with `git branch -d <branch>`, or rename retained evidence
under `archive/<date>-<topic>`.

Before ending a turn with dirty or unmerged work, report one of: committed
branch, active worktree path and branch, anchored stash branch, or exact dirty
files intentionally left uncommitted.
