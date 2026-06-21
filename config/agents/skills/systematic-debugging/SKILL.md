---
name: systematic-debugging
description: Use when encountering a bug, test failure, production incident, unexpected behavior, performance issue, build failure, or integration failure before proposing fixes.
---

# Systematic Debugging

Find root cause before changing behavior.

Purpose: prevent symptom fixes and guesswork.
Consumer: agents diagnosing failures in code, tests, infra, builds, and runtime
systems.
Failure consequence: fixes mask the real cause, create regressions, or require
multiple failed attempts.

**Redteam forwarder:** Phase 1 (Root Cause Investigation): if 'similar bugs elsewhere' is suspected, run `/redteam:bughunt` for whole-tree discovery before narrowing scope. Use `/redteam:verify` on the proposed root cause to confirm it actually predicts the bug.
Falsifier: the failure source is already proven by reproducible evidence and a
minimal fix target is known.

## Compiler-Directed Fast Path

When the compiler/linter/type-checker output names the exact change needed
(API rename, missing import, type mismatch with a clear fix), skip Phases 1–3
and use this shortened loop:

1. Read the error. Confirm it specifies both the old and new form.
2. Search for all occurrences of the old form across the codebase.
3. Apply all fixes in one batch (sed, multi-file edit, or subagent).
4. Rebuild/check once. If new errors appear, classify each as compiler-directed
   (repeat fast path) or unknown (fall back to full Phase 1).

This fast path is NOT for:
- Linker errors (undefined symbol — root cause may be feature flags, platform)
- Runtime panics or test failures
- "Expected X found Y" where the fix involves design decisions
- Errors where the compiler suggests multiple possible fixes

PDD link: name the affected `consumer`, broken `contract` or
`failureBoundary`, current `evidence`, and `falsifier` before changing the
system.

## Rule

No fixes before root-cause investigation.

## Phase 1: Evidence

1. Read the full error, stack, status, event, or log.
2. Reproduce or define why reproduction is not possible.
3. Check recent changes.
4. Trace data/control flow backward from symptom to source.
5. In multi-component systems, inspect each boundary: input, output, config,
   identity, permissions, and state.

Do not propose a fix while the failing layer is still unknown.

## Phase 2: Pattern

Find a working nearby example or authoritative reference. Compare:

- inputs and assumptions
- config/env propagation
- permissions/identity
- lifecycle/order
- dependencies and versions

List the relevant difference before changing anything.

## Phase 3: Hypothesis

State one hypothesis:

`I think <cause> because <evidence>.`

Test one variable. If it fails, form a new hypothesis. Do not stack unrelated
changes.

If three fixes fail, stop and question the architecture or premise before trying
another.

## Phase 4: Fix

1. Create the smallest failing test, repro, or operational check.
2. Apply one fix at the root cause.
3. Verify the original symptom and relevant regression surface.
4. Use `verification-before-completion` before claiming status.

For code behavior changes, use `test-driven-development` unless the task is
explicitly operational/config-only.

## Red Flags

Stop when thinking:

- "Just try this."
- "Probably X."
- "Quick fix first."
- "Add several changes, then test."
- "I do not understand it, but this might work."
- "One more fix" after repeated failures.
- "The compiler said exactly what to change, I don't need to investigate." (use the compiler-directed fast path, don't skip the skill entirely)

Return to evidence.
