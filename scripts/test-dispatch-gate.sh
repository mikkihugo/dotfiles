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
trap 'rm -r -- "$state" 2>/dev/null' EXIT
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

if ((failures > 0)); then
	printf '%s dispatch-gate failure(s)\n' "$failures" >&2
	exit 1
fi
echo "dispatch-gate contract holds"
