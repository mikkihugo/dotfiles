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
Falsifier: the failure source is already proven by reproducible evidence and a
minimal fix target is known.

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

Return to evidence.
