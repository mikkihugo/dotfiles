#!/usr/bin/env bash
# shellcheck disable=SC2016
# from a captured inventory rather than a short-circuiting pipeline.
#
# Why this exists: the unmanaged predecessor destroyed 7 REGISTERED jj
# workspaces on 2026-08-07/08. Its orphan test was
#   if ! jj workspace list 2>/dev/null | grep -q "^${dir_name}:"; then rm -rf
# Under `set -o pipefail`, `grep -q` exits at its first match, `jj` takes
# SIGPIPE and exits 3, pipefail promotes that, `!` inverts it — so a workspace
# matching EARLY in the listing was deleted. Case 6 below is that exact input
# shape: the victim name is the FIRST task entry in the inventory.
#
# Falsifier: reintroduce `rm -rf`, or classify membership through a pipe into
# grep -q, or drop the migration hook from home/modules/activation.nix, and this
# test must fail.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
script="$root/home/modules/engine-worktree-cleanup.sh"
module="$root/home/modules/engine-worktree-cleanup.nix"
activation="$root/home/modules/activation.nix"

failures=0
fail() {
	printf 'FAIL: %s\n' "$1" >&2
	failures=$((failures + 1))
}
ok() { printf 'ok   %s\n' "$1"; }

# ---------------------------------------------------------------- static shape

[[ -f "$script" ]] || {
	echo "FAIL: $script missing" >&2
	exit 1
}
[[ -f "$module" ]] || {
	echo "FAIL: $module missing" >&2
	exit 1
}

# Executable lines only: the header comment quotes the defective pipeline and the
# words rm -rf on purpose, and a test that forbade those would forbid the
# incident write-up that keeps this fix understandable.
body="$(grep -vE '^[[:space:]]*#' "$script")"

if grep -qE '\brm\b[^|;&]*-[a-zA-Z]*r' <<<"$body"; then
	fail "$script contains a recursive rm; every removal must go through repo vcs"
else
	ok "no recursive rm in the sweep"
fi

if grep -qE '\|[[:space:]]*grep[[:space:]]+(-[a-zA-Z]+[[:space:]]+)*-[a-zA-Z]*q' <<<"$body"; then
	fail "$script pipes into grep -q — the 2026-08-08 SIGPIPE misclassification"
else
	ok "no pipe into grep -q"
fi

# The 2026-08-08 defect was the eval-export SILENT FALLBACK, not direnv
# itself. Since the facade's exact-root nix gate (observed failing the sweep
# daily through 2026-08-13), the real-root path must load the flake env via
# `direnv exec` — one-shot and fail-closed — while fixture runs
# (SE_CLEANUP_ENGINE_ROOT set) must bypass direnv entirely.
if grep -qE 'eval .*direnv export' <<<"$body"; then
	fail "$script uses eval direnv-export — the 2026-08-08 silent-fallback pattern"
else
	ok "no eval direnv-export fallback"
fi
check=1
grep -q 'repo_vcs()' "$script" || check=0
grep -qF 'direnv exec "$ENGINE_ROOT"' "$script" || check=0
grep -q 'SE_CLEANUP_ENGINE_ROOT:-' "$script" || check=0
if [ "$check" = 1 ]; then
	ok "facade routed through fail-closed repo_vcs/direnv-exec wrapper with fixture bypass"
else
	fail "$script must route facade calls through repo_vcs(): direnv exec for the real root, direct call under SE_CLEANUP_ENGINE_ROOT"
fi

# The unit must execute the immutable store copy, not a $HOME path an unmanaged
# write could replace.
if grep -qE 'ExecStart = "\$\{cleanupScript\}"' "$module"; then
	ok "ExecStart is the store wrapper"
else
	fail "$module ExecStart must be \${cleanupScript} (a /nix/store path)"
fi
if grep -nE 'ExecStart' "$module" | grep -q 'local/bin'; then
	fail "$module ExecStart points into ~/.local/bin, which is mutable"
fi

if grep -q 'X-SwitchMethod = "keep-old"' "$module"; then
	ok "hms cannot start the sweep (X-SwitchMethod=keep-old)"
else
	fail "$module must set X-SwitchMethod = \"keep-old\"; otherwise hms runs a destructive sweep"
fi

if grep -q 'force = true' "$module"; then
	ok "the .local/bin copy is force-replaced, not clobber-blocked"
