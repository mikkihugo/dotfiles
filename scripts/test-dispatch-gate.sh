#!/usr/bin/env bash
# Contract: the dispatch gate hands out one slot per acquire, refuses past the
# cap, keeps the documented tier plan, and never puts a worker on the
# orchestration-only upstream.
#
# Why this exists: the slot plan is the throttle that keeps parallel workers
# off one provider's rate limit. A silent drift between the plan, the gate and
# ~/.factory/AGENTS.md would put every worker back on a single upstream, which
# is the failure the gate was written for.
#
# Falsifier: a slot plan that maps a worker tier to custom:9Router-4
# (minimax-m3, reserved for orchestration), or a tier seat count other than
# 4 light / 4 medium / 12 heavy, or an `acquire` that succeeds past MAX_SLOTS.
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
gate="$root/scripts/dispatch-gate"
state="$(mktemp -d)"
reap_state="$(mktemp -d)"
trap 'rm -r -- "$state" "$reap_state" 2>/dev/null' EXIT
export DISPATCH_GATE_STATE="$state"

failures=0
check() {
	if [ "$2" = "$3" ]; then
		printf 'ok   %s\n' "$1"
	else
		printf 'FAIL %s: expected %q, got %q\n' "$1" "$2" "$3" >&2
		failures=$((failures + 1))
	fi
}

# Pretend every upstream is LIVE. `acquire` probes the router, and a test must
# not depend on the host router being up.
for n in 0 1 2 3 4 5 6 7; do printf 'live' >"$state/health.custom:9Router-$n"; done

out="$("$gate" acquire test-worker)"
check "acquire succeeds" 0 "$?"
slot="$(printf '%s' "$out" | sed -n 's/^slot=\([0-9]*\).*/\1/p')"
check "acquire prints a slot number" 1 "$slot"
check "slot 1 is the light tier" "custom:9Router-7" \
	"$(printf '%s' "$out" | sed -n 's/.*model=\([^ ]*\).*/\1/p')"

"$gate" status >/dev/null
check "status exits 0 while a slot is held" 0 "$?"

DISPATCH_GATE_MAX=1 "$gate" acquire second >/dev/null 2>&1
check "acquire past the cap exits 2" 2 "$?"

"$gate" release "$slot" >/dev/null
check "release exits 0" 0 "$?"
"$gate" status | grep -q '(no slots in use)'
check "status reports an empty ledger" 0 "$?"

# Fill every seat and read the plan back off the ledger.
for i in $(seq 1 20); do
	"$gate" acquire "worker-$i" >/dev/null || {
		printf 'FAIL could not acquire slot %s\n' "$i" >&2
		failures=$((failures + 1))
	}
done
models="$(cut -f4 "$state"/slot.* | awk '{print $2}')"
check "light tier holds 4 seats" 4 "$(printf '%s\n' "$models" | grep -cx 'custom:9Router-7')"
check "medium tier holds 4 seats" 4 "$(printf '%s\n' "$models" | grep -cx 'custom:9Router-6')"
check "heavy tier holds 12 seats" 12 "$(printf '%s\n' "$models" | grep -cx 'custom:9Router-5')"
check "the orchestration upstream is never a worker slot" 0 \
	"$(printf '%s\n' "$models" | grep -cx 'custom:9Router-4')"

"$gate" acquire one-too-many >/dev/null 2>&1
check "acquire with every seat taken exits 2" 2 "$?"

# Reap contract: a slot whose worker process is gone is reclaimed once the
# grace has passed, a slot inside the grace is kept, and a slot held without a
# session id is kept until the stale window. Separate state dir so these
# hand-written slots do not disturb the seat counts above.
#
# The "alive" session id is this script's own name: the gate matches it with
# `pgrep -f`, so the running test is the live worker. The other two ids are
# unique enough that nothing matches them.
dead_token="dispatch-gate-dead-$$-$(date +%s)"
grace_token="dispatch-gate-grace-$$-$(date +%s)"
live_token="test-dispatch-gate.sh"
now_s="$(date +%s)"

write_slot() {
	printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$now_s" "light custom:9Router-7" "$3" \
		>"$reap_state/slot.$1"
	touch -d "$4" "$reap_state/slot.$1"
}

write_slot 1 dead "$dead_token" '2 hours ago'
write_slot 2 grace "$grace_token" '1 minute ago'
write_slot 3 nosession - '2 hours ago'
write_slot 4 live "$live_token" '2 hours ago'

DISPATCH_GATE_STATE="$reap_state" DISPATCH_GATE_REAP_GRACE=3600 "$gate" status >/dev/null
check "a slot whose worker is gone is reaped" 0 "$([ -e "$reap_state/slot.1" ] && echo 1 || echo 0)"
check "a slot inside the grace is kept" 1 "$([ -e "$reap_state/slot.2" ] && echo 1 || echo 0)"
check "a slot without a session id is kept until the stale window" 1 \
	"$([ -e "$reap_state/slot.3" ] && echo 1 || echo 0)"
check "a slot whose worker is alive is kept" 1 \
	"$([ -e "$reap_state/slot.4" ] && echo 1 || echo 0)"

if ((failures > 0)); then
	printf '%s dispatch-gate failure(s)\n' "$failures" >&2
	exit 1
fi
echo "dispatch-gate contract holds"
