#!/usr/bin/env bash
# engine-worktree-cleanup — retire stale singularity-engine jj task workspaces.
#
# Owned by home/modules/engine-worktree-cleanup.nix. The systemd unit runs this
# file from its immutable /nix/store copy, so an unmanaged edit in $HOME cannot
# change what the timer executes.
#
# This script schedules the repository facade's own guarded verbs. It does NOT
# delete anything itself. Every removal goes through `repo vcs`, which verifies
# ownership, cleanliness, integration and deregistration and fails closed.
#
# WHY (incident 2026-08-08): the previous version deleted 7 REGISTERED engine
# workspaces, leaving their jj registrations behind. Three defects:
#
#   1. The orphan loop tested registration with
#          if ! jj workspace list 2>/dev/null | grep -q "^${dir_name}:"; then
#      Under `set -o pipefail`, `grep -q` exits at its first match, `jj` then
#      takes SIGPIPE and exits 3, pipefail makes that the pipeline status, and
#      `!` inverts it — so a workspace that IS registered and matches EARLY in
#      the listing was classified as an orphan and rm -rf'd. Only names in jj's
#      final write survived. Reproduced in a scratch jj 0.41 repo: 35 of 40
#      registered workspaces destroyed. Journal evidence: 4 deleted 2026-08-07
#      21:33, 2 on 08-08 03:31, 1 on 08-08 12:34 — all "removing orphan", all
#      registered at the time.
#
#   2. The retire loop ran `jj workspace forget "$name" 2>/dev/null || true`
#      and then removed the directory unconditionally, so a failed forget still
#      produced an orphan. It had not fired yet, but it was a second factory.
#
#   3. It reached the facade through `eval "$(direnv export bash)"`. In every
#      real timer run that eval FAILED ("Boolean setting
#      'builders-use-substitutes' has invalid value ''", because the engine's
#      nix/cache/org-nix-config.sh needs a python3 the unit's PATH lacks) and
#      direnv fell back to the previous environment. The script then ran with
#      whatever `jj` happened to be on PATH and no facade at all. The facade is
#      now reached by absolute path and direnv is not used.
#
# There is no pipe into a short-circuiting reader anywhere below, and no bare
# rm -rf. Reintroducing either is how this recurs.
set -euo pipefail

# Overridable only so scripts/test-engine-worktree-cleanup.sh can point the
# sweep at a fixture facade. The systemd unit sets neither, so the timer always
# operates on the real checkout.
ENGINE_ROOT="${SE_CLEANUP_ENGINE_ROOT:-/home/mhugo/code/singularity-engine}"
WORKTREE_ROOT="${SE_CLEANUP_WORKTREE_ROOT:-/home/mhugo/code/worktrees/jj/singularity-engine}"

REPO="$ENGINE_ROOT/bin/repo"
if [[ ! -x "$REPO" ]]; then
	echo "engine-worktree-cleanup: no executable facade at $REPO; refusing to touch anything" >&2
	exit 1
fi

cd "$ENGINE_ROOT"

cleaned=0
kept=0

# Authoritative inventory, captured once with its status checked. If this cannot
# be read we exit rather than guess — an unreadable registry previously meant
# "everything looks like an orphan".
if ! inventory="$("$REPO" vcs workspace-list 2>/dev/null)"; then
	echo "engine-worktree-cleanup: cannot read workspace-list; refusing to delete anything" >&2
	exit 1
fi
if [[ -z "$inventory" ]]; then
	echo "engine-worktree-cleanup: workspace-list is empty; refusing to delete anything" >&2
	exit 1
fi

field() { # field <line> <key>
	local line="$1" key="$2" rest
	rest="${line#*"${key}"=}"
	[[ "$rest" != "$line" ]] || return 1
	printf '%s' "${rest%% *}"
}

# Pass 1: registrations the facade says are reclaimable.
while IFS= read -r line; do
	[[ -n "$line" ]] || continue
	name="$(field "$line" name || true)"
	[[ -n "$name" ]] || continue
	[[ "$name" == "default" ]] && continue

	lease_state="$(field "$line" lease_state || true)"
	reclaim_allowed="$(field "$line" reclaim_allowed || true)"

	if [[ "$lease_state" != "missing" && "$lease_state" != "expired" ]]; then
		kept=$((kept + 1))
		continue
	fi
	if [[ "$reclaim_allowed" != "yes" ]]; then
		kept=$((kept + 1))
		continue
	fi

	ws_path="$WORKTREE_ROOT/$name"

	if [[ -d "$ws_path" ]]; then
		# Registered and present: workspace-close verifies clean + integrated, then
		# forgets and removes. If it refuses, the lane keeps its work — that refusal
		# is the feature, so it is reported and not worked around.
		if "$REPO" vcs workspace-close "$name" >/dev/null 2>&1; then
			echo "engine-worktree-cleanup: closed $name (lease=$lease_state)"
			cleaned=$((cleaned + 1))
		else
			echo "engine-worktree-cleanup: keeping $name — workspace-close refused (dirty, unintegrated, or owned)"
			kept=$((kept + 1))
		fi
	else
		# Registered but the path is gone: this is the orphan state the old script
		# manufactured. forget-missing is the verb that proves the path is absent
		# and clears only the registration.
		if "$REPO" vcs workspace-forget-missing "$name" >/dev/null 2>&1; then
			echo "engine-worktree-cleanup: forgot missing registration $name"
			cleaned=$((cleaned + 1))
		else
			echo "engine-worktree-cleanup: keeping $name — forget-missing refused" >&2
			kept=$((kept + 1))
		fi
	fi
done <<<"$inventory"

# Pass 2: directories on disk with no registration. Membership is tested against
# the captured inventory with bash pattern matching — no pipe, so no SIGPIPE can
# make a registered workspace look unregistered.
if [[ -d "$WORKTREE_ROOT" ]]; then
	for d in "$WORKTREE_ROOT"/*/; do
		[[ -d "$d" ]] || continue
		dir_name="$(basename "$d")"
		[[ "$dir_name" == "default" ]] && continue

		if [[ "$inventory" == *"name=$dir_name "* || "$inventory" == *"name=$dir_name" ]]; then
			continue # registered — pass 1 owns it
		fi

		if "$REPO" vcs workspace-prune-orphan "$dir_name" >/dev/null 2>&1; then
			echo "engine-worktree-cleanup: pruned unregistered directory $dir_name"
			cleaned=$((cleaned + 1))
		else
			echo "engine-worktree-cleanup: keeping unregistered $dir_name — prune-orphan refused (working copy or live lease)"
			kept=$((kept + 1))
		fi
	done
fi

echo "engine-worktree-cleanup: done, $cleaned cleaned, $kept kept"
