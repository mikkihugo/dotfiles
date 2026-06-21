---
description: "Benchmark model lanes and merge model-bench.json evidence"
argument-hint: '[--lanes scout,review,architect] [--dry-run|--run] [--write] [--reset]'
disable-model-invocation: true
allowed-tools: Bash(node:*)
---

Run lane benchmarking for redteam routing.

Default is dry-run planning: it discovers configured live aliases and shows lane
candidates without calling models. Use `--run --write` to smoke-test exact
models and merge those lanes into `model-bench.json`. Use `--reset --write`
only when intentionally replacing the whole bench artifact.

```bash
node "${CLAUDE_PLUGIN_ROOT}/scripts/lane-bench.mjs" $ARGUMENTS
```

Bash({ command: `node "${CLAUDE_PLUGIN_ROOT}/scripts/lane-bench.mjs" $ARGUMENTS`, description: "Redteam lane bench", run_in_background: true })