else
	fail "$module must set force = true on the ~/.local/bin file"
fi

# Migration: the unmanaged plain files must be removed before checkLinkTargets,
# or the first switch aborts with "would be clobbered".
hook="$(sed -n '/retireUnmanagedEngineWorktreeCleanup/,/^    '\'''\'';$/p' "$activation")"
if [[ -z "$hook" ]]; then
	fail "$activation has no retireUnmanagedEngineWorktreeCleanup hook"
else
	grep -q 'entryBefore \["checkLinkTargets"\]' <<<"$hook" ||
		fail "the retirement hook must run entryBefore [\"checkLinkTargets\"]"
	for p in \
		'.config/systemd/user/engine-worktree-cleanup.service' \
		'.config/systemd/user/engine-worktree-cleanup.timer' \
		'.config/systemd/user/timers.target.wants/engine-worktree-cleanup.timer' \
		'.local/bin/engine-worktree-cleanup'; do
		grep -qF "$p" <<<"$hook" || fail "the retirement hook does not remove $p"
	done
	grep -q 'systemctl --user disable --now engine-worktree-cleanup.timer' <<<"$hook" ||
		fail "the retirement hook must stop the timer before removing its unit"
	grep -q 'systemctl --user stop engine-worktree-cleanup.service' <<<"$hook" ||
		fail "the retirement hook must stop an in-flight run before removing its unit"
	# reloadSystemd runs sd-switch, which diffs old-units against new-units and
	# does nothing for an unchanged unit. An unconditional `disable --now` would
	# therefore leave the managed timer stopped from the second `hms` onward.
	grep -qE '! -L .*engine-worktree-cleanup\.timer' <<<"$hook" ||
		fail "the retirement hook must be guarded on the plain (non-symlink) unit file, or it stops the managed timer on every switch"
	if ((failures == 0)); then
		ok "migration hook retires the unmanaged copies pre-checkLinkTargets"
	fi
fi

# ------------------------------------------------------------------- behaviour
#
# HARD GATE, learned the expensive way on 2026-08-08: the behaviour cases below
# EXECUTE the script under test. A version that ignores SE_CLEANUP_ENGINE_ROOT /
# SE_CLEANUP_WORKTREE_ROOT and hardcodes the real paths would sweep the live
# checkout from inside `just check`. Running the pre-fix script through this
# harness did exactly that and deleted 3 real workspace directories. Refuse to
# execute anything that does not honour both overrides.
if ! grep -q 'SE_CLEANUP_ENGINE_ROOT' "$script" ||
	! grep -q 'SE_CLEANUP_WORKTREE_ROOT' "$script"; then
	echo "FAIL: $script does not honour SE_CLEANUP_ENGINE_ROOT/SE_CLEANUP_WORKTREE_ROOT;" >&2
	echo "      refusing to execute it — it would sweep the real checkout" >&2
	exit 1
fi
ok "the sweep honours the fixture root overrides (safe to execute)"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

engine="$tmp/engine"
worktrees="$tmp/worktrees"
mkdir -p "$engine/bin" "$worktrees"

cat >"$engine/bin/repo" <<'FAKE'
#!/usr/bin/env bash
# shellcheck disable=SC2016
set -euo pipefail
printf '%s\n' "$*" >>"$FIXTURE_LOG"
if [[ "${2:-}" == "workspace-list" ]]; then
	[[ "${FIXTURE_LIST_RC:-0}" == 0 ]] || exit "$FIXTURE_LIST_RC"
	cat "$FIXTURE_LIST"
	exit 0
fi
exit "${FIXTURE_VERB_RC:-0}"
FAKE
chmod +x "$engine/bin/repo"

run_case() { # run_case <name> <expected-rc>
	: >"$tmp/log"
	set +e
	FIXTURE_LOG="$tmp/log" \
		FIXTURE_LIST="$tmp/list" \
		FIXTURE_LIST_RC="${FIXTURE_LIST_RC:-0}" \
		FIXTURE_VERB_RC="${FIXTURE_VERB_RC:-0}" \
		SE_CLEANUP_ENGINE_ROOT="$engine" \
		SE_CLEANUP_WORKTREE_ROOT="$worktrees" \
		bash "$script" >"$tmp/out" 2>"$tmp/err"
	rc=$?
	set -e
	[[ "$rc" == "$2" ]] || fail "$1: exit $rc, expected $2"
}

