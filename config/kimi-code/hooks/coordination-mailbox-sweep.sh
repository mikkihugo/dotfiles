#!@bash@
# shellcheck shell=bash disable=SC1008,SC2239
# Coordination tier is live (repo-memory 0.5.2 with coordination_identity +
# coordination_sweep): the sweep uses the atomic server-side coordination
# path instead of the legacy swarm_bus_* fallback. Universal shim — pass
# client label as $1 (e.g. kimi-code, codex, claude, factory, copilot) and
# event name as $2 (UserPromptSubmit / SessionStart).
export REPO_MEMORY_COORDINATION_BUS=1
exec @node@ "$(dirname "$0")/coordination-mailbox-sweep.mjs" "${1:-kimi-code}" "${2:-UserPromptSubmit}"
