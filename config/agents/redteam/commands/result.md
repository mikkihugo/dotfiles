---
description: Show the stored final output for a finished redteam job
argument-hint: '[job-id] [--json]'
disable-model-invocation: true
allowed-tools: Bash(node:*)
---

!`node "${CLAUDE_PLUGIN_ROOT}/scripts/companion.mjs" result $ARGUMENTS`

Read [`skills/redteam-result-handling/SKILL.md`](../skills/redteam-result-handling/SKILL.md) and present findings per that contract.

Do not poll if the job is still running — tell the user to check `/redteam:status <job-id>` later.
