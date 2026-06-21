---
description: Codebase-wide bug hunt (scout + heavy deep-dive)
argument-hint: '[scope] [shallow|deep] [--wait|--background]'
allowed-tools: Bash(node:*), Bash(git:*), Read, Glob, Grep, AskUserQuestion
---

Whole-tree hunt. Always slow — **default to background** unless `--wait`.
Default scout is bounded: 3 scout models scan the candidate files, then heavy
review handles the selected hotspots. Use `--scout-count 2` or `--scout-models
a,b,c` to override. Default scout candidates are flash/M3 or roughly 20-200B;
smaller mechanical scouts are opt-in with `--scout-models`.

**Execution:** `docs/execution.md` — do not poll.

```typescript
Bash({ command: `node "${CLAUDE_PLUGIN_ROOT}/scripts/panel.mjs" --bughunt 5 [flags]`, description: "Redteam bughunt", run_in_background: true })
```

Do not poll. On notification, present findings.
