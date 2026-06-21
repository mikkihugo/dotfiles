---
name: executing-plans
description: Use when executing a written implementation plan inline in the current session with checkpoints and verification.
---

# Executing Plans

**Purpose:** Execute a written plan step-by-step with verification checkpoints when subagents are unavailable or the plan is small enough for inline execution.
**Consumer:** Main agent with no subagent access, or small plans where subagent dispatch overhead exceeds savings.
**Failure consequence:** Steps skipped, ordering broken, or verification missed because no external review gates the work; partial completion claimed as full.
**Falsifier:** The plan has fewer than 3 tasks, no shared state across steps, or no critical verification gate.

## Overview

Load plan, review critically, execute all tasks, report when complete.

**Announce at start:** "I'm using the executing-plans skill to implement this plan."

Use `subagent-driven-development` instead when a written plan needs per-task
implementer/reviewer subagents. Use this skill for inline plan execution.

## The Process

### Step 1: Load and Review Plan

1. Read plan file
2. Verify the plan has a status-readable header:
   `Status:`, `Owner:`, `Last verified:`, `Source:`, and
   `Canonical issue/ADR/spec:`.
3. Verify every executable task has `Status:`, `Proof:`, and `Blocker:`.
4. Review critically - identify any questions or concerns about the plan.
5. If the plan lacks status fields but is otherwise clear, normalize the plan
   before executing it.
6. If concerns remain: raise them with your human partner before starting.
7. If no concerns: create todos for the plan items and proceed.

### Step 2: Execute Tasks

For each task:

1. Mark task `Status: active`.
2. Follow each step exactly (plan has bite-sized steps)
3. Run verifications as specified
4. Update `Proof:` with the command, trace, commit, PR, or file path that proves
   the result.
5. Mark task `Status: implemented` only after proof exists.
6. If blocked, mark task `Status: blocked` and set `Blocker:` to the concrete
   failing command, missing input, or unresolved decision.

### Step 3: Complete Development

After all tasks complete and verified:

- Update plan-level `Status: implemented`.
- Update plan-level `Last verified: YYYY-MM-DD`.
- Ensure every `Done When` checkbox is checked or the plan remains non-final.
- Run markdownlint for the plan file if a markdown validator exists.
- Announce: "I'm using the finishing-a-development-branch skill to complete this work."
- **REQUIRED SUB-SKILL:** Use `finishing-a-development-branch`
- Follow that skill to verify tests, present options, execute choice

## When to Stop and Ask for Help

**STOP executing immediately when:**

- Hit a blocker (missing dependency, test fails, instruction unclear)
- Plan has critical gaps preventing starting
- Plan status fields are absent and cannot be normalized from context
- You don't understand an instruction
- Verification fails repeatedly

**Ask for clarification rather than guessing.**

## When to Revisit Earlier Steps

**Return to Review (Step 1) when:**

- Partner updates the plan based on your feedback
- Fundamental approach needs rethinking

**Don't force through blockers** - stop and ask.

## Remember

- Review plan critically first
- Follow plan steps exactly
- Don't skip verifications
- Keep `Status:`, `Proof:`, `Blocker:`, and `Last verified:` current
- Reference skills when plan says to
- Stop when blocked, don't guess
- Never start implementation on main/master branch without explicit user consent

## Integration

**Required workflow skills:**

- `using-git-worktrees` - Ensures isolated workspace (creates one or verifies existing)
- `writing-plans` - Creates the plan this skill executes
- `finishing-a-development-branch` - Complete development after all tasks
