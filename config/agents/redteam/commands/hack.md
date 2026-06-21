---
description: "Security review: injection, auth bypass, secrets, trust boundaries"
argument-hint: '<what to hack> [quick|2 models] [vs main] [--wait|--background]'
allowed-tools: Bash(node:*), Bash(git:*), Read, Glob, Grep, AskUserQuestion
---

Security-only review. Read-only. Same execution rules as review.

**Execution:** `docs/execution.md` — do not poll. Strip `--wait`/`--background` before `panel.mjs`.

Foreground:
```bash
node "${CLAUDE_PLUGIN_ROOT}/scripts/panel.mjs" --mode security --focus "security bugs ONLY: injection, auth/authorization bypass, secret/credential exposure, path traversal, unsafe deserialization, SSRF, unvalidated input reaching a sink" [flags]
```

Background: same with `run_in_background: true`. Do not poll.
