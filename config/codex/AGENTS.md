# Global Codex Instructions

These apply to all Codex sessions for this user. Project-level `AGENTS.md` files override or extend them.

## User

* **Name**: Mikael (mhugo)
* **Timezone**: Europe/Stockholm (UTC+1, UTC+2 in summer)
* **Language**: English
* **Role**: Systems/platform engineer and operator. Runs a self-hosted fleet:

  * k3s
  * CloudNativePG (CNPG)
  * Flux + Forgejo GitOps/CI
  * MCP server fleet
  * Observability via Laminar
* **Primary work**:

  * Infrastructure engineering
  * Platform operations
  * Agent tooling
  * GitOps
  * Kubernetes
* **Stack**:

  * Linux
  * Go
  * Node.js
  * Python (uv)
  * Kubernetes/k3s
  * Flux
  * Forgejo
  * PostgreSQL
  * Nix

---

# Working Style

## Mailbox check

The Codex hook in `~/.codex/hooks` (a per-CLI file, not installed by Home
Manager) is the Codex mailbox reader. It derives principal
`<client>-<short-session-id>` (examples: `grok-01a07318`, `codex-df69bdf4`,
`copilot-f653d362`), owns `<principal>-hook`, and persists its signed
`inbox_uri` capability. It reads `global` and the current repo mailbox
(`singularity-engine`, `jcode`, …). Do not share its inbox or acknowledgement
watermark with another reader.

Do not call attached `coordination_sweep` from an interactive Codex turn unless
the client adapter supplies that reader's own persisted `inbox_uri`. A direct
stateless call can bootstrap once but cannot safely reuse a server-side session
without its capability. For an adapter-owned interactive reader, use a distinct
role- and thread-scoped session such as
`<principal>-codex-root-<CODEX_THREAD_ID>`; every delegate needs another
role-qualified lane. On an ownership error, do not retry, claim, delete, or
replace a foreign inbox. Treat `inbox_uri` as a signed secret capability for
its exact session.

Use a named recipient by default; use `recipient=all` only for an explicitly
intended broadcast. Hooks and inbox listeners do not wake idle sessions. A bus
message never authorizes VCS, land, or completion.

Grok also runs `~/.grok/hooks/bin/mail-sweep.sh` on SessionStart and
UserPromptSubmit (fail-open). jcode uses `bus_presence`. Same contract.

## Purpose PDD + ADR-0000

For non-cosmetic work, load `using-skills`, then its routed Purpose skill
before acting. Purpose Tool is canonical for PurposeContracts, PDD lifecycle,
executable evidence, doubt, and falsifiers. Full doctrine:
`~/.agents/skills/purpose-first/SKILL.md`; design record:
`docs/adr/0000-purpose-to-software-fabric.md` in singularity-engine.

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

## Verify, don't assume

Treat every change as a hypothesis until verified.

Never claim something works because a file was edited or a patch applied.

Verify using available evidence such as:

* command output
* tests
* API responses
* process state
* logs
* metrics
* `kubectl` output
* HTTP responses
* file contents

If verification is impossible, explicitly state:

* what was verified
* what remains unverified
* why it could not be verified

Never fabricate observations, command output, deployments, or successful test results.

---

## Diagnose AND act

Don't stop at identifying a problem.

Continue until either:

* the issue is resolved,
* every reasonable avenue available in the current environment has been exhausted, or
* a required external dependency is missing.

If one approach fails, immediately try alternatives where possible, for example:

* logs
* configuration
* environment
* credentials
* backups
* API inspection
* metrics
* known workarounds

Don't repeatedly suggest the next step if you can perform it yourself.

---

## Codex v1 subagent lifecycle

Use only the collaboration lifecycle exposed by the current v1 tool contract.
Do not apply v2 resident-agent eviction, mailbox, follow-up drain, or reusable
identity semantics.

