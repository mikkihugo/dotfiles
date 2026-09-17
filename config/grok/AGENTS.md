## Mailbox check

Every turn start, after waits, before fan-in: call MCP server `repo_memory`
tool `coordination_sweep` as identity `<client>-<short-session-id>`
(examples: `grok-01a07318`, `codex-df69bdf4`, `copilot-f653d362`).
Channels: `global` and the current repo mailbox (`singularity-engine`,
`jcode`, …). Named recipient. Never default `recipient=all`. Hardcode
poll. Hooks and `inbox_uri` listen do not wake idle sessions. A bus
message never authorizes VCS, land, or completion.

Grok also runs `~/.grok/hooks/bin/mail-sweep.sh` on SessionStart and
UserPromptSubmit (fail-open). jcode uses `bus_presence`. Same contract.

Grok is a stateless CentralCloud caller. After the hook's first
`coordination_sweep`, read
`$XDG_STATE_HOME/coordination-mailbox/grok-<short-session>.coordination-inbox.json`
(default `~/.local/state/coordination-mailbox/…`) and pass that file's
`inbox_uri` on every later `coordination_sweep` / `coordination_post` /
`coordination_ack`. Do not mint a second session id. Do not call sweep
without the URI once that file exists. If the file is missing, wait for
the next SessionStart/UPS sweep, then read it. Never print or log the URI.

Native Grok skill listing (name + description) is the skill index. Load
Purpose bodies with `load_skill` on `purpose_tool`. Do not paste skill
catalogs into this file.

Full feature/fix lifecycle: after `load_skill({name:"using-skills"})`,
load `skill_file_read({name:"using-skills", path:"references/end-to-end-flow.md"})`
(or `skill://purpose_tool/using-skills/references/end-to-end-flow.md`).
Follow that map. Do not paste it here.

## Do not wrap unfinished work and idle

If the objective is still open, either keep working in this turn or arm a
Grok wakeup **before** stopping: `monitor`, `run_terminal_command` with
`background: true`, or `scheduler_create`. That ping is the notify path.
The mailbox is not. A Stop hook (`stop-unfinished.mjs`) blocks a wrap-up
that names in-flight work with none of those armed. Do not write a status
close-out and spin down.

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
- `coordination_sweep` on `repo_memory`
- grouped `search_*`, then `mcp_catalog_search`

No `ccgw__` / `mcp__ccgw__` / glued `server_tool` names. A missing
wrapper is not a missing tool.

Handshake is the client's job. Do not invent `initialize` if this
session already has tools. Poll mail with `coordination_sweep`.
