#!@bash@
# shellcheck shell=bash disable=SC1008,SC2239
# Same tier as coordination-mailbox-sweep.sh. Both hooks read one mailbox, so
# they must agree on the wire: the sweep exports this flag, and a Stop hook left
# on the legacy swarm_bus tier keeps a second, per-bucket watermark that the
# coordination inbox never advances, re-surfacing messages it already drained.
export REPO_MEMORY_COORDINATION_BUS=1
exec @node@ /home/mhugo/.claude/hooks/stop-continue-if-actionable.mjs
