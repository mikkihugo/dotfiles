# Copilot CLI — Global Instructions (cc-se-sto-devbox-01)

This file is loaded by every Copilot CLI session regardless of cwd. It
complements (does not replace) the per-directory `AGENTS.md` files.

## Purpose PDD + ADR-0000

Iron law: no behavior change without a PurposeContract and failing or stale
proof first.

PDD nine fields (mandatory for non-trivial bounded work):
purpose, consumer, contract, failureBoundary, evidence, falsifier, nonGoals,
invariants, assumptions (each `doubt=0..4` plus a falsifier).

Evidence is executable (test, command, metric, repro, live-state check, or
`[MANUAL: reviewer + scenario]`). Prose is not evidence. Do not invent system
state, command results, API behavior, or successful verification.

ADR-0000 lifecycle:
1. Capture bounded intent.
2. Translate it into a PurposeContract/PDD.
3. Research missing context and expose assumptions.
4. Run-control: risk, doubt, reversibility, blast radius, cost, approval.
5. Map to the Feature Tree and generate a WorkSpec.
6. Contract tests or executable evidence before implementation.
7. Smallest satisfying change.
8. Verify tests, quality, runtime, deployment, and falsifier evidence.
9. Persist an EvidenceBundle, close the work, scoped learning.

Cosmetic self-contained work with no behavior, policy, proof, consumer, or
public-contract impact is out of scope. Everything else is in.

Load `using-skills`, then `purpose-first`. Full doctrine:
`~/.agents/skills/purpose-first/SKILL.md`. ADR:
`docs/adr/0000-purpose-to-software-fabric.md` in singularity-engine.

Done: named purpose, named consumer, proof run (failed first for a behavior
change), evidence on disk, named falsifier.

## Live MCP tools

Do not pin a protocol version in this prompt. Use whatever the live
session already negotiated (one per session). Standard names:

- `mcp_tool_call(server, tool, arguments)` — every CentralCloud call
- `load_skill` on `purpose_tool`
- grouped `search_*`, then `mcp_catalog_search`

No `ccgw__` / `mcp__ccgw__` / glued `server_tool` names. A missing
wrapper is not a missing tool.

Handshake is the client's job. Do not invent `initialize` if this
session already has tools.

## Subagent dispatch via the `task` tool

The `task` tool exposes these `agent_type` values:
`explore`, `task`, `general-purpose`, `rubber-duck`, `code-review`,
`research`, `security-review`.

`architect`, `debug`, `refactor` are **NOT** `task` tool types — they are
`/subagents` config slots only. To use them in the interactive CLI use
`/agent <role>` or `copilot --agent=<role> --prompt "..."`. From this
session they cannot be invoked via the `task` tool.

### Always pass an explicit `model:` parameter

Verified lineage reliability (all routed through the llm-gateway BYOK
endpoint at `https://llm-gateway.centralcloud.com`):

| `model:`           | Status     | Notes                                            |
|--------------------|------------|--------------------------------------------------|
| `auto-minimax`     | ✅ works   | MiniMax M3 — primary workhorse                   |
| `auto-glm`         | ✅ works   | GLM 5.x via ollama-cloud                         |
| `auto-fast`        | ✅ works   | MiniMax M3 direct, fast tier                     |
| `auto-deepseek-fast` | ✅ works   | DeepSeek V4 Flash via deepseek (cheap explore) |
| `auto-kimi`        | ❌ empty   | kimi shared pool quota exhausted (since 2026-08-04) |

Without an explicit `model:`, the `task` and `code-review` agent types
fall back to an unset default and return empty (HTTP 403 from the
gateway). The other types (`explore`, `general-purpose`, `research`,
`security-review`, `rubber-duck`) tend to work without it but should
still pass `model:` for consistency.

**Default to `model: auto-minimax`** unless the task explicitly needs a
different lineage.

## BYOK env vars

Already wired in `/home/mhugo/.dotfiles/shell/bash/bashrc` lines
147-204 (loaded via SOPS on session start):

- `COPILOT_PROVIDER_BASE_URL=https://llm-gateway.centralcloud.com/v1`
  (keep `/v1` while `COPILOT_PROVIDER_TYPE=openai`; stripping it 404s
  `auto-minimax` on Copilot 1.0.84)
