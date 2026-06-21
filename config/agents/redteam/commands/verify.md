---
description: "Finding verification: refute reported bugs or validate a fix with adversarial reviewers"
argument-hint: '[--base <ref> | --text <finding-or-fix>] [--focus <area>] [quick|2 models] [--wait|--background]'
allowed-tools: Bash(node:*), Bash(git:*), Read, Glob, Grep, AskUserQuestion
---

Verify a finding or fix by asking a different lineage to refute it. Use this after redteam reports issues, after a fix, or when the user asks whether a reported bug is real. Read-only.

This is not the first-pass code review command. Use `/redteam:review` to find issues and `/redteam:verify` to kill false positives or check a fix.

Foreground:
```bash
node "${CLAUDE_PLUGIN_ROOT}/scripts/panel.mjs" --verify [flags]
```

Background:
```typescript
Bash({ command: `node "${CLAUDE_PLUGIN_ROOT}/scripts/panel.mjs" --verify [flags]`, description: "Redteam verify", run_in_background: true })
```

Do not poll. Present per `skills/redteam-result-handling/SKILL.md` — then STOP.
