---
name: instruction-writing
description: Use when changing prompt templates, AGENTS.md, CLAUDE.md, MCP/tool instructions, skills, governance docs, or any instruction surface where verbosity, duplicated doctrine, hidden exemptions, unclear provenance, or weak enforcement could affect agent behavior.
---

# Instruction Writing

Make instruction surfaces shorter, stricter, and easier to obey. Edit canonical
text instead of adding another copy of the same rule.

Purpose: prevent prompts and agent instructions from hiding compliance debt or
duplicating doctrine until agents cannot tell which rule is authoritative.
Consumer: agents editing prompt templates, `AGENTS.md`, `CLAUDE.md`, skills,
workflow text, and policy-facing docs.
Failure consequence: missing contracts, skipped gates, and stale instructions
ship because the policy surface says "handled" while the code remains broken.
Falsifier: removing an exemption or duplicated instruction requires no code, doc,
test, prompt-loader, or policy change because the underlying contract is already
true in one canonical place.

## Workflow

1. Identify the instruction surface and its consumer:
   prompt template, root agent doc, scoped agent doc, skill, hook policy, or ADR.
2. Find the canonical source for the rule before writing:
   `AGENTS.md`, `CLAUDE.md`, ADRs, prompt loaders, policy scripts, or tests.
3. Record provenance when the instruction was harvested from another source:
   product, repo, component, file, command, trace, or benchmark.
4. Delete duplication. Link to canonical detail when it already exists.
5. Replace broad advice with rule, trigger, failure consequence, falsifier, and
   verification command.
6. Keep text that changes behavior. Remove motivation, ceremony, roleplay,
   repeated warnings, and generic "be careful" wording.
7. Expose compliance debt: missing JSDoc, skipped tests, lint suppressions,
   generated exemptions, and allow-list entries must be fixed or recorded as
   bounded migration work.
8. Verify the consuming surface: prompt variable coverage, markdown lint, policy
   script, unit test, or narrow command.

## Writing Rules

- One rule should fit in one short paragraph or one bullet.
- A rule must say when it applies and what breaks if ignored.
- A judgment rule needs a falsifier.
- A temporary exception needs owner/path, removal condition, failure consequence,
  and falsifier.
- Do not add synonyms for existing doctrine. Choose one term and use it.
- Do not paste long doctrine into prompts. Put doctrine in canonical docs; make
  prompts reference the actionable slice.
- Do not weaken gates to make prose true. Refactor code or policy until the gate
  and instruction agree.
- Product/system names are evidence when they explain source, boundary, policy,
  benchmark, or architecture. Preserve evidence names; remove decorative labels.
- Validator fixes must reduce real debt. A new ignore, allow-list, or disabled
  rule needs path, owner, removal condition, failure consequence, and falsifier.

## Compression Pass

Use instruction compression for prose, not for code or data:

- Remove articles, auxiliary verbs, intensifiers, pleasantries, and repeated
  framing when meaning stays clear.
- Keep nouns, main verbs, numbers, quantifiers, uncertainty qualifiers,
  negations, file paths, command names, URLs, schema keys, prompt variables, and
  technical terms.
- Keep product/system names when they carry provenance, integration boundary,
  provider policy, benchmark evidence, or architecture meaning. Generalize
  decorative shorthand only.
- Harvest or comparison artifacts must preserve provenance names when columns
  such as `source_index`, `repo_or_component`, `repo`, `source`, and
  `target_file_or_module` are trace keys. Keep product, repo, component, and
  source names there so reviewers can prove where a pattern came from.
- Keep prepositions when they define relationships: source/destination,
  ownership, scope, location, dependency, or exclusion.
- Prefer fragments for agent-only consumers. Prefer complete sentences when
  ambiguity, legal risk, or security risk would increase.
- Do not run blind compression over policy files. Review behavior-changing
  rewrites against the canonical 9-field PDD contract.

## Validator Work

When prompt/docs validation fails, split failures into:

- **Syntax breakage:** parser errors, malformed frontmatter, unmatched fences.
  Fix first; validators cannot classify broken input.
- **Mechanical debt:** line length, fence language, heading shape, table style.
  Prefer codemods or formatter-safe rewrites over disabling rules.
- **Policy debt:** inline HTML, duplicated headings, missing provenance, hidden
  exemptions. Fix the contract or create bounded migration records.
- **False positive:** allowed only with local justification and a removal test or
  removal condition.

Do not report "all validators pass" until the exact command has run in the
current checkout.

## Output Shape

For doc edits, produce the smallest diff that preserves the contract.
For prompt edits, preserve variables and update every `loadPrompt` caller or test
that depends on the changed variables.
For skill edits, keep `SKILL.md` self-contained. Size is a judgment call: keep
detail that prevents likely misuse, remove detail that only repeats doctrine.
