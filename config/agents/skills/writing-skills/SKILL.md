---
name: writing-skills
description: Use when creating, editing, pruning, or verifying skills before deployment.
---

# Writing Skills

Skills are process code. Edit them with the same discipline as production code:
baseline failure, minimal guidance, verification.

Purpose: keep reusable agent behavior small, discoverable, and tested.
Consumer: agents authoring or maintaining `SKILL.md` files and supporting skill
assets.
Failure consequence: bloated or untested skills misroute agents, duplicate
doctrine, or create hidden exemptions.

**Redteam forwarder:** Before declaring a new or modified skill done, run `/redteam:review` with the security (`hack`) lane on the skill file. Catches prompt-injection vectors in skill instructions, ambiguous phrasing that could be misinterpreted, missing doctrinal structure (Purpose/Consumer/Failure consequence/Falsifier), and missing `<SUBAGENT-STOP>` markers in main-agent-only skills.
Falsifier: a skill edit reliably improves agent behavior without a baseline
failure, verification scenario, or deployment check.

## Use

Use for:

- New skills.
- Skill rewrites, compression, pruning, or merges.
- Skill descriptions/frontmatter.
- Supporting files under a skill directory.

Do not use skills for one-off repo policy. Put project rules in `AGENTS.md`,
`CLAUDE.md`, ADRs, tests, or policy scripts.

## Discovery Contract

Frontmatter:

- `name`: lowercase words and hyphens.
- `description`: starts with `Use when...`.
- Description names triggers/symptoms only, not workflow.
- Frontmatter stays under 1024 chars.

Body:

- First screen says what problem the skill handles.
- Include searchable terms agents will use.
- Keep heavy references in separate files only when needed.
- Keep examples few and directly reusable.

## Skill Contract

Prefer this shape:

- Purpose: why it exists.
- Consumer: who uses it.
- Failure consequence: what breaks if ignored.
- Falsifier: what would prove the rule unnecessary or wrong.
- Use/Do not use: observable trigger boundary.
- Procedure or checklist: smallest enforceable sequence.
- Verification: command, scenario, or review needed before claiming done.

For discipline skills, add rationalization counters. For output-shape skills,
write a positive recipe instead of a prohibition list.

## Test Loop

1. RED: run or describe a baseline scenario where an agent fails without the
   skill or current wording.
2. GREEN: write the smallest guidance that blocks that failure.
3. VERIFY: run the same scenario or a close static proxy.
4. REFACTOR: remove duplicate text, tighten trigger, retest if behavior changed.

If live pressure testing is too expensive, say that and run static checks:
frontmatter, size, references, ASCII when required, and stale skill names.

## Compression Rules

- Remove narratives, session stories, benefits sections, and repeated warnings.
- Keep commands, file paths, concrete triggers, failure modes, and stop rules.
- Prefer fragments for agent-only consumers.
- Link to canonical rules instead of restating them.
- Delete unused skills instead of documenting around them.

## Merge And Prune

Merge or remove when:

- Two skills trigger on the same situation.
- One skill only says "use this other skill."
- A skill is tied to unused tooling.
- A large skill duplicates smaller canonical skills.

Keep separate when:

- Trigger differs.
- Consumer differs.
- Failure consequence differs.
- One is general and one is domain-specific.

## Deployment Check

Before reporting complete:

- List added, changed, removed skills.
- Check no stale references to removed skill names.
- Check frontmatter parses and descriptions start with `Use when`.
- Check word count as a review signal, not a hard limit. Keep longer skills
  when the extra text prevents real misuse; explain why.
- State whether behavior was pressure-tested or only statically verified.
