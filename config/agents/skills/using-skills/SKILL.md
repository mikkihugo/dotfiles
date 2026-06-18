---
name: using-skills
description: Use when starting any conversation or task, before clarifying, inspecting files, planning, editing, or answering.
---

<SUBAGENT-STOP>
If dispatched as a subagent for a specific task, skip this skill.
</SUBAGENT-STOP>

# Using Skills

Check relevant skills before acting. The overhead is intentional: loading the
right rule is cheaper than repairing drift after an agent acted from memory.
`purpose-first-tdd` is the primary doctrine for changes: canonical 9-field PDD
contract plus failing proof before implementation.

Purpose: route work through reusable process instead of memory or habit.
Consumer: main agents at turn start and before new task modes.
Failure consequence: agents skip required workflows, duplicate stale practice,
or answer before loading the policy that governs the task.
Falsifier: the task is a self-contained one-liner with no repo, runtime,
workflow, policy, or user-history dependency.

## Rule

Before any response or action:

1. Identify skills whose description might apply.
2. Load each relevant skill.
3. Announce selected skills in one short line.
4. Follow the skill unless the user or repo instructions override it.

If unsure whether a skill applies, load it. If it does not fit after reading,
say why briefly and continue. Do not skip a skill just to reduce ceremony.

## Overhead Policy

Skill-loading overhead is allowed and expected. Prefer a small delay with the
right governing rule over a fast answer that bypasses purpose, provenance,
quality gates, or verification.

Skip skill loading only for hard self-contained tasks such as:

- current time/date
- simple translation
- one sentence rewrite
- one terminal command with no repo consequence

Any repo file, runtime, validator, prompt, plan, code, infra, or memory-dependent
task is not self-contained.

## Priority

User/repo instructions override skills. Skills override default habit.

When multiple skills apply:

1. Capability search first when adding/changing a surface:
   `existing-capability-first`.
2. Primary purpose/proof doctrine for behavior or policy:
   `purpose-first-tdd`.
3. Quality gates when proof, validators, exceptions, or hidden debt are in play:
   `quality-contracts`.
4. Process skills next: `brainstorming`, `systematic-debugging`,
   `test-driven-development`, `writing-plans`.
5. Domain/output skills next: `instruction-writing`, `human-writing`, frontend,
   image, API, skill writing.
6. Verification skills before claims: `verification-before-completion`,
   review/finish skills.

## Red Flags

Stop and check skills when thinking:

- "This is simple."
- "I need context first."
- "I remember the workflow."
- "I'll inspect one file first."
- "This skill is probably overkill."
- "I'll answer then verify."

Action is task. Task requires skill check.
