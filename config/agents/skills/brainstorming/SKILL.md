---
name: brainstorming
description: Use when a request needs product/design exploration, unclear requirements, multiple viable approaches, UI/UX choices, or new behavior whose intent is not yet bounded.
---

# Brainstorming

Turn ambiguous intent into an approved design or scoped spec. Do not use this as
a blocker for obvious bug fixes, small config changes, mechanical edits, or
operator-directed "do it" work.

Purpose: prevent implementation from starting before purpose, constraints, and
success criteria are clear.
Consumer: agents shaping new features, components, workflows, UI, or behavior
where requirements are not already explicit.
Failure consequence: agents build the wrong thing, over-design simple work, or
hide assumptions until implementation.
Falsifier: the user supplied exact files, behavior, constraints, and acceptance
criteria, and no design choice remains.

## Use

Use when any are true:

- User asks to design, brainstorm, create a feature, build an app, or choose an
  approach.
- Requirements are ambiguous or product-facing.
- Multiple credible implementations exist with meaningful tradeoffs.
- Visual/layout decisions affect success.

Skip when:

- User gives a concrete fix/change and says `do it`.
- Production incident needs diagnosis first.
- The task is pure refactor, formatting, deletion, or config adjustment.
- Existing plan/spec already defines the design.

## Flow

1. Inspect current context: files, docs, recent state, existing patterns.
2. Ask one clarifying question at a time only when needed.
3. Present 2-3 approaches with tradeoffs when there is a real choice.
4. Recommend one approach and state why.
5. Present the design scaled to risk and complexity.
6. Get user approval before turning it into a plan or implementation.

For large requests, split into independently useful sub-projects. Brainstorm the
first slice instead of one giant spec.

## Output

For small design decisions, a short approved design is enough.

For durable specs, write to the repo-preferred location, usually:
`docs/specs/YYYY-MM-DD-<topic>-design.md`.

After approval, use `writing-plans` when implementation needs a multi-step plan.

## Visual Companion

Offer visual mockups/diagrams only when seeing the choice beats reading it.
Do not offer visuals for ordinary requirements questions.
