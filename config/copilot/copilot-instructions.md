# Copilot CLI — Global Instructions (cc-se-sto-devbox-01)

This file is loaded by every Copilot CLI session regardless of cwd. It
complements (does not replace) the per-directory `AGENTS.md` files.

Verified 2026-09-04 against Copilot CLI 1.0.82 on the llm-gateway fabric.

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

- `COPILOT_PROVIDER_BASE_URL=https://llm-gateway.centralcloud.com` (note:
  trailing `/v1` stripped — the Anthropic client appends `/v1/messages`
  itself)
- `COPILOT_PROVIDER_API_KEY` from SOPS-decrypted `api-keys.yaml`
- `COPILOT_PROVIDER_TYPE=anthropic`
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

The CentralCloud `repo_memory` MCP exposes the coordination tier
(`coordination_subscribe` / `_poll` / `_ack` / `_post`) — the single-inbox
replacement for the legacy `swarm_bus_*` surface. Subscribe once per session
(global channel is always on; add the repository mailbox), poll at session
start, before each blocking operation, and before handoff. Ack every consumed
message in the same turn. Post status/blocker/handoff to `global` with
`recipient=all`; directed mail uses an explicit recipient. Other agents on
this devbox may have context I lack (or that complements mine). Treat silence
as "no signal," not "no one cares."

### Persist observations

Anything I observe that survives the session (bugs, workarounds, gate
failures, recovery runbooks) goes to `repo_memory` via
`memory_retain` with appropriate `kind:` tags
(`bug`/`observation`/`todo`/`handoff`/`decision`/`convention`/`falsifier`).
The earlier "observation that only lives in one conversation dies with it"
pattern is what the coordination bus + repo_memory exist to prevent.

Copilot's `agentStop` hook (observations-autolog.json) drains
`~/.agent-work/observations/copilot-<sessionId>.md` into the bank
automatically at turn end. So: append each observation/idea as ONE LINE to
that capture file during the turn (create it if missing), and the hook
retains it with `kind:observation` and clears the file. Do not leave
observations only in the conversation — the bank is the durable store.

### Don't pretend subagent dispatch is optional

When the operator says "audit," "review," "research," "investigate" — those
imperatives map to dispatch. The single-agent-path reflex is the wrong
default for a multi-agent devbox.
