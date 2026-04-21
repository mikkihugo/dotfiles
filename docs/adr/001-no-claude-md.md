# ADR-001: Forbid CLAUDE.md — use ADRs and repo structure as standards

**Status:** Accepted  
**Date:** 2026-04-21

## Context

`CLAUDE.md` is a proprietary Anthropic convention for injecting instructions into
Claude Code sessions. It is not a recognised standard in software engineering and
creates several problems:

- It is invisible to other tools, contributors, and agents not made by Anthropic.
- It encourages verbose, prose-heavy "instructions" that AI models selectively
  ignore or treat as optional hints.
- Standards defined there are not enforced by any mechanism — Claude Code reads
  them but routinely drifts, takes shortcuts, or silently skips steps.
- It duplicates information that belongs in ADRs, READMEs, and tooling config.

## Decision

`CLAUDE.md` is **forbidden** in all repos owned by this organisation.

All standards, conventions, and architectural decisions are documented as ADRs
in `docs/adr/`. Tooling config (lefthook, commitlint, alejandra, cliff) is the
enforcement layer — not instructions in a file that an AI can ignore.

Claude Code operating in these repos **must**:

1. **Read `docs/adr/` at the start of every session** before taking any action.
2. **Follow ADRs without exception.** An ADR is a decision, not a suggestion.
3. **Not take shortcuts.** If a step is required, do it. If it cannot be done,
   say so explicitly — do not silently skip it or pretend it was done.
4. **Not lie.** Do not report success for actions that were not taken. Do not
   claim a file was written if it was not verified. Do not say "done" when work
   is incomplete.
5. **Not be lazy.** Read the actual files. Run the actual commands. Check the
   actual output. Do not assume.
6. **Prefer Rust tools** per the toolchain standard: `rg` not `grep`, `bat` not
   `cat`, `sd` not `sed`, `fd` not `find`, `lsd` not `ls`.
7. **Commit every change immediately** with a Conventional Commit message. Do
   not batch unrelated changes. Do not leave the working tree dirty.
8. **Never create files named** with suffixes like `_enhanced`, `_v2`, `_new`,
   `_old`, `_improved`, `_better`. Edit the original file. Use git for history.

## Consequences

- `CLAUDE.md` at the repo root is deleted.
- Claude Code sessions must be pointed at `docs/adr/` explicitly if context is
  needed — no magic injection file.
- Enforcement is mechanical: lefthook hooks, commitlint, and alejandra reject
  non-compliant commits regardless of what Claude does or does not read.
- Any AI agent that ignores this ADR is operating outside the agreed contract
  for this repository.
