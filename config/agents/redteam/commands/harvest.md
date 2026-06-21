---
description: "Pattern harvest vs main: find good reusable code or operational patterns"
argument-hint: '[area or doc] [quick|2 models] [--base <ref>] [--wait|--background]'
allowed-tools: Bash(node:*), Bash(git:*), Read, Glob, Grep, AskUserQuestion
---

Harvest good patterns introduced relative to `main`. Read-only scan. Pass a later `--base <ref>` to override.

**Execution:** `docs/execution.md` — do not poll. `-n 1` quick harvest may foreground; default package → background.

```bash
node "${CLAUDE_PLUGIN_ROOT}/scripts/panel.mjs" --package harvest --base main [flags]
```

Or background with `run_in_background: true`. Do not poll.
