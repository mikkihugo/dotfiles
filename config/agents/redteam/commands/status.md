---
description: Show active and recent redteam panel jobs for this repository
argument-hint: '[job-id] [--wait] [--timeout-ms <ms>] [--poll-interval-ms <ms>] [--json]'
disable-model-invocation: true
allowed-tools: Bash(node:*)
---

!`node "${CLAUDE_PLUGIN_ROOT}/scripts/companion.mjs" status $ARGUMENTS`

`--wait` blocks until the selected job, or all current-session active jobs, stop
running. It has no default timeout: if the job is alive, keep waiting. Use
`--timeout-ms <ms>` only when the user explicitly wants a bounded wait. If that
explicit timeout expires and the job is still running, say it is still running;
do not summarize findings, claim failure, or rerun the panel.

If the user did not pass a job ID:
- Render the output as a compact Markdown table (the companion already formats one).
- Do not add extra prose beyond a one-line intro if needed.

If the user passed a job ID:
- Present the full command output.
- Preserve the `Recent trace` block if present; it is the supported view of
  live model/tool progress.
- If status is `completed`, mention `/redteam:result <job-id>`.
- If status is `running`, mention `/redteam:cancel <job-id>` — do not poll.
- If output says `Still running after ...`, report that state exactly and stop.
