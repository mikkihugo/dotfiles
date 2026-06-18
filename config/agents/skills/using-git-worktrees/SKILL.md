---
name: using-git-worktrees
description: Use when feature work needs workspace isolation, branch-safe edits, or a written plan should not run in the current checkout.
---

# Using Git Worktrees

Create isolation only when it reduces risk. Detect existing isolation first.

Purpose: protect the user's current checkout from branch-scale work.
Consumer: agents starting substantial feature work, plan execution, or risky
multi-file edits.
Failure consequence: work pollutes the user's active branch, or nested worktrees
create phantom state.
Falsifier: current workspace is already isolated, or the user explicitly wants
the current checkout edited.

## Gate

Use a worktree when:

- User asks for isolation or a new branch.
- Work is multi-step and branch-scale.
- Existing dirty state is unrelated and likely to conflict.
- Plan execution would touch many files.

Skip when:

- User says edit current checkout.
- Change is narrow, urgent, or GitOps/live-ops scoped.
- Platform already placed you in an isolated workspace.

## Detect

```bash
git rev-parse --show-superproject-working-tree 2>/dev/null
GIT_DIR=$(cd "$(git rev-parse --git-dir)" && pwd -P)
GIT_COMMON=$(cd "$(git rev-parse --git-common-dir)" && pwd -P)
git branch --show-current
```

If `GIT_DIR != GIT_COMMON` and not a submodule, you are already isolated.

## Create

Prefer platform-native worktree tools when available.

Git fallback:

1. Use explicit user/repo worktree location if present.
2. Else use existing `.worktrees/` or `worktrees/`; `.worktrees/` wins.
3. Else default to `.worktrees/`.
4. Verify project-local worktree dir is ignored before creating it.

```bash
git check-ignore -q .worktrees || git check-ignore -q worktrees
git worktree add "$path" -b "$branch"
```

If ignore check fails, add the directory to `.gitignore` and commit that change
before creating project-local worktrees.

## Baseline

After entering the workspace, run setup and the narrow baseline command for the
repo. If baseline fails, report the failure and ask before proceeding.
