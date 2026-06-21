---
description: "Code/diff review: adversarial review of a change (default: stratified panel of 2 lineages)"
argument-hint: '<what to review> [quick|2 models|audit] [vs main] [verify?] [--wait|--background]'
allowed-tools: Bash(node:*), Bash(git:*), Read, Glob, Grep, AskUserQuestion
---

Review a code change or diff adversarially to break confidence it should ship. **Read-only this turn.**

Core constraint:
- Do not fix issues, apply patches, or imply you will change code after presenting findings.
- After findings, **STOP** and ask which items the user wants fixed.

Translate user intent: `docs/orchestration.md`, `docs/lineages.md`, `models.json`. Resolve vague doc names with Glob/Grep → `--input`.

**Execution:** `docs/execution.md` — do not poll; background → `/redteam:status`. **Results:** `skills/redteam-result-handling/SKILL.md`.

Execution mode:
- `--wait` in raw args → foreground, no ask.
- `--background` in raw args → background, no ask.
- Else estimate scope (`git status`, `git diff --shortstat`); default `-n 2` on a real diff → recommend **background**. `-n 1` on ≈1–2 files → foreground OK.
- If asking: `AskUserQuestion` once — `Run in background (Recommended)` vs `Wait for results` (flip when tiny quick pass).

Foreground:
```bash
node "${CLAUDE_PLUGIN_ROOT}/scripts/panel.mjs" [your translated flags]
```
Wait for completion; present per `skills/redteam-result-handling/SKILL.md` — then STOP; ask before fixing.

Background:
```typescript
Bash({ command: `node "${CLAUDE_PLUGIN_ROOT}/scripts/panel.mjs" [flags]`, description: "Redteam review", run_in_background: true })
```
Do not poll. Tell user: started — check `/redteam:status`; when done `/redteam:result <job-id>`. End turn.
