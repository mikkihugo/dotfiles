#!@bash@
# shellcheck shell=bash disable=SC1008,SC2239
# Coordination tier is live (repo-memory 0.5.2 with coordination_identity +
# coordination_sweep): the sweep uses the atomic server-side coordination
# path instead of the legacy swarm_bus_* fallback.
export REPO_MEMORY_COORDINATION_BUS=1
exec @node@ /home/mhugo/.codex/hooks/coordination-mailbox-sweep.mjs "${1:-codex}" "${2:-UserPromptSubmit}"
