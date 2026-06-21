---
description: "Architecture lane review: ADRs, system design, route choices, and implementation shape"
argument-hint: '<doc or pasted design> [quick|2 models] [--lane-planner-model provider/model] [--wait|--background]'
allowed-tools: Bash(node:*), Bash(git:*), Read, Glob, Grep, AskUserQuestion
---

Review an architecture or design choice through the bench-backed architect lane.
Read-only. Use `/redteam:plan` for execution sequencing and `/redteam:review`
for code diffs.

Substrate + models: `docs/orchestration.md`, `docs/lineages.md`, `models.json`.
If `REDTEAM_LANE_PLANNER_MODEL` is set, the planner may rank only eligible
bench candidates. Pass `--lane-planner-model provider/model` to select a planner
for this run, or `--no-lane-planner` for deterministic bench score order.

**Execution:** `docs/execution.md` — do not poll. Strip `--wait`/`--background`
before `panel.mjs`.

Foreground:
```bash
node "${CLAUDE_PLUGIN_ROOT}/scripts/panel.mjs" --mode decision --lane architect [flags]
```

Background:
```typescript
Bash({ command: `node "${CLAUDE_PLUGIN_ROOT}/scripts/panel.mjs" --mode decision --lane architect [flags]`, description: "Redteam architect review", run_in_background: true })
```

Do not poll. Present per `skills/redteam-result-handling/SKILL.md` — then STOP;
ask before fixing.
