---
name: writing-plans
description: Use when you have a spec or requirements for a multi-step task, before touching code.
---

# Writing Plans

## Overview

Write comprehensive implementation plans assuming the engineer has zero context
for our codebase and questionable taste. Document everything they need to know:
which files to touch for each task, code, testing, docs they might need to
check, how to test it. Give them the whole plan as bite-sized tasks. DRY.
YAGNI. TDD. Frequent commits.

Assume they are a skilled developer, but know almost nothing about our toolset
or problem domain. Assume they don't know good test design very well.

**Announce at start:** "I'm using the writing-plans skill to create the implementation plan."

**Context:** If working in an isolated worktree, it should have been created via
`using-git-worktrees` at execution time.

**Save plans to:** `docs/plans/YYYY-MM-DD-<feature-name>.md`

- (User preferences for plan location override this default)

## Scope Check

If the spec covers multiple independent subsystems, it should have been broken
into sub-project specs during brainstorming. If it wasn't, suggest breaking
this into separate plans - one per subsystem. Each plan should produce working,
testable software on its own.

## File Structure

Before defining tasks, map out which files will be created or modified and what
each one is responsible for. This is where decomposition decisions get locked
in.

- Design units with clear boundaries and well-defined interfaces. Each file has
  one clear responsibility.
- Prefer smaller, focused files over large files that do too much.
- Files that change together should live together. Split by responsibility, not
  by technical layer.
- In existing codebases, follow established patterns. If the codebase uses large
  files, do not unilaterally restructure; if a file you modify has grown
  unwieldy, including a split in the plan is reasonable.

This structure informs the task decomposition. Each task should produce
self-contained changes that make sense independently.

## Task Right-Sizing

A task is the smallest unit that carries its own test cycle and is worth a
fresh reviewer's gate. When drawing task boundaries: fold setup,
configuration, scaffolding, and documentation steps into the task whose
deliverable needs them; split only where a reviewer could meaningfully
reject one task while approving its neighbor. Each task ends with an
independently testable deliverable.

## Bite-Sized Task Granularity

**Each step is one action (2-5 minutes):**

- "Write the failing test" - step.
- "Run it to make sure it fails" - step.
- "Implement the minimal code to make the test pass" - step.
- "Run the tests and make sure they pass" - step.
- "Commit" - step.

## Status Contract

Every plan in `docs/plans/` must be status-readable without interpreting prose.
Use a small metadata block after the worker note. Values are deliberately plain
text so markdownlint, grep, and simple scripts can validate them.

Allowed `Status:` values:

- `planned`
- `active`
- `blocked`
- `implemented`
- `superseded`

Required metadata keys:

- `Status:`
- `Owner:`
- `Last verified:`
- `Source:`
- `Canonical issue/ADR/spec:`

Use `none` when no canonical issue, ADR, or spec exists. Use `not verified`
only before any verification has run; update it with `YYYY-MM-DD` once evidence
exists.

## Plan Document Header

**Every plan MUST start with this header:**

```markdown
# [Feature Name] Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `subagent-driven-development` for subagent execution or `executing-plans` for inline execution. Steps use checkbox (`- [ ]`) syntax for tracking.

Status: planned
Owner: agent | human | mixed
Last verified: not verified
Source: spec path, prompt, `.sf` record, or manual
Canonical issue/ADR/spec: path-or-none

## Goal

[One sentence describing what this builds.]

## PDD Contract

- Purpose:
- Consumer:
- Contract:
- Failure boundary:
- Evidence:
- Falsifier:
- Non-goals:
- Invariants:
- Assumptions:

## Architecture

[2-3 sentences about approach.]

## Tech Stack

[Key technologies/libraries.]

## Done When

- [ ] Observable acceptance criterion with command, trace, commit, or file path.
- [ ] Another acceptance criterion.

## Global Constraints

[The spec's project-wide requirements — version floors, dependency limits,
naming and copy rules, platform requirements — one line each, with exact
values copied verbatim from the spec. Every task's requirements implicitly
include this section.]

---
```

