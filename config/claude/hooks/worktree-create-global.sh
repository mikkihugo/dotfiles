#!/usr/bin/env bash
# WorktreeCreate hook: put Claude Code worktrees in the GLOBAL worktree tree
# instead of <repo>/.claude/worktrees/.
#
# Why: Claude Code has no setting for the worktree location (only worktree.baseRef);
# the documented way to relocate it is to replace creation with this hook. Keeping
# checkouts inside the repo puts a full second copy under the working tree, which
# host sweeps that walk ~/code by depth then have to descend and skip.
#
# Layout matches what `repo vcs workspace-spawn` already uses, so every worktree
# for a repo lives in one place regardless of which tool made it:
#   /home/mhugo/code/worktrees/git/<repo>/<name>
#
# Contract: read JSON on stdin, print the created worktree path on stdout, send
# all logging to stderr. A non-zero exit makes Claude Code fall back / report.
set -euo pipefail

GLOBAL_ROOT="${CLAUDE_WORKTREE_ROOT:-/home/mhugo/code/worktrees/git}"

payload="$(cat)"
name="$(printf '%s' "$payload" | jq -r '.name // empty')"
if [ -z "$name" ]; then
	echo "worktree-create-global: no .name in hook payload" >&2
	exit 1
fi

# Reject anything that could escape the target directory.
case "$name" in
*/* | *..*)
	echo "worktree-create-global: refusing unsafe worktree name '$name'" >&2
	exit 1
	;;
esac

root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [ -z "$root" ]; then
	echo "worktree-create-global: not inside a git repository" >&2
	exit 1
fi
repo="$(basename "$root")"

target="$GLOBAL_ROOT/$repo/$name"
branch="worktree-$name"

if [ -e "$target" ]; then
	echo "worktree-create-global: $target already exists" >&2
	exit 1
fi
mkdir -p "$(dirname "$target")"

# Mirror the built-in naming (branch `worktree-<name>`) so existing tooling that
# recognises those branches keeps working. baseRef=head means branch from HEAD.
if git -C "$root" show-ref --verify --quiet "refs/heads/$branch"; then
	git -C "$root" worktree add "$target" "$branch" >&2
else
	git -C "$root" worktree add -b "$branch" "$target" HEAD >&2
fi

printf '%s\n' "$target"
