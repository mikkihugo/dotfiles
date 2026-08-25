#!/usr/bin/env bash
# Reap search processes whose agent already stopped waiting for them.
#
# Why: codex's exec_command `yield_time_ms` is a YIELD, not a kill. At the yield
# deadline codex records "Script completed" with empty output and moves on, but
# leaves the whole subtree running. Four such orphans scanning /nix/store and
# $HOME drove this box to load 70 with PSI io full=40% while CPU sat ~46% idle.
# Nothing else on the host reaps them: every janitor unit prunes files, and
# systemd-oomd triggers on memory pressure only, never on I/O.
#
# Targeting is by ANCESTRY, not age alone. A search with an agent CLI ancestor
# and an age far past any yield window has no live consumer for its output, so
# killing it destroys nothing. A search whose chain tops out at a login shell
# has a human waiting on it and is always left alone.
set -uo pipefail

THRESHOLD=${REAP_THRESHOLD_SECONDS:-300}
DRY_RUN=${REAP_DRY_RUN:-0}
AGENT_COMMS='^(codex|claude|jcode|kimi-code|node)$'
SEARCH_COMMS='^(rg|fd|find|grep|ag|ack)$'
SELF=$$

# Walk up from $1; echo "pid:comm" of the first agent ancestor, else nothing.
agent_ancestor() {
	local pid=$1 depth=0 ppid comm
	while [ "$pid" -gt 1 ] && [ "$depth" -lt 12 ]; do
		read -r ppid comm < <(ps -o ppid=,comm= -p "$pid" 2>/dev/null | tr -s ' ' | sed 's/^ //')
		[ -n "${ppid:-}" ] || return 0
		if [[ "$comm" =~ $AGENT_COMMS ]]; then
			printf '%s:%s\n' "$pid" "$comm"
			return 0
		fi
		pid=$ppid
		depth=$((depth + 1))
	done
}

reaped=0
while read -r pid etimes comm; do
	[ "$pid" != "$SELF" ] || continue
	[[ "$comm" =~ $SEARCH_COMMS ]] || continue
	[ "${etimes:-0}" -gt "$THRESHOLD" ] 2>/dev/null || continue

	ancestor=$(agent_ancestor "$pid")
	if [ -z "$ancestor" ]; then
		continue # human-owned: a person is waiting for this
	fi

	args=$(ps -o args= -p "$pid" 2>/dev/null | cut -c1-160)
	if [ "$DRY_RUN" = 1 ]; then
		printf 'WOULD-REAP pid=%s comm=%s age=%ss agent=%s cmd=%s\n' "$pid" "$comm" "$etimes" "$ancestor" "$args"
	else
		kill -TERM "$pid" 2>/dev/null && reaped=$((reaped + 1))
		printf 'reaped pid=%s comm=%s age=%ss agent=%s cmd=%s\n' "$pid" "$comm" "$etimes" "$ancestor" "$args"
	fi
done < <(ps -eo pid=,etimes=,comm= --user "$(id -u)" 2>/dev/null | tr -s ' ' | sed 's/^ //')

[ "$DRY_RUN" = 1 ] || [ "$reaped" -eq 0 ] || echo "reaped $reaped abandoned search process(es)"
exit 0
