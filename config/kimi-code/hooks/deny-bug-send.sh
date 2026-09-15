#!/usr/bin/env bash
# PreToolUse: do not send bugs (send_feedback / tracker issue creation) unless
# the user asked. Kimi-contract port of ~/.grok/hooks/bin/deny-bug-send.sh
# (which is the grok side of the same rule; keep behavior in sync by hand).
#
# Contract differences vs the grok original, both deliberate:
#   - Deny shape: grok/claude emit {"decision":"deny","reason"}; Kimi blocks
#     via hookSpecificOutput.permissionDecision (same shape the
#     skills-gate-pretooluse hook already uses on this host).
#   - "Did the user ask" input: the grok payload carries lastUserPrompt; the
#     documented Kimi payload does not. We still read the same fields
#     defensively (.last_user_prompt // .lastUserPrompt // .prompt) so the
#     hook upgrades silently if Kimi ever forwards prompt text. When no
#     prompt field is present the check fails CLOSED (deny), exactly like the
#     grok original on a missing prompt: autonomous filing is the failure
#     mode; a false deny costs one turn, a false allow files junk.
#   - Matcher (in the [[hooks]] entry, not here) must name Kimi MCP tool
#     names: grok's send_feedback|use_tool names do not exist in Kimi, where
#     MCP tools are exposed individually (e.g. mcp__...forgejo_issue_create).
#
# Fail-open on parse errors (exit 0), matching the original.
set -uo pipefail
input=$(cat)
tool=$(printf '%s' "$input" | jq -r '.tool_name // .toolName // empty' 2>/dev/null) || exit 0
prompt=$(printf '%s' "$input" | jq -r '.last_user_prompt // .lastUserPrompt // .prompt // empty' 2>/dev/null) || true
lc=$(printf '%s' "$tool" | tr '[:upper:]' '[:lower:]')
args=$(printf '%s' "$input" | jq -c '.tool_input // .toolInput // {}' 2>/dev/null) || args='{}'

asked=0
printf '%s' "$prompt" | rg -qi 'file an issue|open an issue|send feedback|/feedback|create.*ticket' && asked=1

deny() {
	jq -nc --arg r "$1" \
		'{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
	exit 0
}

case "$lc" in
*send_feedback*)
	[ "$asked" -eq 1 ] || deny "Do not send_feedback unless the user asked to file feedback."
	;;
esac

if printf '%s' "$lc$args" | rg -qi 'forgejo_issue_create|create_issue|github.*issues'; then
	[ "$asked" -eq 1 ] || deny "Do not create tracker issues unless the user asked."
fi
exit 0
