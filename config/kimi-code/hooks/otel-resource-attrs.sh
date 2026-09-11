#!/usr/bin/env bash
# config/kimi-code/hooks/otel-resource-attrs.sh — SessionStart hook for kimi-code
#
# Purpose: at session boot, append per-session keys to OTEL_RESOURCE_ATTRIBUTES
# so the in-cluster OTel collector receives spans tagged with the right
# identity. Also write a JSON sidecar at
#   ${XDG_RUNTIME_DIR:-/run/user/$UID}/kimi-otel/${session_id}.json
# so observability lookup tools can resolve workspace + lane from a session_id
# without parsing wire.jsonl.
#
# Consumer: any observability-mcp tool that needs to join Loki / OTel data
# to a specific kimi-code session.
#
# Contract (idempotent):
#   - Re-running overwrites the JSON sidecar.
#   - OTEL_RESOURCE_ATTRIBUTES session keys are deduplicated (any prior
#     kimi.session.* / kimi.workspace.* / kimi.lane.* / kimi.principal.* /
#     kimi.model.* / kimi.parent_agent.* entries are stripped before appending).
#
# Input (kimi-code delivers hook input as JSON on stdin — runHook.ts:132):
#   hook_event_name, session_id, cwd, source, model, profile.
# Env overrides (win over stdin when set):
#   KIMI_SESSION_ID, KIMI_WORKSPACE, KIMI_LANE, KIMI_PRINCIPAL,
#   KIMI_MODEL, KIMI_PARENT_AGENT.
#
# Falsifier: a kimi-code session with no JSON sidecar means OTEL spans
# lack session_id / workspace / lane labels, so observability lookup
# falls back to the slower wire.jsonl grep.

set -euo pipefail

# Read stdin only when piped (kimi-code pipes JSON; manual runs have /dev/null).
input=""
if [[ ! -t 0 ]]; then
	input="$(cat)"
fi

# Pull one field from stdin JSON via jq, empty string if missing or jq absent.
# kimi-code bundles jq; absence is treated as "no input" rather than fatal.
json_field() {
	local key="$1"
	if [[ -n "$input" ]] && command -v jq >/dev/null 2>&1; then
		printf '%s' "$input" | jq -r --arg k "$key" '.[$k] // empty'
	fi
}

# env > stdin > synthetic fallback for each session field.
SESSION_ID="${KIMI_SESSION_ID:-$(json_field session_id)}"
[[ -n "$SESSION_ID" ]] || SESSION_ID="$(hostname)-$$-$(date +%s%N)"

WORKSPACE="${KIMI_WORKSPACE:-$(json_field cwd)}"
[[ -n "$WORKSPACE" ]] || WORKSPACE="$(pwd 2>/dev/null || echo unknown)"

MODEL="${KIMI_MODEL:-$(json_field model)}"
[[ -n "$MODEL" ]] || MODEL="unknown"

LANE="${KIMI_LANE:-}"
PRINCIPAL="${KIMI_PRINCIPAL:-${USER:-unknown}@$(hostname)}"
PARENT_AGENT="${KIMI_PARENT_AGENT:-main}"

# Strip any prior session-scoped keys from the static defaults, then append
# the live ones. Static defaults live in ~/.kimi-code/otel-resource-attrs.env.
defaults_file="${HOME}/.kimi-code/otel-resource-attrs.env"
if [[ -f "$defaults_file" ]]; then
	base=$(grep -v '^#' "$defaults_file" | grep -v '^$' | paste -sd, -)
else
	base="kimi.client.name=kimi-code"
fi

stripped=$(printf '%s' "$base" | tr ',' '\n' | grep -Ev '^kimi\.(session|workspace|lane|principal|model|parent_agent)\.' | paste -sd, -)

session_keys="kimi.session.id=${SESSION_ID},kimi.workspace.path=${WORKSPACE},kimi.parent_agent=${PARENT_AGENT},kimi.principal=${PRINCIPAL},kimi.model=${MODEL}"
[[ -n "$LANE" ]] && session_keys+=",kimi.lane=${LANE}"

if [[ -n "$stripped" ]]; then
	export OTEL_RESOURCE_ATTRIBUTES="${stripped},${session_keys}"
else
	export OTEL_RESOURCE_ATTRIBUTES="${session_keys}"
fi

# Write the JSON sidecar atomically. Track boot_ts once so both sidecar
# and stdout log line carry the same value.
sidecar_dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/kimi-otel"
sidecar_path="${sidecar_dir}/${SESSION_ID}.json"
tmp_path="${sidecar_path}.tmp.$$"
boot_ts=$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ)

mkdir -p "$sidecar_dir"
if command -v jq >/dev/null 2>&1; then
	jq -n \
		--arg sid "$SESSION_ID" \
		--arg ws "$WORKSPACE" \
		--arg lane "$LANE" \
		--arg principal "$PRINCIPAL" \
		--arg model "$MODEL" \
		--arg parent "$PARENT_AGENT" \
		--arg ts "$boot_ts" \
		--arg otel_attrs "$OTEL_RESOURCE_ATTRIBUTES" \
		'{session_id:$sid, workspace:$ws, lane:$lane, principal:$principal, model:$model, parent_agent:$parent, boot_ts:$ts, otel_attrs:$otel_attrs}' \
		>"$tmp_path"
else
	printf '{"session_id":"%s","workspace":"%s","lane":"%s","principal":"%s","model":"%s","parent_agent":"%s","boot_ts":"%s","otel_attrs":"%s"}\n' \
		"$SESSION_ID" "$WORKSPACE" "$LANE" "$PRINCIPAL" "$MODEL" "$PARENT_AGENT" "$boot_ts" "$OTEL_RESOURCE_ATTRIBUTES" \
		>"$tmp_path"
fi
mv -f "$tmp_path" "$sidecar_path"

# Emit one structured log line for kimi-code's own logger; tagged for the
# observability lookup pipeline. stdout is captured by kimi-code, so this
# is the only signal that survives outside the sidecar file.
if command -v jq >/dev/null 2>&1; then
	jq -nc \
		--arg sid "$SESSION_ID" \
		--arg ws "$WORKSPACE" \
		--arg lane "$LANE" \
		--arg principal "$PRINCIPAL" \
		--arg ts "$boot_ts" \
		'{type:"otel.session_started", session_id:$sid, workspace:$ws, lane:$lane, principal:$principal, boot_ts:$ts}'
fi
