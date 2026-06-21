---
description: Cancel an active background redteam panel job
argument-hint: '[job-id]'
disable-model-invocation: true
allowed-tools: Bash(node:*)
---

!`node "${CLAUDE_PLUGIN_ROOT}/scripts/companion.mjs" cancel $ARGUMENTS`

Present the command output. Job id comes from stderr at panel start (`redteam: job id = …`) or `/redteam:status`.
