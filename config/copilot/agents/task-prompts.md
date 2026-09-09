# task-tool prompt templates

The `task` tool exposes built-in agent types (`explore`, `task`,
`general-purpose`, `rubber-duck`, `code-review`, `research`,
`security-review`) whose **system prompts live inside the Copilot CLI
binary and are not user-editable**. The `prompt` field passed to the
`task` tool is a *per-invocation scope brief*, not an agent
redefinition. These templates are the scope briefs that actually
produce useful output at the `auto-deepseek-fast` /
`auto-minimax` tier on this devbox.

## Why these exist

A whole-repo "find bugs in X" or "review this whole repo" brief
returns 0 turns / 0 findings from the built-in agent types — they are
tuned for diff-shaped work (`/security-review` and `/review` slash
commands). The templates below are scoped to one file or one function
so the cheap-tier agents have a tractable problem.

## Templates

### 1. Security review of one function

```
agent_type: security-review
model: auto-deepseek-fast

You are auditing ONE specific function for exploitable security bugs.
Scope: <REPO_PATH>/<FILE_PATH>, function <FN_NAME> (line <N>-<M>).

Context: <why this function is interesting — e.g. "I am investigating
whether Command::new(caller_supplied_args) can reach a shell>. The
surrounding bash script has <known_mitigation>.

Tasks:
1. Read the function and its callers (trace backward from <FN_NAME>).
2. For each caller, classify the argv: static-literal vs runtime-built
   vs user-supplied.
3. Identify any code path where untrusted input reaches
   Command::args() / spawn / exec without strict validation.
4. Confirm or refute: is the bash-side validation sufficient? Cite
   file:line for the validation check.

Output: a markdown table | # | Severity | File:Line | Finding |
Confidence |. Then a one-paragraph summary of what you inspected.

DO NOT modify any files. DO NOT review unrelated files. Read-only.
```

### 2. Code review of one diff (whole file or patch)

```
agent_type: code-review
model: auto-deepseek-fast

You are reviewing the diff below for logic errors, panics, races,
deadlocks, data loss, and wrong contracts. Skip style and perf.

Diff to review:
<PASTE_DIFF_OR_FILE_PATH>

For each file in scope:
1. Read the whole file (not just the diff hunk).
2. Identify the contract change: what was the function/module
   responsible for before, and what is it responsible for now?
3. For each added or modified line, classify: bug fix / refactor /
   behavior change / test. Flag any behavior change that is not
   justified by the diff's stated intent.
4. For each new error-handling block: is the error classifiable,
   recoverable, or terminal? Are unwrap()/expect()/panic!()
   reachable from a public API path?

Output: a markdown table | # | Severity | File:Line | Bug | Repro
hint | Confidence |. Then a short prose summary.

If the diff touches <X cross-cutting concern — locking, IPC, env
mutation, persistence>, do an extra pass on that concern.

DO NOT modify any files.
```

### 3. Source-tracing a symbol

```
agent_type: explore
model: auto-fast

Find every definition and every call site of `<SYMBOL>` in
<REPO_PATH>.

Do not paraphrase. Output a markdown table:

| Hop | Kind | File:Line | Snippet |
|-----|------|-----------|---------|

Where Kind is one of: `definition`, `re-export`, `wrapper`, `caller`,
`test`. Walk the chain until you reach the entry point (CLI command,
public API, IPC handler, HTTP route).

If the symbol does not exist in the repo, say so plainly. Do not
propose alternates.
```

### 4. Whole-repo audit (only for general-purpose or task types)

```
agent_type: general-purpose
model: auto-minimax

You are doing a structured read-only audit of <REPO_PATH> for
<BUG_CLASS>.

Constraints:
- Read-only. Do not modify any files.
- Do not use web tools.
- Cite file:line for every finding.
- Confidence ≥ 7/10 to report.

Phase 1 — inventory: list the top-level directories and the crate
names (if Rust). Pick the 3-5 most likely surfaces for <BUG_CLASS>.

Phase 2 — per-surface read: for each surface picked in phase 1, read
the public API and the 2-3 largest files. Note any anomaly that
matches <BUG_CLASS>.

Phase 3 — synthesize: report findings with file:line, severity, and
confidence. If you find nothing, say so explicitly and explain what
you checked.

Output format: a markdown table | # | Severity | File:Line | Finding
| Confidence | followed by a prose summary of the phases.
```

Use the general-purpose / task agent types (with MiniMax-M3) for
whole-repo audits — the cheaper code-review / security-review types
will return 0 turns on this scope. Even with general-purpose, expect
to split a repo into 3-5 surface-scoped dispatches in parallel rather
than one whole-repo pass.

## Dispatch checklist (every time)

- [ ] `agent_type` is one of the 7 supported by the `task` tool
      (`explore | task | general-purpose | rubber-duck | code-review |
      research | security-review`); not a `/subagents` config slot.
- [ ] `model` is set explicitly per the devbox verified-lineage table
      (`auto-minimax`, `auto-glm`, `auto-fast`, `auto-deepseek-fast`).
- [ ] `prompt` names the file path (or function + line range), the
      investigation angle, and the output format.
- [ ] Confidence threshold is appropriate for the task shape (≥ 7/10
      for review; lower acceptable for exploration).
- [ ] Read-only is stated explicitly when it matters.
