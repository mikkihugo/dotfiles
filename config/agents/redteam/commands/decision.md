---
description: "Decision/ADR review: architecture or approach choice"
argument-hint: '<doc or pasted decision> [quick|2 models] [--wait|--background]'
allowed-tools: Bash(node:*), Bash(git:*), Read, Glob, Grep, AskUserQuestion
---

Review a decision — ADR, architecture choice, or approach. Not a code diff and not an implementation plan. Read-only.

Use this when the user asks whether a chosen option is right, under-analyzed, beaten by an alternative, or unsafe to execute. Use `/redteam:plan` for implementation/execution plans.

Substrate + models: `docs/orchestration.md`, `docs/lineages.md`, `models.json`.

**Execution:** `docs/execution.md` — do not poll. Strip `--wait`/`--background` before `panel.mjs`.

Foreground:
```bash
node "${CLAUDE_PLUGIN_ROOT}/scripts/panel.mjs" --mode decision [flags]
```

Background:
```typescript
Bash({ command: `node "${CLAUDE_PLUGIN_ROOT}/scripts/panel.mjs" --mode decision [flags]`, description: "Redteam decision review", run_in_background: true })
```

Do not poll. Present per `skills/redteam-result-handling/SKILL.md` — then STOP; ask before fixing.