entry() { # entry <name> <lease_state> <reclaim_allowed>
	printf 'name=%s path=%s/%s working_copy=abc 1234 role=task lease_state=%s lease_owner= owns_lease=no path_in_use=no task_write_allowed=no reclaim_allowed=%s cleanup_allowed=no\n' \
		"$1" "$worktrees" "$1" "$2" "$3"
}
default_entry() {
	printf 'name=default path=%s working_copy=abc 1234 role=canonical-readonly lease_state=not-applicable lease_owner= owns_lease=no path_in_use=yes task_write_allowed=no reclaim_allowed=no cleanup_allowed=no\n' "$engine"
}

# 1 — facade unreadable: refuse, call nothing.
FIXTURE_LIST_RC=2 run_case "unreadable facade refuses" 1
grep -qvx 'vcs workspace-list' "$tmp/log" &&
	fail "case 1 called a verb beyond workspace-list after the facade failed"
grep -q 'refusing to delete anything' "$tmp/err" || fail "case 1 did not report a refusal"
unset FIXTURE_LIST_RC
ok "unreadable inventory refuses without calling a verb"

# 2 — empty inventory: refuse.
: >"$tmp/list"
run_case "empty inventory refuses" 1
grep -q 'workspace-list is empty' "$tmp/err" || fail "case 2 did not report an empty inventory"
ok "empty inventory refuses"

# 3 — registered, present, reclaimable: workspace-close, nothing else.
mkdir -p "$worktrees/lane-a"
{
	default_entry
	entry lane-a expired yes
} >"$tmp/list"
run_case "reclaimable present workspace" 0
grep -qx 'vcs workspace-close lane-a' "$tmp/log" || fail "case 3 did not call workspace-close"
grep -q 'workspace-prune-orphan' "$tmp/log" && fail "case 3 pruned a registered workspace"
[[ -d "$worktrees/lane-a" ]] || fail "case 3 removed the directory itself"
ok "reclaimable present workspace goes through workspace-close"

# 4 — registered, path gone: forget-missing.
rm -rf "$worktrees/lane-a"
run_case "registered with missing path" 0
grep -qx 'vcs workspace-forget-missing lane-a' "$tmp/log" || fail "case 4 did not call forget-missing"
ok "missing path clears only the registration"

# 5 — live lease: never touched.
mkdir -p "$worktrees/lane-live"
{
	default_entry
	entry lane-live active no
} >"$tmp/list"
run_case "live lease untouched" 0
grep -qx 'vcs workspace-list' "$tmp/log" || fail "case 5 read no inventory"
grep -qE 'workspace-(close|forget-missing|prune-orphan)' "$tmp/log" && fail "case 5 acted on a live lease"
ok "live lease is never acted on"

# 6 — THE REGRESSION. A registered workspace that appears FIRST in the listing,
# with an unregistered directory beside it. The old pipeline classified the
# early match as an orphan. Only the unregistered name may be pruned.
mkdir -p "$worktrees/aaa-early" "$worktrees/zzz-stray"
{
	default_entry
	entry aaa-early active no
} >"$tmp/list"
run_case "early-matching registration survives" 0
grep -q 'aaa-early' "$tmp/log" && fail "case 6 called a verb on the registered early match"
grep -qx 'vcs workspace-prune-orphan zzz-stray' "$tmp/log" || fail "case 6 did not prune the unregistered directory"
[[ -d "$worktrees/aaa-early" ]] || fail "case 6 removed a registered workspace"
ok "a registration matching early in the listing is not treated as an orphan"

# 7 — every guarded verb refusing: report and keep, exit 0.
FIXTURE_VERB_RC=1 run_case "refusals are kept, not forced" 0
grep -q 'keeping' "$tmp/out" || fail "case 7 did not report a refusal as kept"
[[ -d "$worktrees/zzz-stray" ]] || fail "case 7 removed a directory the facade refused"
unset FIXTURE_VERB_RC
ok "a refusal keeps the workspace"

if ((failures > 0)); then
	echo "$failures engine-worktree-cleanup contract failure(s)" >&2
	exit 1
fi
echo "engine-worktree-cleanup contract holds"
