---
name: subagent-driven-development
description: Use when executing a written implementation plan through independent task lanes with implementer, review, fix, and final integration gates.
---

# Subagent-Driven Development

Execute a written plan with one focused implementer subagent per task, one
review gate per task, and one final branch review.

Purpose: keep the main agent as coordinator while isolated agents implement and
review bounded work.
Consumer: agents executing multi-task implementation plans with subagent support.
Failure consequence: task context leaks across lanes, review gaps ship, or
subagents edit shared files without ownership.
Falsifier: inline execution completes the same plan faster with equal review
quality and less context load.

## Use

Use when:

- A written plan exists.
- Tasks are mostly independent or can be serialized by dependency.
- Subagent support is available.
- Review gates matter.

Use `executing-plans` when subagents are unavailable or the plan is small enough
for inline execution. Use `dispatching-parallel-agents` for ad hoc independent
failures without a full plan.

## Flow

1. Read plan once. Record global constraints and shared-file owners.
2. Verify the plan is status-readable: plan header has `Status:`, `Owner:`,
   `Last verified:`, `Source:`, and `Canonical issue/ADR/spec:`; each task has
   `Status:`, `Proof:`, and `Blocker:`.
3. If the plan lacks status fields but is otherwise clear, normalize it before
   dispatch.
4. Preflight contradictions: task conflicts, missing dependencies, or plan text
   that mandates a review defect. Ask once if blocked.
5. For each task:
   - set task `Status: active` before dispatch;
   - dispatch implementer with only its task, global constraints, allowed paths,
     forbidden paths, unique artifact prefix, test commands, and stop rule;
   - require status: `DONE`, `DONE_WITH_CONCERNS`, `NEEDS_CONTEXT`, or `BLOCKED`;
   - inspect diff and reported tests;
   - dispatch reviewer with task requirements and diff/package;
   - fix Critical/Important findings, then re-review;
   - update task `Proof:` with command, trace, commit, PR, or file path;
   - mark task `Status: implemented` only after clean spec and quality review.
6. If a task blocks, set `Status: blocked` and write the concrete `Blocker:`.
7. After all tasks, run final branch review.
8. Update plan-level `Status:` and `Last verified:` before completion.
9. Run markdownlint for the plan file when available.
10. Use `finishing-a-development-branch`.

## Prompt Contract

Implementer prompt:

- Task scope and exact files.
- PDD contract: purpose, consumer, contract, failureBoundary, evidence,
  falsifier, nonGoals, invariants, assumptions.
- Global constraints copied from plan.
- Allowed edits and forbidden shared files.
- Unique task artifact prefix, e.g. `.agent-work/task-03/` or
  `/tmp/<repo>-task-03-<timestamp>/`.
- Required tests/verification commands.
- Commit/report expectation.
- Required plan update: task `Status:`, `Proof:`, and `Blocker:`.
- Stop rule for ambiguity, missing context, or plan conflict.

Reviewer prompt:

- Task requirements.
- Diff/package path or exact diff source.
- Unique review artifact path.
- Tests already run.
- Required verdicts: spec compliance and code quality.
- No pre-judged findings. Do not tell reviewer what not to flag.

## Status Handling

- `DONE`: review it.
- `DONE_WITH_CONCERNS`: read concerns; resolve correctness/scope doubts before
  review.
- `NEEDS_CONTEXT`: provide missing context and re-dispatch.
- `BLOCKED`: change context, model, task split, or plan. Do not retry unchanged.
  Record the blocker in the plan.

## Boundaries

- Main agent owns plan context, shared files, branch state, and final claim.
- Subagents own only assigned paths.
- No generic scratch/report paths. Every artifact path includes repo/task/lane
  identity.
- One fixer handles final-review findings as a batch.
- Subagent summaries are evidence, not completion proof. Verify before claiming
  done.
- A checked task without `Proof:` is not complete.
