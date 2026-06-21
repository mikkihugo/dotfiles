---
description: "Deep code review: multi-lens sweep, adversarial verification, synthesis"
argument-hint: '<what to review> [vs main] [verify?] [--wait|--background]'
allowed-tools: Bash(node:*), Bash(git:*), Read, Glob, Grep, AskUserQuestion
---

Deep multi-lens sweep. Always slow — **default to background** unless `--wait`.

**Execution:** `docs/execution.md` — do not poll. Strip `--wait`/`--background` before `panel.mjs`.

Unless user passed `--wait`, launch in background:
```typescript
Bash({ command: `node "${CLAUDE_PLUGIN_ROOT}/scripts/panel.mjs" --ultrareview [flags]`, description: "Redteam ultrareview", run_in_background: true })
```

Do not poll. On notification, present synthesized findings.
