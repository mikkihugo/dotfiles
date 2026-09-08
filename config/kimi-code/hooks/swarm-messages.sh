#!@bash@
# shellcheck shell=bash disable=SC1008,SC2239
# Coordination tier is live (repo-memory 0.5.2 with coordination_identity +
# coordination_sweep, deployed 2026-09-08): the hook uses the atomic
# server-side sweep instead of the legacy swarm_bus_* dance.
export REPO_MEMORY_COORDINATION_BUS=1
exec @node@ /home/mhugo/.codex/hooks/coordination-mailbox-sweep.mjs kimi-code "${1:-UserPromptSubmit}"
