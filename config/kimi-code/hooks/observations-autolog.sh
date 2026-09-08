#!@bash@
# shellcheck shell=bash disable=SC1008,SC2239
# Autolog: drain session observations/ideas into repo_memory at turn end.
# Reads ~/.agent-work/observations/<client>-<session>.md and retains each
# entry with kind:observation (no OBSERVATIONS.md trail). Fires on Stop.
exec @node@ /home/mhugo/.dotfiles/config/kimi-code/hooks/observations-autolog.mjs kimi-code "${1:-Stop}"
