---
description: Review an implementation plan before execution
argument-hint: '--plan <file> | --input <plan-path> | --text <plan prose> [--focus <area>] [quick|audit] [--wait|--background]'
allowed-tools: Bash(node:*), Bash(git:*), Read, Glob, Grep, AskUserQuestion
---

Review an implementation plan adversarially, not code and not an ADR. Read-only.

Use this when the user asks whether a plan is grounded, executable, test-first, sequenced, or complete enough to run. Use `/redteam:decision` for architecture decisions and ADRs.

Substrate + models: `docs/orchestration.md`, `docs/lineages.md`, `models.json`.

**Execution:** `docs/execution.md` — do not poll. Strip `--wait`/`--background` before `panel.mjs`.

Prefer `--plan <file>` for a plan document; it implies `--mode plan` unless the user explicitly overrides mode.

Foreground:
```bash
node "${CLAUDE_PLUGIN_ROOT}/scripts/panel.mjs" --mode plan [flags]
```

Background:
```typescript
Bash({ command: `node "${CLAUDE_PLUGIN_ROOT}/scripts/panel.mjs" --mode plan [flags]`, description: "Redteam plan review", run_in_background: true })
```

Do not poll. Present per `skills/redteam-result-handling/SKILL.md` — then STOP; ask before fixing.
