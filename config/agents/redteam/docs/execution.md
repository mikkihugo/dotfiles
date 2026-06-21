# Execution — foreground, background, do not poll (Claude reads this)

Redteam runs are **slow** (often 2–10+ minutes). Follow the same execution discipline as the Codex plugin: detach long work, never poll.

## Claude-side flags only

`--wait` and `--background` are for **you**, not `panel.mjs`. Strip them before the `node …/panel.mjs` command.

| Flag | Meaning |
|------|---------|
| `--wait` | Foreground. Do not ask. Block until the harness finishes. |
| `--background` | Background. Do not ask. Launch and end the turn. |

User says *"run it in the background"* → treat as `--background`. *"wait for results"* → `--wait`.

## When to recommend background

**Always background** (unless user said `--wait`):
- `/redteam:ultrareview`, `/redteam:bughunt`
- `--package audit`, `-n 3` or more
- `--verify` on a wide panel

**Recommend background** when any of:
- Default review (`-n 2`) on a non-trivial diff
- Decision review of a long doc (`--input` file > ~100 lines or large ADR)
- Diff touches more than ~2 files or looks directory-sized

**Foreground OK** when all of:
- `-n 1` quick pass
- Scoped diff is clearly tiny (≈1–2 files, small shortstat)
- User asked to wait or passed `--wait`

When unsure → **background**, not poll.

## Size check (before AskUserQuestion)

Same as Codex review:
- `git status --short --untracked-files=all`
- `git diff --shortstat` and `git diff --shortstat --cached`
- With `--base`: `git diff --shortstat <base>...HEAD`
- Untracked files count as reviewable work
- Only claim "nothing to review" when scope is actually empty

## AskUserQuestion (once)

Skip if `--wait` or `--background` already set.

Two options; put the recommended one first with `(Recommended)`:
- `Run in background`
- `Wait for results`

## Foreground flow

```bash
node "${CLAUDE_PLUGIN_ROOT}/scripts/panel.mjs" [panel flags…]
```

- Let the Bash call complete in this turn.
- Treat `=== REDTEAM EXIT status=<code> ===` on stderr as the completion
  sentinel. When it appears, stop side discussion and report the result first.
- Parse the merged JSON from stdout.
- Present `summary` + each finding (`severity`, `title`, `body`, `file:line`).
- Do not fix issues in the same turn as the review (read-only).

## Background flow

```typescript
Bash({
  command: `node "${CLAUDE_PLUGIN_ROOT}/scripts/panel.mjs" [panel flags…]`,
  description: "Redteam panel",
  run_in_background: true,
})
```

Then tell the user the panel started in the background. Mention `/redteam:status` for progress, `/redteam:status <job-id> --wait` when the user wants to block for completion, and `/redteam:result <job-id>` when done. **End the turn.**

Job id is printed at start: `redteam: job id = <id>` (also in `/redteam:status`).
`/redteam:status --wait` has no default timeout: if the panel process is alive,
keep waiting. Use `--timeout-ms <ms>` only for an explicitly bounded wait. If
that bounded wait reports `Still running after ...`, treat it as an in-progress
state, not completion or failure.

## Do NOT poll

Never do any of these while a run is in flight:

- Loop on the results dir or per-lineage JSON files
- `tail -f`, repeated `Read` of `/tmp/redteam/…`
- `BashOutput` polling waiting for completion
- Repeated `/redteam:status` calls; use `/redteam:status <job-id> --wait`
- Re-run the same panel because it feels slow
- Pipe the panel through `tail` or `head` (buffers live output)

The harness notifies on completion. Foreground runs print
`=== REDTEAM EXIT status=<code> ===` when the process exits. When notified, use
`/redteam:result <job-id>` or read the completed Bash stdout — then present
findings per `skills/redteam-result-handling/SKILL.md`.

Mid-run progress (optional, only if the user explicitly asks): stderr at startup prints  
`redteam: results dir = /tmp/redteam/<session>-…/` — one-off peek is OK; **polling is not**.

## After completion

- Present findings; then STOP and ask which items to fix. Redteam never edits.
- Lean loop: 1–2 lineages → fix → review again — each round is a new invocation with the same execution rules.
