---
description: Show configured provider health, live catalog reachability, and bench evidence
argument-hint: '[--json] [--no-live] [--timeout-ms <ms>]'
disable-model-invocation: true
allowed-tools: Bash(node:*)
---

Report provider status without invoking review models. By default this checks
configured provider `/models` catalogs, declared aliases, lineage coverage, and
bench pass/fail counts. Use `--no-live` for a config + bench only view. Use
`--timeout-ms` to bound each live catalog request.

!`node "${CLAUDE_PLUGIN_ROOT}/scripts/companion.mjs" provider-status $ARGUMENTS`

If any provider shows `missing-key`, `missing-config`, `missing-catalog`, or
`error`, report that explicitly before suggesting review/bench runs.
