#!/usr/bin/env bash
# Reap long-running Nix eval/dev-shell processes left behind when an agent CLI
# stopped waiting (same failure class as reap-abandoned-searches: yield ≠ kill).
#
# Targets only processes whose ancestry includes a known agent harness and whose
# age exceeds the threshold. Human login shells and CI (root) are never touched.
set -uo pipefail

THRESHOLD=${REAP_NIX_THRESHOLD_SECONDS:-1800}
DRY_RUN=${REAP_DRY_RUN:-0}
AGENT_COMMS='^(codex|claude|jcode|kimi-code|opencode|cursor)$'
NIX_COMMS='^(nix|nix-direnv)$'
SELF=$$

agent_ancestor() {
	local pid=$1 depth=0 ppid comm
	while [ "$pid" -gt 1 ] && [ "$depth" -lt 16 ]; do
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

looks_like_orphan_nix() {
	local args=$1
	case "$args" in
	*"print-dev-env"*) return 0 ;;
	*"nix develop"*) return 0 ;;
	*"nix eval"*) return 0 ;;
	*) return 1 ;;
	esac
}

reaped=0
while read -r pid etimes comm; do
	[ "$pid" != "$SELF" ] || continue
	[[ "$comm" =~ $NIX_COMMS ]] || continue
	[ "${etimes:-0}" -gt "$THRESHOLD" ] 2>/dev/null || continue

	ancestor=$(agent_ancestor "$pid")
	if [ -z "$ancestor" ]; then
		continue
	fi

	args=$(ps -o args= -p "$pid" 2>/dev/null | cut -c1-200)
	looks_like_orphan_nix "$args" || continue

	if [ "$DRY_RUN" = 1 ]; then
		printf 'WOULD-REAP pid=%s comm=%s age=%ss agent=%s cmd=%s\n' "$pid" "$comm" "$etimes" "$ancestor" "$args"
	else
		kill -TERM "$pid" 2>/dev/null && reaped=$((reaped + 1))
		printf 'reaped pid=%s comm=%s age=%ss agent=%s cmd=%s\n' "$pid" "$comm" "$etimes" "$ancestor" "$args"
	fi
done < <(ps -eo pid=,etimes=,comm= --user "$(id -u)" 2>/dev/null | tr -s ' ' | sed 's/^ //')

[ "$DRY_RUN" = 1 ] || [ "$reaped" -eq 0 ] || echo "reaped $reaped stale nix eval process(es)"
exit 0
