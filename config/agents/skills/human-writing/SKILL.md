---
name: human-writing
description: Use when creating or revising docs, plans, records, PR text, handoffs, or other prose that should be sparse, direct, and low-context.
---

# Human Writing

**Purpose:** Produce prose that humans will read later (docs, plans, handoffs, PR notes) without filler, activity narration, or fake warmth.
**Consumer:** Future readers — other engineers, your own future self, reviewers.
**Failure consequence:** Filler and recap paragraphs accumulate; readers spend context budget on text that doesn't change what they can do.
**Falsifier:** Output is a code change, log line, status string, or single-sentence reply where prose adds no value.

Use this skill for prose that humans will read later: docs, plans, records,
handoffs, PR notes, and status summaries.

## Default Style

- Say why, not what you are doing. State reason, consequence, and blocker.
- Keep it sparse. Prefer the shortest version that preserves decisions,
  evidence, commands, and next actions.
- Write like an engineer leaving a useful note for another engineer.
- Use concrete nouns and exact file, command, model, endpoint, date, or runtime
  names when they matter.
- Remove filler, generic framing, hype, and recap paragraphs that do not change
  what the reader can do.
- Do not use fake warmth, ceremony, or activity narration unless status itself
  is the deliverable.
- Preserve uncertainty honestly. Say what is known, what is inferred, and what
  still needs verification.
- Prefer bullets for scan-heavy material. Prefer short paragraphs for context or
  rationale.

## Docs Context Budget

When editing docs, reduce future context load:

- Keep root docs and agent instructions as routing maps, not full doctrine.
- Move deep detail into narrowly named reference docs only when it will be reused.
- Delete duplicated explanations instead of rephrasing them in multiple places.
- Prefer links to canonical docs over pasted summaries.
- Keep generated or temporary research out of hand-maintained docs unless it has
  become a durable decision.

## Rewrite Pass

Before finishing prose, do one compression pass:

1. Delete throat-clearing and obvious statements.
2. Collapse repeated ideas into one canonical sentence.
3. Replace broad claims with observed facts.
4. Keep only examples that prevent likely misuse.
5. End with the current state and the next useful action, if there is one.