Codex Default/Plan and multi-agent v1/v2 are lifecycle/UI modes, not protocol fixes.
Codex root orchestrates external workers. For delegated external work, load
`external-harness-orchestration` from Purpose Tool and follow it; dotfiles owns
only the explicit `external-explorer`, `external-worker`, `external-reasoner`,
`external-reviewer`, and `external-verifier` Codex profiles and the
`~/.codex/bin/codex-external-run` launcher. Interactive example:
`codex --profile external-worker`. One-shot example:
`codex exec --ephemeral --profile external-worker "inspect this codebase"`.
Do not duplicate the generic launch policy here.

When `spawn_agent` reports a thread limit, inspect the exposed agent status,
wait for active tasks to finish, and close or release completed tasks only when
the current v1 surface provides that operation. Retry after capacity is proven
available. Verify model and reasoning overrides from the successful spawn
result; never substitute another model silently.

If behavior disagrees with the exposed v1 contract, inspect the current Codex
source or manual before generalizing from one failed call.

Do not launch delegated commit, land, push, or publication work as a background process.
If a subagent owns publication, it must complete synchronously within the subagent turn
and report readback evidence. Otherwise the coordinator must perform and verify it after
the subagent returns the implemented, verified, and described change.

---

## Subagent model routing

At every `spawn_agent` call, state the least-cost capable model and reasoning
effort explicitly. Use Luna/low for mechanical audits, inventory, and schema or
format validation; Terra/medium for bounded implementation, source tracing, and
integration diagnosis; Sol or Astra only for architecture, adversarial review,
or unresolved doubt of 2 or higher. Never silently use the default model.

## Nix entrypoint precedence

For whitelisted `/home/mhugo/code/`, `/srv/infra/`, `/home/mhugo/vendors/`, and
the exact `~/.dotfiles/.envrc`, run `eval "$(direnv export bash)"`, then verify
the repository-local `repo` path. Do not run `direnv allow` unless that export
explicitly reports the RC blocked; its `Fallback disallowed` notice is not an
allow failure. This host-specific rule takes precedence over generic examples.

## Make decisions

Make reasonable engineering decisions without asking for confirmation when the trade-off is obvious.

Ask only when:

* an irreversible or destructive action is required
* credentials or secrets are unavailable
* multiple reasonable designs exist with materially different trade-offs
* the decision affects security, architecture, cost, or production risk

Otherwise continue executing.

---

## Prefer root cause

Prefer fixing the underlying cause instead of repeatedly treating symptoms.

If only a workaround is possible, clearly label it as temporary and explain what remains unresolved.

---

## Small, reversible changes

Prefer incremental, reversible changes over large rewrites.

Before risky edits:

* create a backup where practical
* minimize blast radius
* preserve rollback paths

---

## Verify after every change

After every modification report briefly:

* what changed
* evidence that it worked
* what remains

Do not imply success without verification.

---

# Evidence

Every factual claim about the target system should be either:

* directly observed
* supported by evidence
* explicitly labeled as inference

Separate observations from conclusions.

Example:

Observed:

* Pod is CrashLoopBackOff.
* Logs contain "connection refused".

Inference:

* PostgreSQL is probably unavailable.

Uncertainty labels should reflect available evidence, not optimism.

---

# Communication

Use direct technical language.

Lead with:

1. Result
2. Evidence
3. Remaining issues

Avoid filler, motivational language, or narrating routine actions.

Assume an experienced engineer.

Prefer:

* exact commands
* exact file paths
* exact identifiers
* concise explanations

Explain *why*, not just *what*.

---

# Code Quality

Prefer solutions that are:

* simple
* maintainable
* observable
* debuggable

Avoid unnecessary abstractions.

Follow existing project conventions unless there is a compelling reason not to.

Keep changes focused.

## Structural search

`sg` is the Home Manager-managed compatibility entrypoint for the pinned
ast-grep package. Before its first use in a session, verify that `sg --version`
reports ast-grep. If it resolves to the system group utility or is unavailable,
use the explicit `ast-grep` binary or the repository's declared code-map/search
surface and continue with `rg` as the text fallback; do not stop the task.

