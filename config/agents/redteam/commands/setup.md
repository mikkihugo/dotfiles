---
description: Check redteam harness readiness
argument-hint: '[--json]'
disable-model-invocation: true
allowed-tools: Bash(node:*)
---

!`node "${CLAUDE_PLUGIN_ROOT}/scripts/companion.mjs" setup $ARGUMENTS`

Present the setup output to the user. If not ready, say what failed before running review commands.
