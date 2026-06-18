---
name: dispatching-parallel-agents
description: Use when 2+ independent tasks, failures, or path-scoped investigations can run without shared state, shared files, or sequential dependency.
---

# Dispatching Parallel Agents

Dispatch one agent per independent problem domain. Keep shared state with the
coordinator.

Purpose: reduce wall-clock time without losing ownership boundaries.
Consumer: agents coordinating multiple test failures, validator failures,
subsystem investigations, or path-scoped implementation lanes.
Failure consequence: agents edit the same files, duplicate investigation, hide
validator debt, or return incompatible fixes.
Falsifier: one agent can resolve every failure with less context and no more
wall-clock time than parallel lanes.

## Use

Use when all are true:

- 2+ failures or tasks exist.
- Each lane has distinct files, subsystem, or failure class.
- One lane's result is not needed before another starts.
- Shared files can stay with the coordinator or one named owner.

Do not use when failures likely share one root cause, need whole-system tracing,
or require the same resource/file.

## Split

- By path: one test file, package, service, or doc tree per agent.
- By failure class: parser/syntax, mechanical formatting, policy contract,
  runtime bug.
- By subsystem: API, worker, database, UI, deploy.

Shared files stay with the coordinator unless one agent explicitly owns them:
`package.json`, lockfiles, root lint config, root agent docs, CI/GitOps entry
points, generated allow-lists.

## Collision Control

Before dispatch, assign each lane:

- Owned paths: files/directories the agent may edit.
- Read-only paths: context the agent may inspect but not edit.
- Artifact prefix: unique report/temp path prefix, e.g.
  `/tmp/agent-<lane>-<timestamp>` or `.agent-work/<lane>/`.
- Forbidden shared paths: files owned by coordinator or another lane.

Agents must not write generic names like `/tmp/report.md`, `/tmp/diff.patch`,
`notes.md`, or `review.md`. Include lane id, task id, or timestamp in every
scratch/report path.

If two lanes need the same file, do not run them in parallel. Serialize them or
make one coordinator-owned edit after both investigations return.

## Prompt Contract

Each subagent prompt must include:

- Scope: exact files, commands, logs, or subsystem.
- Goal: observable pass/fail condition.
- Constraints: allowed edits and forbidden paths.
- Unique artifact/report path prefix.
- Evidence: current failure output or reproduction command.
- Return shape: root cause, files changed, commands run with results, remaining
  failures outside scope.

Do not ask a subagent to "fix all tests" or infer ownership from repository
context. Give the lane and stop rule.

## Validator Lanes

Order matters when validators fail:

1. Syntax/parser failures first; broken input blocks classification.
2. Mechanical formatting/lint debt next; prefer formatter-safe rewrites.
3. Policy failures last; fix contract or record bounded migration work.

New ignores, allow-list entries, disabled rules, or skipped validators need path,
owner, removal condition, failure consequence, and falsifier.

## Integration

After agents return:

1. Read every summary.
2. Check file overlap and shared-state changes.
3. Inspect diffs before trusting results.
4. Run the narrow lane commands again if output is stale or incomplete.
5. Run the integration command that proves the combined change.

Do not report completion from subagent summaries alone.