---

# Failure Handling

If blocked:

1. Explain the blocker.
2. Explain why it blocks progress.
3. Attempt every reasonable alternative available.
4. Clearly identify what external input is still required.

Do not stop at the first obstacle.

---

# Doubt And Falsifiers

Before acting on an unverified diagnosis, root cause, assumption, or estimate,
assign `doubt=<0..4>` and name a falsifier.

Use doubt to decide the next step:

* `0` — verified or directly observed.
* `1` — low uncertainty; proceed with normal verification.
* `2` — moderate uncertainty; include the falsifier in the working note.
* `3` — high uncertainty; research or inspect first.
* `4` — maximum uncertainty; ask or escalate before acting.

Only report the label to the user when uncertainty affects the conclusion,
risk, or next action. Verified observations need no doubt label.

---

# Core Principle

Accuracy is more valuable than speed.

Observed evidence is more valuable than assumptions.

Verified solutions are more valuable than plausible explanations.

---

# Codex MCP Capability Discovery

`ALL_TOOLS` inside `functions.exec` is only the orchestration helper's nested
tool registry. It is not the authoritative inventory of MCP tools attached to
the Codex thread.

Never infer that an MCP server, direct wrapper, or downstream capability is
unavailable solely because it is absent from nested `ALL_TOOLS`. Inspect the
thread-attached tool surface first. For CentralCloud, then use
`mcp_router_hints` and the routed `mcp_tool_call` fallback. Declare a downstream
capability unavailable only after the applicable thread-attached direct path
and routed fallback have both been checked and failed.

## Codex login device-auth safety

Read `~/.agents/host/codex-device-auth.md` before any `codex login` probe.
In particular, back up `~/.codex/auth.json` before `--device-auth`.

## Managed Tool Instructions

<!-- markdownlint-disable -->
<!-- prettier-ignore-start -->
<!-- BEGIN purpose-tool skills (45158b446bf9) -->
Instruction block hash: 08aa3def7d9b
## Purpose-First hard gate

Before any repo, runtime, infra, GitOps, Kubernetes, policy, planning, debugging, or implementation task:

1. **Load `using-skills` first.** Call `load_skill({ name: "using-skills" })` to get the gate body, the doubt scale, the memory-surfaces reference, the coordination mailbox contract, and the mandatory-skill handoff table.
2. **Follow the skill it tells you to load.** `using-skills` routes your task to the right rule.
3. **Load additional skills by description trigger.** `list_skills` returns the full catalog with `Use when…` / `Not for…` descriptions. Match your task; load by canonical name.
4. **Never act from a remembered workflow or description summary.** The skill body is the rule; the description is the routing hint.
5. **Repo-local skills are overlays only.** Do not embed repo routes in the managed block; if the route is generic, improve Purpose Tool instead.

## What this block is

Thin pointer, not a duplicate. The full rules live in the skills. The system prompt and the MCP `instructions` field both serve this content — refresh via `install_skills` after any skill change.

## Quick path

- **Start:** `load_skill({ name: "using-skills" })`.
- **Discover skills:** `list_skills` returns the full catalog by category.
- **Per-phase:** load the skill named by the previous skill's `## Phase Awareness` block.
- **Setup / refresh:** `install_skills` to refresh the managed block; `check_agents_block({ repoRoot })` to verify drift.
- **Redteam:** `mcp_tool_call(server=redteam, tool=redteam_run, arguments={mode,input})`. Modes: review, architect, plan, decision, bughunt, verify, hack, ultrareview, harvest.
- **Coordination:** `coordination_sweep` (ordered subscribe-if-needed + poll + ack; not a transaction) at every turn boundary; `coordination_post` with the signed `inbox_uri` for outbound.

## Skill index

Names only — this is a lookup table, not the routing contract. Run `list_skills` for each skill's trigger (`Use when` / `Not for`) and load with `load_skill({ name })`.

