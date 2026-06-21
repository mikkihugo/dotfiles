---
name: redteam
description: >
  Cross-model adversarial review + decision review. You orchestrate: translate user
  intent to panel flags, resolve doc names, pick lineages from models.json. Read-only
  JSON verdicts from scripts/panel.mjs + scripts/runner.mjs.
user-invocable: true
triggers:
  - redteam
  - adversarial review
  - review the diff
  - hack the code
  - implementation plan review
  - plan review
  - decision review
  - ADR review
allowed-tools: Bash, Read, Glob, Grep, AskUserQuestion
---

# Redteam — you orchestrate

The user speaks plainly. **You** run slash commands, resolve docs, translate intent to flags, and pick lineages from canonical files. The harness does not parse natural language.

## Read before running

| File | Purpose |
|------|---------|
| [`/home/mhugo/.claude/redteam/docs/orchestration.md`](../../../../.claude/redteam/docs/orchestration.md) | **When to use which command**; user language → flags |
| [`/home/mhugo/.claude/redteam/docs/lineages.md`](../../../../.claude/redteam/docs/lineages.md) | **When to pick which lineage**; speed/reliability hints |
| [`/home/mhugo/.claude/redteam/docs/execution.md`](../../../../.claude/redteam/docs/execution.md) | **Foreground vs background; do not poll** |
| [`/home/mhugo/.claude/redteam/models.json`](../../../../.claude/redteam/models.json) | **Lineage policy** — provider order and narrow model params |
| [`/home/mhugo/.claude/redteam/model-bench.json`](../../../../.claude/redteam/model-bench.json) | Generated lane evidence when present |

When the user names a lineage ("use qwen") or you need `--models`, read `models.json` for lineage names. Concrete provider/model ids come from configured Kimi aliases plus live provider catalogs. Default panel routing may use `model-bench.json`, but only for configured, live, metadata-backed models with a distinct failover.

## Slash commands

| Command | Use |
|---------|-----|
| `/redteam:review` | Review code/diff before shipping (default lean: 2 lineages) |
| `/redteam:architect` | Review architecture, ADRs, system design, and route choices through the architect lane |
| `/redteam:plan` | Review an implementation plan for grounding, sequencing, and falsifier gaps |
| `/redteam:decision` | Review a non-architecture decision (doc or pasted prose) |
| `/redteam:hack` | Security-only review |
| `/redteam:bughunt` | Whole-codebase bug hunt |
| `/redteam:harvest` | Positive pattern harvest |
| `/redteam:verify` | Refute reported bugs or validate a fix |
| `/redteam:ultrareview` | Deep multi-lens pre-merge sweep |
| `/redteam:bench` | Discover/benchmark lane candidates and write routing evidence |

## When to forward here

Other skills that explicitly call out redteam as a quality gate:

- **`verification-before-completion`:** For high-stakes or contested claims, run `/redteam:verify` before declaring done.
- **`finishing-a-development-branch`:** Before the 4-option menu for non-trivial branches, optionally run `/redteam:ultrareview`.
- **`writing-skills`:** Before declaring a skill done, run `/redteam:review` with the security (`hack`) lane.
- **`quality-contracts`:** For contested or high-stakes contracts, run `/redteam:review`.
- **`purpose-first-tdd`:** For falsifier validation, run `/redteam:verify`.
- **`writing-plans`:** Before dispatching implementers, run `/redteam:plan`.
- **`systematic-debugging`:** Phase 1 — if similar bugs suspected, run `/redteam:bughunt`.

## Implementation location

Full implementation (commands, scripts, prompts, schemas) lives at `/home/mhugo/.claude/redteam/`. The `kimi.plugin.json` manifest there defines the plugin contract. This dotfile entry is the discoverable skill pointer that the skill tool loads.
