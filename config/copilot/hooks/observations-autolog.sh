#!@bash@
# shellcheck shell=bash disable=SC1008,SC2239
# Autolog: drain session observations/ideas into repo_memory at agentStop.
# Reads ~/.agent-work/observations/copilot-<sessionId>.md and retains each
# entry with kind:observation (no OBSERVATIONS.md trail).
exec @node@ /home/mhugo/.dotfiles/config/kimi-code/hooks/observations-autolog.mjs copilot "${2:-agentStop}"