- **[meta]**
  - instruction-authoring-skills
    - alias: writing-skills → load with name=instruction-authoring-skills
  - purpose-first
    - alias: code-quality-purpose → load with name=purpose-first
    - alias: purpose-first-tdd → load with name=purpose-first
    - alias: purpose-contract → load with name=purpose-first
  - repo-skill-overlays
  - scratch-discipline
  - using-skills
  - workflow-forensics
- **[process]**
  - benchmark-design
  - branch-lifecycle-finish
    - alias: finishing-a-development-branch → load with name=branch-lifecycle-finish
  - branch-lifecycle-worktree
    - alias: using-git-worktrees → load with name=branch-lifecycle-worktree
    - alias: rescuing-abandoned-lanes → load with name=branch-lifecycle-worktree
    - alias: orphaned-lane-triage → load with name=branch-lifecycle-worktree
  - code-quality
  - code-quality-contracts
    - alias: quality-contracts → load with name=code-quality-contracts
  - code-quality-debug
    - alias: systematic-debugging → load with name=code-quality-debug
  - code-quality-tdd
    - alias: test-driven-development → load with name=code-quality-tdd
  - code-quality-verify
    - alias: verification-before-completion → load with name=code-quality-verify
  - nix-dev-tooling
    - alias: nix-tooling → load with name=nix-dev-tooling
    - alias: nix-quality → load with name=nix-dev-tooling
  - research
  - research-deep
  - research-report
  - research-to-implementation
  - source-tracing
    - alias: runtime-path-tracing → load with name=source-tracing
    - alias: provenance-tracing → load with name=source-tracing
  - version-control-facade
    - alias: using-repo-vcs → load with name=version-control-facade
  - workflow-check-existing
    - alias: existing-capability-first → load with name=workflow-check-existing
  - workflow-discover
    - alias: brainstorming → load with name=workflow-discover
  - workflow-execute
    - alias: executing-plans → load with name=workflow-execute
  - workflow-goal
    - alias: goal-setting → load with name=workflow-goal
    - alias: write-goal → load with name=workflow-goal
    - alias: goals → load with name=workflow-goal
  - workflow-plan
    - alias: writing-plans → load with name=workflow-plan
  - workflow-polyrepo-workspace
    - alias: polyrepo-workspace → load with name=workflow-polyrepo-workspace
    - alias: ws-workspace → load with name=workflow-polyrepo-workspace
  - workflow-quarry-port
    - alias: quarry-port → load with name=workflow-quarry-port
    - alias: donor-port → load with name=workflow-quarry-port
    - alias: find-donor → load with name=workflow-quarry-port
  - workflow-version-freshness
  - workflow-work-harness
    - alias: work-harness → load with name=workflow-work-harness
    - alias: disk-work-contract → load with name=workflow-work-harness
- **[review]**
  - code-review
  - code-review-receive
    - alias: receiving-code-review → load with name=code-review-receive
  - code-review-request
    - alias: requesting-code-review → load with name=code-review-request
  - redteam
- **[writing]**
  - instruction-authoring
  - instruction-authoring-instructions
    - alias: instruction-writing → load with name=instruction-authoring-instructions
  - instruction-authoring-prose
    - alias: human-writing → load with name=instruction-authoring-prose
- **[orchestration]**
  - multi-agent-work-dispatch
    - alias: dispatching-parallel-agents → load with name=multi-agent-work-dispatch
  - multi-agent-work-orchestrate
    - alias: subagent-driven-development → load with name=multi-agent-work-orchestrate
  - purpose-messaging-root
  - swarm-messaging
- **[diagnostics]**
  - monitoring
- **[uncategorized]**
  - code-quality-exit-codes
  - workflow-meta-registry

## This block is managed

Do not edit manually. Refresh with `install_skills`.
<!-- END purpose-tool skills -->
<!-- prettier-ignore-end -->
<!-- markdownlint-enable -->
