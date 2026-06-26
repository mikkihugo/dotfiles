---
name: redteam-result-handling
description: Internal guidance for presenting redteam panel JSON back to the user
user-invocable: false
---

# Redteam Result Handling

When presenting review/decision/hack/ultrareview output:

- Present `summary` first, then findings ordered by severity (critical → high → medium → low).
- Use file paths and line numbers exactly as reported.
- Preserve confidence scores and lineage attribution when present.
- If verdict is `approve` with no material findings, say so briefly.
- If the harness returned `needs-attention`, treat findings as blocking until addressed or explicitly accepted.

## Read-only contract (CRITICAL)

- Redteam is **read-only**. After presenting findings, **STOP**.
- Do **not** fix issues in the same turn unless the user explicitly asked you to implement fixes **after** seeing results.
- Ask which findings to address before editing code — same discipline as Codex review output.

## Background jobs

- Use `/redteam:status` to check progress — **never poll** results dirs or loop on `BashOutput`.
- When a background job completes, use `/redteam:result <job-id>` or the notification payload, then apply this skill.

## Failures

- If result is missing or parse failed, show the companion message and stop — do not invent findings.
- If setup is not ready, direct to `/redteam:setup`.
