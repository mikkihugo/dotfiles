---
name: purpose-first-tdd
description: Use when making or evaluating any behavior, plan, prompt, skill, code, test, or operational change that needs purpose, proof, consumer, or falsifier clarity.
---

# Purpose First TDD

<SUBAGENT-STOP>
If dispatched as a subagent for a specific task, skip this skill.
</SUBAGENT-STOP>

Purpose comes first. Tests are executable purpose. Code and instructions exist
to satisfy a real consumer.

**Redteam forwarder:** For falsifier validation, run `/redteam:verify` to cross-check that the falsifier actually catches the intended failure mode. A falsifier that never fires is not a real falsifier. For high-stakes contracts (security, billing, policy gates), use `/redteam:review` to validate the contract holds before declaring it done.

Purpose: make every change defensible before implementation.
Consumer: agents planning, implementing, reviewing, debugging, or editing
instructions.
Failure consequence: changes optimize activity instead of value; tests prove
implementation details instead of purpose; reviewers cannot tell what failure
means.
Falsifier: the change is purely cosmetic or self-contained with no behavior,
policy, proof, consumer, or public-contract impact.

## Contract

Before behavior changes, fill the canonical 9-field PDD contract:

- `purpose`: why this exists.
- `consumer`: who or what uses it.
- `contract`: what the change must achieve.
- `failureBoundary`: what breaks or is contained when it fails.
- `evidence`: test, command, observation, trace, or invariant proving it.
- `falsifier`: executable or observable condition that would prove it wrong.
- `nonGoals`: what this intentionally excludes.
- `invariants`: truths that must remain true while changing it.
- `assumptions`: facts not yet proven.

## TDD Rule

For behavior, plan, prompt, skill, code, test, or operational changes:

1. Write or identify failing proof from the `evidence`/`falsifier` fields.
2. Run it and see the expected failure.
3. Implement the smallest change.
4. Run proof again and relevant regression checks.

If the task is operational/config-only, define the equivalent proof command or
live-state check before changing it.

## Judgment Rule

Any judgment call needs confidence and falsifier:

`confidence=<level>; falsifier=<specific evidence that would change this>.`

No falsifier means the decision is not ready.
