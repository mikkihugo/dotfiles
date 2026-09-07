#!/usr/bin/env bash
# SessionEnd guard: report repository workspaces this session leaves behind.
#
# WHY THIS EXISTS
# Every other workspace rule in this setup is a hard gate that fires BEFORE
# work: PreToolUse blocks raw git in jj repos, read_full_workspace_inventory
# blocks housekeeping until the inventory is read, and a write into a workspace
# requires a live lease. Closure is the only rule left to the honour system --
# the agent must still be alive and must voluntarily reach a final step.
#
# It does not survive contact with reality. On 2026-07-25 singularity-engine
# held 219 task records and 12 live leases: ~200 workspaces opened and never
# closed. The system had already DETECTED it (task_close_warning=yes,
# task_age_seconds=70410 against task_max_hours=4) and computed that warning
# with nobody left running to read it.
#
# So this is the missing gate, on the one event that fires at the end.
#
# REPORT ONLY. It never closes, releases, forgets or deletes anything. Deciding
# a workspace is finished requires knowing whether its work landed, which this
# cannot determine -- and an automated closer that guesses wrong destroys work.
# Its whole job is to make the debt visible at the moment it is created.
#
# SessionEnd does not fire on a crash or a kill -9. The periodic sweep in
# git-auto-backup.nix is the backstop for those; the two are complementary and
# neither replaces the other.
set -uo pipefail

LEASE_ROOT="${SE_LOCK_ROOT:-/tmp/singularity-engine}/workspace-leases"
now=$(date +%s)

input=$(cat 2>/dev/null || true)
session=$(printf '%s' "$input" | jq -r '.session_id // ""' 2>/dev/null)

emit() {
	printf '%s\n' "$1"
	exit 0
}
[ -d "$LEASE_ROOT" ] || emit '{"suppressOutput": true}'

mine=() stale=()
for task in "$LEASE_ROOT"/*.task; do
	[ -e "$task" ] || continue
	ws=$(basename "$task" .task)

	# Field order is fixed by scripts/se_task.sh: objective, plan, scope,
	# max_files, max_lines, max_hours, started_epoch, resize_count, owner_ref.
	IFS=$'\t' read -r _obj _plan _scope _mf _ml max_hours started _rc owner _rest <"$task" 2>/dev/null || continue
	[ -n "${owner:-}" ] || continue

	# A live lease means someone is still working; not this hook's business.
	[ -e "$LEASE_ROOT/$ws.lease" ] && continue

	if [ -n "$session" ] && [[ "$owner" == *"$session"* ]]; then
		mine+=("$ws")
		continue
	fi

	# Over-age without a lease is the abandoned case the system already flags.
	if [[ "${started:-}" =~ ^[0-9]+$ ]] && [[ "${max_hours:-}" =~ ^[0-9]+$ ]] && [ "$max_hours" -gt 0 ]; then
		age_h=$(((now - started) / 3600))
		[ "$age_h" -gt "$max_hours" ] && stale+=("$ws (${age_h}h/${max_hours}h, $owner)")
	fi
done

[ ${#mine[@]} -eq 0 ] && [ ${#stale[@]} -eq 0 ] && emit '{"suppressOutput": true}'

msg=""
if [ ${#mine[@]} -gt 0 ]; then
	msg+="This session leaves ${#mine[@]} workspace(s) open without a lease: ${mine[*]}. "
	msg+="Land or abandon them via the repo vcs facade -- nothing else will. "
fi
if [ ${#stale[@]} -gt 0 ]; then
	n=${#stale[@]}
	# Cap the list: the point is to surface the debt, not to paste 200 lines
	# into the terminal on every exit.
	shown=("${stale[@]:0:5}")
	msg+="${n} other workspace(s) are past their declared max_hours with no lease"
	msg+=" (oldest shown): ${shown[*]}."
fi

jq -cn --arg m "$msg" '{systemMessage: $m}' 2>/dev/null || printf '{"systemMessage": "%s"}\n' "$msg"
