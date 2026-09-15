#!@bash@
# shellcheck shell=bash disable=SC1008,SC2239
# Stop: keep the turn open while a genuinely actionable coordination-mailbox
# message (type "question" or "blocker") sits unacked. Kimi-contract port of
# ~/.grok/hooks/bin/stop-actionable.sh, which is itself a grok-native wrap of
# the Claude helper stop-continue-if-actionable.mjs.
#
# Contract translation, kept in this thin wrapper on purpose:
#   - The helper emits Claude/grok shape {"decision":"block","reason"} on
#     stdout with exit 0. Kimi's Stop hook blocks by printing the reason to
#     stderr and exiting 2 ("a message can be appended to let the model
#     continue"). Empty stdout + exit 0 = allow, in both contracts.
#   - Every failure path must allow the stop (fail-open): a malformed hook
#     must never become a permanent block. The helper already fail-opens
#     internally; the `|| exit 0` guards here cover spawn/jq failures.
#
# Identity note: the helper derives its sweep identity from the stdin
# payload's session_id with a hardcoded "claude" client label (that is how
# the grok wrapper runs it too). Per-session ids keep state files distinct;
# only the sweep identity label reads "claude", which affects nothing except
# which cursor file the poll advances.
set -u
out=$(@node@ "${HOME}/.claude/hooks/stop-continue-if-actionable.mjs") || exit 0
[ -z "$out" ] && exit 0
reason=$(printf '%s' "$out" | jq -r 'select(type=="object" and .decision=="block") | .reason // empty' 2>/dev/null) || exit 0
[ -z "$reason" ] && exit 0
printf '%s\n' "$reason" >&2
exit 2