## Task Structure

````markdown
### Task N: [Component Name]

Status: planned
Proof: not verified
Blocker: none

**Files:**

- Create: `exact/path/to/file.py`
- Modify: `exact/path/to/existing.py:123-145`
- Test: `tests/exact/path/to/test.py`

**Interfaces:**

- Consumes: [what this task uses from earlier tasks — exact signatures]
- Produces: [what later tasks rely on — exact function names, parameter
  and return types. A task's implementer sees only their own task; this
  block is how they learn the names and types neighboring tasks use.]

- [ ] **Step 1: Write the failing test**

```python
def test_specific_behavior():
    result = function(input)
    assert result == expected
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest tests/path/test.py::test_name -v`
Expected: FAIL with "function not defined"

- [ ] **Step 3: Write minimal implementation**

```python
def function(input):
    return expected
```

- [ ] **Step 4: Run test to verify it passes**

Run: `pytest tests/path/test.py::test_name -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add tests/path/test.py src/path/file.py
git commit -m "feat: add specific feature"
```
````

When execution updates a task, change `Status:` and `Proof:` near that task.
Valid task status values are `planned`, `active`, `blocked`, and
`implemented`. `Proof:` must name the command, trace, commit, PR, or file path
that proves the task status. If blocked, `Blocker:` must name the concrete
missing input or failing command.

## No Placeholders

Every step must contain the actual content an engineer needs. These are
**plan failures** - never write them:

- "TBD", "TODO", "implement later", "fill in details"
- "Add appropriate error handling" / "add validation" / "handle edge cases"
- "Write tests for the above" (without actual test code)
- "Similar to Task N" (repeat the code; the engineer may read tasks out of
  order)
- Steps that describe what to do without showing how (code blocks required for
  code steps)
- References to types, functions, or methods not defined in any task

## Remember

- Exact file paths always
- Complete code in every step — if a step changes code, show the code
- Exact commands with expected output
- Purpose contract, DRY, YAGNI, TDD, frequent commits
- Plan-level `Status:` plus task-level `Status:` / `Proof:` fields.
- Markdown that passes repo markdownlint without local rule disables.

## Self-Review

After writing the complete plan, look at the spec with fresh eyes and check the
plan against it. This is a checklist you run yourself, not a subagent dispatch.

**1. Spec coverage:** Skim each section/requirement in the spec. Can you point
to a task that implements it? List any gaps.

**2. Placeholder scan:** Search your plan for red flags from the "No
Placeholders" section above. Fix them.

**3. Type consistency:** Do the types, method signatures, and property names you
used in later tasks match what you defined in earlier tasks? A function called
`clearLayers()` in Task 3 but `clearFullLayers()` in Task 7 is a bug.

**4. Status readability:** Can `rg "^Status:|^Proof:|^- \\[[ xX]\\]"`
show the plan state? Does every task have `Status:`, `Proof:`, and `Blocker:`?

**5. Markdown lint:** Run the repo's markdownlint command, or a targeted
`markdownlint-cli2 <plan-file>` when no repo command exists. Fix warnings in the
plan instead of disabling rules.

If you find issues, fix them inline. No need to re-review; fix and move on. If
you find a spec requirement with no task, add the task.

## Execution Handoff

After saving the plan, offer execution choice:

Say:

Plan complete and saved to `docs/plans/<filename>.md`. Two execution options:

**1. Subagent-Driven** - Use one implementer and review gate per task

**2. Inline Execution** - Execute tasks in this session with checkpoints

Which approach?

**If Subagent-Driven chosen:**

- **REQUIRED SUB-SKILL:** Use `subagent-driven-development`
- Fresh subagent per task + two-stage review

**If Inline Execution chosen:**

- **REQUIRED SUB-SKILL:** Use `executing-plans`
- Batch execution with checkpoints for review
