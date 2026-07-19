#!@bash@
# shellcheck shell=bash disable=SC1008,SC2239
exec @node@ /home/mhugo/.codex/hooks/swarm-messages.mjs claude "${1:-UserPromptSubmit}"
