#!@bash@
# shellcheck shell=bash disable=SC1008,SC2239
exec @node@ /home/mhugo/.codex/hooks/coordination-mailbox-sweep.mjs copilot "${1:-UserPromptSubmit}"
