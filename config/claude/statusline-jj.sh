#!@bash@
# shellcheck shell=bash disable=SC1008,SC2239
# Claude Code statusline for jj-backed repos that forbid native jj.
#
# Purpose: show working-copy identity, cleanliness, bookmark, workspace and the
# CAS tree id without ever invoking the `jj` binary — this repo replaces `jj` on
# PATH with an agent-vcs-refuse shim and requires the `repo vcs` facade.
#
# Consumer: settings.json -> statusLine.command
# Falsifier: if `repo vcs status` stops printing a "Working copy  (@) :" line,
# the change id renders empty and this script must be updated.

set -uo pipefail

input=$(cat 2>/dev/null || true)

json_get() {
	[ -n "$input" ] || return 0
	printf '%s' "$input" | @jq@ -r "$1 // empty" 2>/dev/null || true
}

cwd=$(json_get '.workspace.current_dir')
[ -n "$cwd" ] || cwd=$(json_get '.cwd')
[ -n "$cwd" ] || cwd=$(json_get '.workspace.project_dir')
[ -n "$cwd" ] || cwd=$PWD
cd "$cwd" 2>/dev/null || true

model=$(json_get '.model.display_name')

DIM=$'\033[2m'
RST=$'\033[0m'
CYAN=$'\033[36m'
YEL=$'\033[33m'
GRN=$'\033[32m'
MAG=$'\033[35m'

# Resolve `repo` by walking up from the rendered directory, never from PATH: a
# direnv-exported PATH keeps pointing at whichever checkout the shell was opened
# in, which would report that repo's state while sitting somewhere else.
repo_bin=""
root=$cwd
while [ "$root" != "/" ] && [ -n "$root" ]; do
	if [ -x "$root/bin/repo" ]; then
		repo_bin="$root/bin/repo"
		break
	fi
	root=$(dirname "$root")
done

# No repo facade here -> render the plain prompt and stop.
if [ -z "$repo_bin" ]; then
	printf '%s%s%s %s%s%s' "$DIM" "${model:-claude}" "$RST" "$DIM" "$(basename "$cwd")" "$RST"
	exit 0
fi

# Publish atomically: a reader must never see a half-written line.
emit() {
	printf '%s' "$1"
	printf '%s' "$1" >"$cache.tmp.$$" 2>/dev/null && mv -f "$cache.tmp.$$" "$cache" 2>/dev/null
}

# A full `repo vcs` probe costs ~6s wall; a statusline must never block that
# long. Serve the last rendered line immediately and refresh out of band, so a
# render is always cache-fast and the displayed state trails by at most one
# refresh. Only the very first render in a directory pays the full cost.
cache_key=$(printf '%s' "$cwd" | cksum | cut -d' ' -f1)
cache="${TMPDIR:-/tmp}/claude-statusline-jj.$UID.$cache_key"
lock="$cache.lock"
ttl=6

if [ -f "$cache" ] && [ -z "${STATUSLINE_JJ_REFRESH:-}" ]; then
	cat "$cache"
	now=$(date +%s)
	then_=$(stat -c %Y "$cache" 2>/dev/null || echo 0)
	# mkdir is the atomic guard: one refresher at a time, no pile-up of probes.
	if [ $((now - then_)) -ge "$ttl" ] && mkdir "$lock" 2>/dev/null; then
		(
			trap 'rmdir "$lock" 2>/dev/null' EXIT
			STATUSLINE_JJ_REFRESH=1 "$0" <<<"$input" >/dev/null 2>&1
		) &
	fi
	exit 0
fi

status=$("$repo_bin" vcs status 2>/dev/null || true)

# No jj working copy under this path -> plain prompt.
if ! printf '%s' "$status" | grep -q 'Working copy'; then
	line=$(printf '%s%s%s %s%s%s' "$DIM" "${model:-claude}" "$RST" "$DIM" "$(basename "$cwd")" "$RST")
	emit "$line"
	exit 0
fi

change=$(printf '%s' "$status" | sed -n 's/^Working copy  (@) : \([a-z]*\) .*/\1/p')

if printf '%s' "$status" | grep -q 'The working copy has no changes\.'; then
	state="${GRN}clean${RST}"
else
	state="${YEL}dirty${RST}"
fi

# Bookmarks render as "<change> <commit> <bookmark[,bookmark]> | <description>".
# Absent the " | " separator the parent commit carries no bookmark.
parent=$(printf '%s' "$status" | sed -n 's/^Parent commit (@-): //p')
bookmark=""
case "$parent" in
*' | '*) bookmark=$(printf '%s' "$parent" | sed 's/ | .*//' | awk '{print $3}') ;;
esac

ws=$("$repo_bin" vcs current-workspace 2>/dev/null | tr -d '\n')
tree=$("$repo_bin" vcs tree-id @ 2>/dev/null | tr -d '\n' | cut -c1-12)

line="${DIM}${model:-claude}${RST}"
line="${line} ${DIM}│${RST} ${CYAN}${change}${RST} ${state}"
[ -n "$bookmark" ] && line="${line} ${DIM}│${RST} ${MAG}${bookmark}${RST}"
[ -n "$ws" ] && line="${line} ${DIM}│${RST} ${DIM}ws:${RST}${ws}"
[ -n "$tree" ] && line="${line} ${DIM}│${RST} ${DIM}tree:${tree}${RST}"

emit "$line"
