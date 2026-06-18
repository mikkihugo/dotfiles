---
name: existing-capability-first
description: Use when adding or changing a capability surface such as a public function, API, command, prompt, workflow, schema/helper, policy, or reusable instruction.
---

# Existing Capability First

Search before inventing. Reuse, extend, replace, or delete existing capability
before adding another home for the same concept.

Purpose: keep systems coherent instead of accumulating parallel surfaces.
Consumer: agents adding or changing reusable behavior, APIs, commands, prompts,
workflows, policies, schemas, or helpers.
Failure consequence: duplicate capability diverges; callers pick different
paths; old bugs survive because the new surface bypasses rather than fixes them.
Falsifier: the change is pure formatting, pure refactor, or test-only work that
does not alter a contract or add a reusable surface.

## Trigger

Use when a diff adds or changes:

- public function, class, module, route, command, or tool
- prompt template, skill, workflow, policy, or agent instruction
- database/schema/helper surface
- exported config, integration boundary, or decision rule

Skip when no behavior or contract surface changes.

## Search Order

Search in this order, using repository-native tools first:

1. Exported names, type names, route names, command names.
2. Tool surfaces, prompt templates, skills, workflows, and agent docs.
3. Existing helpers, schemas, migrations, fixtures, and policy scripts.
4. Tests and regression fixtures.
5. ADRs, specs, runbooks, and migration history.
6. Stale or deprecated implementations that should be deleted or marked
   non-authoritative.

Record search keys and nearest artifact. If none exists, say `none` plus the
reason existing surfaces cannot satisfy the PDD contract.

## Decision

- Equivalent exists: reuse or extend it. Update its purpose/consumer contract if
  the contract changes.
- Similar but obsolete exists: replace and delete, or mark non-authoritative with
  a removal path.
- None exists: add the smallest new surface and state why reuse would fail.

Do not stop at shallow name search in large repos. Search by failure class,
consumer, and data shape too.
