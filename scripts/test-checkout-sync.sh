#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

export HOME="$tmp/home"
mkdir -p "$HOME/code" "$HOME/code/worktrees" "$HOME/.local/state"

git_init() {
	local bare="$1" work="$2"
	git init --bare -q "$bare"
	git init -q "$work"
	git -C "$work" remote add origin "$bare"
	git -C "$work" config user.email test@example.invalid
	git -C "$work" config user.name test
	printf '%s\n' base >"$work/file"
	git -C "$work" add file
	git -C "$work" commit -qm base
	git -C "$work" push -q -u origin HEAD:main
	git -C "$work" branch -M main
}

git_init "$tmp/behind.git" "$HOME/code/behind"
printf '%s\n' remote >"$tmp/remote-file"
git clone -q -b main "$tmp/behind.git" "$tmp/remote"
git -C "$tmp/remote" config user.email test@example.invalid
git -C "$tmp/remote" config user.name test
cp "$tmp/remote-file" "$tmp/remote/file"
git -C "$tmp/remote" add file && git -C "$tmp/remote" commit -qm remote && git -C "$tmp/remote" push -q

git_init "$tmp/upstream.git" "$HOME/code/worktrees/diverged-but-upstream"
printf '%s\n' equivalent >"$HOME/code/worktrees/diverged-but-upstream/equivalent"
git -C "$HOME/code/worktrees/diverged-but-upstream" add equivalent
git -C "$HOME/code/worktrees/diverged-but-upstream" commit -qm local
git clone -q -b main "$tmp/upstream.git" "$tmp/upstream-remote"
git -C "$tmp/upstream-remote" config user.email test@example.invalid
git -C "$tmp/upstream-remote" config user.name test
printf '%s\n' equivalent >"$tmp/upstream-remote/equivalent"
git -C "$tmp/upstream-remote" add equivalent
git -C "$tmp/upstream-remote" commit -qm remote
git -C "$tmp/upstream-remote" push -q

git_init "$tmp/unique.git" "$HOME/code/unique-commits"
git -C "$HOME/code/unique-commits" commit --allow-empty -qm unique

git_init "$tmp/dirty.git" "$HOME/code/dirty"
printf '%s\n' dirty >>"$HOME/code/dirty/file"

mkdir -p "$HOME/code/jj-skip/.git" "$HOME/code/jj-skip/.jj"

CHECKOUT_SYNC_NO_COORD=1 "$root/scripts/checkout-sync" >/dev/null

python3 - "$HOME/.local/state/checkout-sync/status.json" <<'PY'
import json, sys
rows = json.load(open(sys.argv[1]))["checkouts"]
by = {r["path"]: r for r in rows}
assert by[next(p for p in by if p.endswith('/behind'))]["action"] == "fast-forwarded"
assert by[next(p for p in by if p.endswith('/diverged-but-upstream'))]["action"] == "stale-but-safe"
assert by[next(p for p in by if p.endswith('/unique-commits'))]["action"] == "unique-local-commits"
assert by[next(p for p in by if p.endswith('/dirty'))]["action"] == "dirty"
assert not any(p.endswith('/jj-skip') for p in by)
PY

echo "checkout sync fixture: ok"