- `COPILOT_PROVIDER_API_KEY` from SOPS-decrypted `api-keys.yaml`
- `COPILOT_PROVIDER_TYPE=openai`
- `COPILOT_MODEL=auto-minimax`
- `COPILOT_PROVIDER_MAX_PROMPT_TOKENS=458752`
- `COPILOT_PROVIDER_MAX_OUTPUT_TOKENS=65536`

The dotfiles bashrc wires these for fresh child shells via `BASH_ENV`.
A running copilot process that was spawned BEFORE the SOPS-loaded env
was exported does NOT inherit them — sourcing the bashrc in your
shell sets env vars for YOUR shell only. Permanent fix: restart
copilot in a new shell so it picks up the dotfiles env at startup.

## Operator authority

This host (`cc-se-sto-devbox-01`) follows "all agents do as recommended"
unless explicitly told otherwise. The devbox `AGENTS.md` documents
operator authority overrides for specific high-impact actions
(restart copilot, edit `/home/mhugo/AGENTS.md`, etc.).

## Related instruction files

- `/home/mhugo/AGENTS.md` — home devbox operator guide (read by Copilot
  in cwd)
- `/home/mhugo/.dotfiles/AGENTS.md` — dotfiles source for shell
  integration (not read by Copilot)
- `/home/mhugo/code/jcode/AGENTS.md` — jcode-specific instructions
  (read when cwd is inside jcode)
- Per-repo `AGENTS.md` files — read the nearest ancestor before editing
  any code surface

## Operational doctrine — actually fan out, run reviews

The devbox `AGENTS.md` mandates fan-out: "Default to parallel subagents
(explore/coder swarms) whenever 2+ independent lanes exist — research,
diagnosis, reproduction, and non-overlapping code surfaces." This is not
optional. Concrete triggers and what to do:

### When to dispatch subagents (default to yes)

- **Any non-trivial task with 2+ independent lanes**: research + read +
  audit run in parallel as `explore`/`research` subagents.
- **Code changes**: spawn `code-review` AND `security-review` subagents
  in parallel on the diff before declaring work complete. Don't skip
  these even for "small" changes — they catch blind spots you and I share.
- **Refactor or seam-violation work**: spawn `architect` (via `/agent
  architect` in interactive CLI; in this session, run a
  `general-purpose` subagent with explicit architect-mode prompt) for
  design review.
- **Long-running reads/audits**: dispatch to `task` agent_type — keeps
  my context window clean.
- **Anything that risks circular reasoning**: dispatch `rubber-duck`
  (it has `autoInvoke: true`, plus can be surfaced via
  `--agent=rubber-duck`).

### When to run adversarial review

The `redteam` subagent (via the centralcloud MCP gateway) is a deliberate
opposer. Run it before any of:
- Merging a non-trivial PR (especially security-relevant changes)
- Publishing a public API or schema
- Submitting a plan that will become multi-week work
- After claiming "fixed" or "complete" on a substantive bug

Mode hint: `mode=review` for code, `mode=architect` for design proposals,
`mode=bughunt` after a fix to verify it actually closes the gap.

### When to post on the coordination bus

The CentralCloud `repo_memory` MCP exposes the v3 coordination tier:
`coordination_read`, `coordination_post`, and (for direct mail) the separate
`coordination_ack`. There is no subscribe/poll/sweep verb or inbox capability.
Read with an explicit principal and `reader: "agent"`; post status,
blocker, or handoff to `global` with a named recipient. Never default to
`recipient=all`. Treat silence as "no signal," not "no one cares."

### Persist observations

Anything I observe that survives the session (bugs, workarounds, gate
failures, recovery runbooks) goes to `repo_memory` via
`memory_retain` with appropriate `kind:` tags
(`bug`/`observation`/`todo`/`handoff`/`decision`/`convention`/`falsifier`).
The earlier "observation that only lives in one conversation dies with it"
pattern is what the coordination bus + repo_memory exist to prevent.

### Don't pretend subagent dispatch is optional

When the operator says "audit," "review," "research," "investigate" — those
imperatives map to dispatch. The single-agent-path reflex is the wrong
default for a multi-agent devbox.
