#!@bash@
# shellcheck shell=bash disable=SC1008,SC2239
# Autolog: drain session observations/ideas into repo_memory at turn end.
# Reads ~/.agent-work/observations/<client>-<session>.md and retains each
# entry with kind:observation (no OBSERVATIONS.md trail). Fires on Stop.
# Pass client label as $1 (kimi-code, codex, claude, factory, copilot)
# and event name as $2 (Stop / SessionEnd).
exec @node@ "$(dirname "$0")/observations-autolog.mjs" "${1:-kimi-code}" "${2:-Stop}"
