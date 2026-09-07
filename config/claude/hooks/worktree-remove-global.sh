#!/usr/bin/env bash
# WorktreeRemove hook: counterpart to worktree-create-global.sh.
#
# Required, not optional. Once WorktreeCreate is replaced, Claude Code's built-in
# cleanup no longer knows how to remove the worktree it asked us to make, and the
# directory is simply left on disk. This host already carries 63 worktrees; a
# leak per session is exactly how that number got there.
#
# Contract: worktree_path arrives on stdin as JSON. All output is discarded by
# Claude Code, so diagnostics go to stderr.
set -euo pipefail

GLOBAL_ROOT="${CLAUDE_WORKTREE_ROOT:-/home/mhugo/code/worktrees/git}"

payload="$(cat)"
path="$(printf '%s' "$payload" | jq -r '.worktree_path // empty')"
if [ -z "$path" ]; then
	echo "worktree-remove-global: no .worktree_path in payload" >&2
	exit 0
fi

# Only ever delete inside the directory we own. The reference example pipes
# straight into `rm -rf`, which would happily take any path the payload names.
case "$path" in
"$GLOBAL_ROOT"/*) ;;
*)
	echo "worktree-remove-global: refusing to remove '$path' (outside $GLOBAL_ROOT)" >&2
	exit 0
	;;
esac
case "$path" in
*..*)
	echo "worktree-remove-global: refusing traversal path '$path'" >&2
	exit 0
	;;
esac

# Prefer git's own removal so the worktree is deregistered rather than left as a
# stale administrative entry needing a later prune.
if root="$(git -C "$path" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"; then
	repo_root="$(dirname "$root")"
	git -C "$repo_root" worktree remove --force "$path" >&2 2>/dev/null ||
		rm -rf -- "$path"
	git -C "$repo_root" worktree prune >&2 2>/dev/null || true
else
	rm -rf -- "$path"
fi

echo "worktree-remove-global: removed $path" >&2
