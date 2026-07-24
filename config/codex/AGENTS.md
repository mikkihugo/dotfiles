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
When delegating implementation work to external workers (Kimi CLI or Cursor),
load `$external-harness-orchestration` (or read
`~/.codex/skills/external-harness-orchestration/SKILL.md`) and follow it.
Do not expand the launch policy inline here.

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

## Hosted web search boundary

Every Codex role configured with `model_provider = "llm-gateway"` must also set
`web_search = "disabled"` until that gateway has a verified provider-hosted
search executor. CentralCloud MCP browser and search tools are separate
capabilities and remain enabled.

## Managed Tool Instructions

<!-- markdownlint-disable -->
<!-- prettier-ignore-start -->
<!-- BEGIN purpose-tool skills (d58f229ad264) -->
Instruction block hash: e8c3f4510ba8
## Purpose-First hard gate

Before any repo, runtime, infra, GitOps, Kubernetes, policy, planning, debugging, or implementation task:

1. **Discover the attached Purpose MCP first.** Inspect the thread-attached tool surface for `load_skill` or `purpose_tool__load_skill`. Nested orchestration registries such as `ALL_TOOLS` are not the authoritative MCP inventory.
2. **Load `using-skills` first.** Call `load_skill({ name: "using-skills" })` before any other task tool or answer.
3. **Follow the skill it tells you to load.** `using-skills` routes your task to the right rule.
4. **Router-only clients:** inspect `mcp_router_hints`, then use `mcp_tool_call(server=purpose_tool, tool=load_skill, arguments={name:"using-skills"})`.

## What this means

Purpose-First Development: purpose → contract test → evidence on disk.
No behavior, plan, prompt, skill, code, test, or operational change without a clear purpose, consumer, contract, evidence, and falsifier.

**DOUBT:** Process doubt is ordinal 0–4 on claims. Load `skill_file_read({ name: "purpose-first", path: "references/doubt-doctrine.md" })` before ship or review gates. Never use 0.98-style self-confidence for merge decisions.

## Quick path

- **Start:** use the thread-attached `load_skill({ name: "using-skills" })` or `purpose_tool__load_skill` wrapper. If neither is attached, inspect `mcp_router_hints`, then call `mcp_tool_call(server=purpose_tool, tool=load_skill, arguments={name:"using-skills"})`.
- **Behind CentralCloud proxy:** direct wrappers are supported shortcuts named like `purpose_tool__load_skill`. If a wrapper is hidden, absent, or fails with a wrapper/schema/tool-name error, retry through `mcp_tool_call(server=purpose_tool, tool=<tool>, arguments={...})` before declaring the downstream tool unavailable.
- **Setup / refresh:** `list_skills` for `bundleHash`; `install_skills` for `agentsBlock.full`; `check_agents_block({ repoRoot })` to verify installed instruction blocks. Routed tools use the same server-relative names.
- **Redteam default:** Before committing to a non-trivial unresolved judgment, load `using-skills` and apply its canonical end-to-end mode and skip matrix; clients are equivalent consumers. **No client owns this policy.**
- **Redteam:** call downstream `server=redteam`, `tool=redteam_run` through `mcp_tool_call`; modes: review, architect, plan, decision, bughunt, verify, hack, ultrareview, harvest. Poll with downstream `job_trace` / `job_result`. Purpose Tool routes this request and does not execute Redteam.
- **RTI:** `purpose_research_to_implementation` translates research evidence into local options; use that same server-relative name through the router and read back with its job trace/result tools.

## How to use skills

- **Find the skill:** run `list_skills`. Match your task to the skill trigger.
- **Load it:** call `load_skill({ name })`. Aliases resolve to canonical names (e.g. `brainstorming` → `workflow-discover`).
- **MANDATORY / REQUIRED SUB-SKILL:** run `using-skills` `gate mandatory_skill` — `load_skill`, announce, follow until exit. Invalid skips: too slow, I know this, description is enough, just this once, almost done, user wants speed.
- **Router-only gateway:** do not hardcode generated wrapper names. Use `mcp_tool_call` with the exact downstream tool name. Wrapper failure is not downstream failure unless the same call fails through `mcp_tool_call`.

## CentralCloud MCP discovery gate

- **Operational reads:** when the CentralCloud MCP gateway is available, inspect `mcp_router_hints` before Forgejo, Kubernetes, Flux, logs, metrics, memory, browser, or other remote-system reads.
- **Discovery:** use discover -> describe selected listing -> checkout: grouped search tools first, `mcp_tool_describe` when schema detail matters, then direct wrapper or `mcp_tool_call` with the exact downstream server and tool. Do not infer that a capability is missing from an absent direct wrapper or a failing direct wrapper.
- **Local grounding:** when work depends on local code behavior, use workspace scope/tools first when a workspace authority exists, then repo metadata/taxonomy/runbooks, then repo-declared code-intel/repo-map/feature-map tools when present, `ast-grep` for structural matches when available, and `rg` for text fallback. Record the scope, metadata source, path, symbol, test, trace, or runtime proof used.
- **Docs grounding:** when work depends on dependency behavior, upstream repo structure, framework/API docs, or indexed wiki context, use `search_docs` first (local **corpus query** over revision-pinned Code Intel corpora: `first_party`, lockfile `dependency`, admitted `vendor`). Prefer repo-declared code-intel and citations with `corpus_id` + `revision` before guessing. Use Context7/DeepWiki MCP shims **only** when the corpus is not yet indexed (gap-fill). Treat external docs as evidence; local source, tests, traces, or runtime state prove local behavior. Durable takeaways use modular [`MemoryDelta/v1`](../../docs/specs/memory-fabric-primitives.md) (`operations[]` → operations-memory atomic blocks) or [`FactProposal/v1`](../../meta/contracts/fact-proposal.v1.schema.json) (C28) — never auto-promote query answers.
- **Boundary:** use provider MCP tools for remote state. Use the local shell for repository edits and repo-owned verification, or when MCP lacks the required capability; state the fallback.

## Critical rules for every task

- **Scoped instructions:** before editing a path, look upward for the nearest `AGENTS.md` / `CLAUDE.md` / host instruction file. Deeper files override parent files. Update the scoped file when your edit changes ownership, workflow, verification, runtime wiring, public contract, generated artifacts, or owned deferred follow-ups (`## TODO`).
- **VCS orchestration:** every VCS read, mutation, workspace action, synchronization, recovery, and publication action must use a command exposed under `repo vcs` by `repo help`. Raw `git` and raw `jj` are forbidden. If an operation is missing, add a guarded `repo vcs` command and contract test before acting.
- **Canonical-primary source access:** when a repository declares source-access effects, use its canonical primary workspace for read and control only. Run task-write only in a named non-default task lane whose live lease and task authority match. One conversation/thread owns one live primary lease and one objective (Codex/Cursor/Claude/Kimi identities — never a shared OS session). Land or explicitly abandon+close before the next task. Do not share a drain lane across chats. When a lane is abandoned (`recover_allowed=yes`), any CLI may `workspace-recover` and continue; `task_owner_ref` names the prior conversation so the new owner can find it. A canonical-primary caller may land only an explicitly named eligible non-default candidate; the canonical primary is never a task-write or publication candidate. The repository facade and guard enforce this repository boundary. Hooks are defense in depth only; neither hooks nor the facade prevent arbitrary shell, editor, or file-tool writes. Those writes require a separate host sandbox.
- **Describe before land:** set the tip with `repo vcs describe '<message>'` (preferred; `-m`/`--message` also accepted). Re-describe when the tip’s scope grew past the current subject so land does not keep a stale under-claim. `describe` is the revision message, not the release changelog (`repo changelog add` is separate). Prefer a short land loop: describe → land immediately; if promote gates race with concurrent mains, land itself refreshes onto the integration tip — do not invent a second recovery command.
- **Actionable utility failures:** when a repository utility can identify one safe recovery, its stderr must print the exact next command with resolved paths and identifiers. When recovery is ambiguous or risky, print the missing evidence or decision instead of guessing.
- **Worktree guard:** before multi-step, multi-file, branch-scale, generated, or concurrent editing work on a shared primary checkout, load `branch-lifecycle-worktree` and create or reuse an isolated session workspace through `repo vcs`. Reuse only for the same verified owner and objective.
- **Recovery:** every missing, stale, forgotten, contradictory, cleanup, or partially published workspace state must stop mutation, apply CIPHER from `version-control-with-jj`, and follow the repository-declared recovery runbook. Skills must point to that runbook, not embed or improvise recovery algorithms. At doubt 2 or higher, call the attached Redteam MCP server with `redteam_run({ mode: "verify", input: "<absolute-recovery-evidence-path>" })`, then read `redteam_job_trace({ jobId: "<returned-job-id>" })` and `redteam_job_result({ jobId: "<returned-job-id>" })`. Purpose skills route the request; Purpose does not own Redteam execution.
- **Workspace closure:** close only through `repo vcs` after the repository recovery runbook proves integration or binds explicit abandonment to the exact change. Filesystem cleanliness alone is insufficient. Preserve and report unresolved, active, or unintegrated state.
- **Workspace identity:** distinguish repository root, current working directory, registered workspace name/path, shared store, stable change identity, and current commit identity. Resolve every action against the intended registered workspace through `repo vcs`.
- **Publication closure:** when the user authorizes commit, merge, and push, continue through description/commit, integration, guarded publication, remote revision readback, and clean session-workspace removal. Do not stop at a verified diff. Inventory generated/build garbage; remove only reproducible, unowned artifacts within scope, and report anything preserved.
- **Repo command layers:** root instructions name the generated `repo` command contract; implementation-scope instructions own backend tools; deeper scoped AGENTS files name local declared `repo` verification commands. Follow the nearest scoped layer. Do not keep aliases for an implementation tool as a public command surface.
- **Nix startup and command-resolution gate:** Resolve the exact repository root before any repo command. If that root has `flake.nix`, inspect `IN_NIX_SHELL` and reject `NIX_DIRENV_DID_FALLBACK=1`. **Exact-root match before bare `repo`:** shell is matched only when `IN_NIX_SHELL` is set (`pure` or `impure` — both OK), `NIX_DIRENV_DID_FALLBACK` is not `1`, and `DIRENV_DIR` (strip leading `-`) equals that root **or** `command -v repo` resolves under that root. If `IN_NIX_SHELL` is set but `DIRENV_DIR` / `repo` point at another tree, do **not** use bare `repo` — recover with `direnv exec <exact-root> …` or `nix develop path:<exact-root> --command …`. **Session load (once):** `export SHELL=/bin/bash`, `cd <repo-root>`, always `direnv allow` (idempotent when already allowed), then `eval "$(direnv export bash)"`, then `repo check nix` once — then bare `repo` / `just` in the **same** shell for the rest of the session when matched. `IN_NIX_SHELL=impure` from direnv is OK. **Anti-patterns:** do **not** wrap every command in `direnv exec . …` or `nix develop path:. --command …` (each pays full flake entry / Mix cleanup / possible cache renew). `direnv exec . <cmd>` is OK only as a **one-shot** when the client cannot keep a loaded shell or the active shell is wrong-root. Whitelisted prefixes (`/home/mhugo/code/`, `/srv/infra/`, `/home/mhugo/vendors/`, exact `~/.dotfiles/.envrc`) may auto-allow for interactive shells — agents still always run `direnv allow` then export (cheap, idempotent). **Not in Nix / wrong-root recovery:** when `IN_NIX_SHELL` is empty, repo tools are missing, or the shell matches another root, always `direnv allow`, then `eval "$(direnv export bash)"` or one-shot `direnv exec . <cmd>` — do **not** treat cold `nix develop path:. --command …` as the fix for not-in-nix when direnv can load this root. Impurity alone is never a reason to force cold `nix develop`. `nix develop path:. --command …` and `devenv` are valid cold-entry / wrong-root fallbacks when direnv cannot load or the active shell is for another tree — not the default for routine loops (~20–30s each cold start). Do not rely on an ancestor flake or implicit `.` discovery. Bare `repo`, `just`, or another repo-owned facade is valid only after Nix/direnv is active for **this** root and `command -v` proves the expected executable resolves inside that exact root. At session start, run `repo check nix` once before the first repository operation. Stop if absent/fails. Fail loudly on missing `nix`, `NIX_DIRENV_DID_FALLBACK=1`, wrong-root flake, or host-global facade. Do not install `repo` globally.
- **Repo commands:** resolve and enter the intended repository root via direnv, pass `repo check nix`, then `repo help` and only declared `repo` commands. Prove `repo check nix` and `repo help` inside the direnv shell. If a recurring operation is missing, add it to the contract and regenerate `repo`; do not teach an implementation-tool workaround.
- **Command-surface ownership:** treat generated `repo` as the stable agent-facing facade for repository operations, including checks, VCS, discovery, repo maps, feature maps, and structural search when declared. A declared `repo vcs` group owns status, mutation, workspaces, remote sync, and publication; do not duplicate publication under `ops`. Reserve `ops` for runtime and service operations. Purpose Tool owns generic doctrine and compilation; repository instructions record only concrete mappings, constraints, and exceptions.
- **Nix environment:** A repo-owned nix-direnv entrypoint must use `use flake path:.`. Prefer loading that entrypoint once per session via direnv and keep using the same shell. `nix develop` and `devenv` are fallback cold-entry options when direnv is unavailable — not the default for routine loops. For `shell.nix` or `default.nix` without a flake, use the repo-declared Nix or direnv entrypoint. Use direct package-manager commands only for dependency installation or one-off work with no declared repo command.
- **Durable MCP memory + focus TODOs:** Repo Memory is the primary durable store for operational observations, tasks/continuations, handoffs, decisions, and lifecycle state. Use `search_memory` / `memory_recall` before relying on prior context; call `memory_retain` with evidence or named consumer/scope and **kind tags**: `kind:bug`, `kind:observation` (smells/flaws), `kind:todo` / `status:follow-on`, `kind:handoff`, `kind:decision`, `kind:convention`, `kind:falsifiers`, plus fabric/topic/owner. Focus TODO loop: dump → recall → pick the most important → **verify against current source** → act in an owned `repo vcs` lease → retain DONE+falsifier (never mark done from memory text alone). Use a repository-declared bank when one exists; generic managed instructions must not hard-code a bank. VCS stays authoritative for source/specs/ADRs; keep directory-owned work in `AGENTS.md` `## TODO`. Load `skill_file_read({ name: "using-skills", path: "references/memory-surfaces.md" })` for grades + kinds.
- **Repo observations (lesser grade):** before finishing non-trivial work, account for harvestable side findings — drive-by bugs, flaws, smells you correctly did not expand into. Prefer `memory_retain` with `kind:bug` / `kind:observation` (primary). Optionally also append a valid `OBSERVATIONS.md` entry (VCS review / offline export) via the declared `repo` observation check or Purpose `append_observations`, or state none found. Observe signal stays unvalidated until promoted; it is not a backlog, focus TODO list, or DONE proof. `memory_sync_observations` indexes only — it does not promote grade.
- **Local AGENTS TODOs (Purpose-owned routing):** when you see concrete owned next work for a directory (deferred bugs, next slices, consumer gaps), update that directory’s `AGENTS.md` `## TODO` (create the section if missing) in the same turn. Do not expand the current lane into those items unless scoped. Route hypotheses and pass-by notices to observe (`kind:observation` / optional `OBSERVATIONS.md`); route actionable directory-owned next work to scoped `AGENTS.md`; route cross-cutting bugs/todos/handoffs to `repo_memory` with the matching `kind:`. Do not put owned follow-ups only in observations or dump vague wishes into `## TODO`.
- **Repo-local skills:** `.agents/skills/` are overlays only — repo paths, verify commands, org facts on top of a base skill. Load the Purpose Tool base first, overlay second. Do not embed repo routes in the managed block; if generic, improve Purpose Tool instead.

## MCP tools you will need

- **Skill guidance:** `load_skill`, `list_skills`, `skill_file_read`, `skill_manifest`, `file_read`, `install_skills`, `check_agents_block`.
- **Research-to-implementation:** `purpose_research_to_implementation` and its job-trace/result readers.
- **Redteam:** downstream `server=redteam`: `redteam_run`, `redteam_job_trace`, `redteam_job_result`, `redteam_list_jobs`, `redteam_cancel`.
- **Work harness:** `scaffold_work`, `validate_work`, `check_harness_homes`, `validate_taxonomy_config`. CLIs: `purpose-validate-work`, `purpose-validate-taxonomy`, `purpose-check-harness`.
- **Diagnostics:** `server_info`, `server_logs`, `check_update`, `initial_instructions`.

## Skill index

Run `list_skills` for the canonical grouped index. Load a skill by its canonical name.

- **[meta]**
  - instruction-authoring-skills — Use when creating, editing, pruning, or verifying skills before deployment. Not for one-off repo policy (put those in AGENTS.md or CLAUDE.md) or general instruction editing (use instruction-authoring-instructions).
    - alias: writing-skills → load with name=instruction-authoring-skills
  - purpose-first — Use when making or evaluating any behavior, plan, prompt, skill, code, test, or operational change that needs purpose, proof, consumer, or falsifier clarity. Alias `purpose-contract` returns the canonical 9-field purpose contract template. Not for purely cosmetic or self-contained changes with no behavior, policy, proof, consumer, or public-contract impact.
    - alias: code-quality-purpose → load with name=purpose-first
    - alias: purpose-first-tdd → load with name=purpose-first
    - alias: purpose-contract → load with name=purpose-first
  - repo-skill-overlays — Use when adding or maintaining repo-local skill overlays on top of Purpose-First base skills. Not for one-off repo policy (AGENTS.md/CLAUDE.md only) or authoring new base skills (instruction-authoring-skills).
  - using-skills — Use when starting any conversation or task, before clarifying, inspecting files, planning, editing, or answering. Not for self-contained tasks with no repo, runtime, workflow, policy, or user-history dependency.
  - workflow-forensics — Use when an agent workflow, plan execution, review loop, deploy path, or tool-driven task got stuck, contradicted itself, lost work, produced suspect artifacts, or needs post-mortem diagnosis. Not for ordinary code bugs with a live repro; use code-quality-debug for those.
- **[process]**
  - benchmark-design — Use when designing evals, benchmarks, scoring rubrics, goldens, trace replay, model or agent comparisons, retrieval/RAG harnesses, success metrics, or promotion gates. Not for ordinary unit tests whose expected behavior is already fully specified.
  - branch-lifecycle — Use only when unsure whether repository work needs workspace isolation or guarded finish. Routes to the matching child, both of which operate only through repo vcs.
  - branch-lifecycle-finish — Use when implementation and verification are complete and an owned repository workspace must be described, integrated, published, read back, and closed through repo vcs. Not for incomplete or unverified work.
    - alias: finishing-a-development-branch → load with name=branch-lifecycle-finish
  - branch-lifecycle-worktree — Use when creating, reusing, supervising, delegating, recovering, releasing, or closing an isolated repository workspace. Enforces one task per workspace through repo vcs. Not for work already isolated under a verified matching owner and objective.
    - alias: using-git-worktrees → load with name=branch-lifecycle-worktree
  - code-quality — Use only when unsure which code-quality child skill applies — it routes to the child. For a concrete quality action, load that child directly.
  - code-quality-contracts — Use when changing production behavior, tests, policy gates, validators, docs, or exceptions where correctness, hidden debt, magic constants, stale contracts, or silent failures could ship. Not for cosmetic changes that cannot affect behavior, proof, observability, policy scope, or a public contract.
    - alias: quality-contracts → load with name=code-quality-contracts
  - code-quality-debug — Use when encountering a bug, test failure, production incident, unexpected behavior, performance issue, build failure, or integration failure before proposing fixes. Not for cases where root cause is already proven by reproducible evidence and a minimal fix target is known.
    - alias: systematic-debugging → load with name=code-quality-debug
  - code-quality-tdd — Use when implementing any feature or bugfix, before writing implementation code, to turn the Purpose-First contract into executable proof. Not for pure refactors, docs-only, test-only, formatting, or compiler-directed migrations with no behavior change.
    - alias: test-driven-development → load with name=code-quality-tdd
  - code-quality-verify — Use when about to claim work is complete, fixed, passing, ready to commit, or ready for PR, especially after code, docs, config, or validator changes. Not for answer-only work or one no-repo-consequence command that changes no repository artifact.
    - alias: verification-before-completion → load with name=code-quality-verify
  - nix-dev-tooling — Use when editing *.nix, diagnosing Nix closures, or choosing lefthook / alejandra / statix / deadnix / nom / nix-tree / nix-locate beyond the using-skills Nix startup gate. Not for ordinary repo commands once repo check nix already passed.
    - alias: nix-tooling → load with name=nix-dev-tooling
    - alias: nix-quality → load with name=nix-dev-tooling
  - research — Use when starting scoped research that should progress from an outline through deep evidence collection to a durable report. Not for final architecture/adoption decisions or local implementation planning.
  - research-deep — Use when executing item-by-item deep research from an outline into structured evidence files with resumable batches, source quality screening, validation, and synthesis handoff. Not for preliminary outline creation or final implementation planning.
  - research-report — Use when validated deep-research evidence must be synthesized into a durable source-backed report. Not for collecting missing evidence or making adoption and implementation decisions.
  - research-to-implementation — Use when a task needs external research, local source tracing, benchmark comparison, architecture pattern extraction, agent-role design, self-evolution design, memory/planning systems, or a grounded implementation plan. Not for ordinary bugfixes or bounded implementation work where local behavior is already clear.
  - source-tracing — Use when source, runtime path, data origin, config flow, generated artifacts, or ownership must be traced before claiming behavior present, partial, obsolete, or missing — including conversational answers that call anything dead, unused, obsolete, legacy, superseded, or zero-callers; status words are classification claims. Not for bug symptoms with a known failure; use code-quality-debug and root-cause tracing for those.
    - alias: runtime-path-tracing → load with name=source-tracing
    - alias: provenance-tracing → load with name=source-tracing
  - version-control-with-jj — Use when a repository uses jj and any repository-state read, mutation, workspace action, synchronization, recovery, or publication is needed. Enforces the repository-owned repo vcs facade and deliberate one-transition reasoning. Not for non-VCS tasks.
    - alias: using-jj → load with name=version-control-with-jj
  - workflow — Use only when unsure which workflow child skill applies — it routes to the child. For a concrete workflow action, load that child directly.
  - workflow-check-existing — Use when adding or changing a capability surface such as a public function, API, command, prompt, workflow, schema/helper, policy, or reusable instruction. Not for pure formatting, refactoring, or test-only changes that do not alter a contract or reusable surface.
    - alias: existing-capability-first → load with name=workflow-check-existing
  - workflow-discover — Use when a request needs product/design exploration, unclear requirements, multiple viable approaches, UI/UX choices, naming/ownership decisions, or new behavior whose intent is not yet bounded. Not for obvious bug fixes, small config changes, mechanical edits, or operator-directed tasks that are mechanically specified with exact target, behavior, constraints, and acceptance evidence.
    - alias: brainstorming → load with name=workflow-discover
  - workflow-execute — Use when executing a written implementation plan in the current session. Not for plans that need per-task subagent implementers and review gates — use multi-agent-work-orchestrate (alias subagent-driven-development) instead.
    - alias: executing-plans → load with name=workflow-execute
  - workflow-goal — Use when the user explicitly asks to create, write, refine, inspect, continue, or finish a durable goal for multi-turn autonomous work. Not for ordinary one-shot requests, vague discussions, or implementation plans that only need docs/plans.
    - alias: goal-setting → load with name=workflow-goal
    - alias: write-goal → load with name=workflow-goal
    - alias: goals → load with name=workflow-goal
  - workflow-plan — Use when you have a spec or requirements for a multi-step task, before touching code. Not for single-step changes, trivial edits, or work with fewer than 3 tasks where decomposition adds overhead.
    - alias: writing-plans → load with name=workflow-plan
  - workflow-polyrepo-workspace — Use when work spans multiple independent git repositories coordinated by a workspace or consolidation authority (repo metadata, manifest.yml, meta-repo, or repo-of-repos layout), including scope selection, status, bootstrap, migration, or fan-out commands. Not for work confined to one git root or uncoordinated repositories with no declared authority.
    - alias: polyrepo-workspace → load with name=workflow-polyrepo-workspace
    - alias: ws-workspace → load with name=workflow-polyrepo-workspace
  - workflow-quarry-port — Use when finding or porting algorithms from a read-only donor tree (quarry, vendor snapshot, archived service) into this repo. Not for running the donor in production, full product integration, or trivial one-file copies with no contract change.
    - alias: quarry-port → load with name=workflow-quarry-port
    - alias: donor-port → load with name=workflow-quarry-port
    - alias: find-donor → load with name=workflow-quarry-port
  - workflow-work-harness — Use when creating, validating, continuing, taking over, or finishing disk-first Purpose-first work packets (purpose.contract.json, work.spec.json with EARS, evidence.bundle.json). Not for purely cosmetic self-contained edits.
    - alias: work-harness → load with name=workflow-work-harness
    - alias: disk-work-contract → load with name=workflow-work-harness
- **[review]**
  - code-review — Use only when unsure which code-review child skill applies — it routes to the child. For a concrete review action, load that child directly.
  - code-review-receive — Use when receiving code review feedback, especially before implementing reviewer suggestions or resolving disputed technical comments. Not for solo work with no reviewer present, or trivial cosmetic comments that do not affect behavior.
    - alias: receiving-code-review → load with name=code-review-receive
  - code-review-request — Use when completing tasks, implementing major features, or before merging to verify work meets requirements. Not for throwaway branches, already-merged work, or single-line changes below the review threshold.
    - alias: requesting-code-review → load with name=code-review-request
  - redteam — Use when the user asks for advisory review, adversarial review, plan review, security audit, or cross-model critique. Not for in-flow redteam steps — each Purpose-First skill forwards to the right mode itself.
- **[writing]**
  - instruction-authoring — Use only when unsure which instruction-authoring child skill applies — it routes to the child. For a concrete authoring action, load that child directly.
  - instruction-authoring-instructions — Use when changing prompts, AGENTS.md, CLAUDE.md, MCP/tool instructions, skills, governance docs, or instruction surfaces where wording can change agent behavior. Not for human-facing docs or prose (use instruction-authoring-prose) or skill lifecycle work (use instruction-authoring-skills).
    - alias: instruction-writing → load with name=instruction-authoring-instructions
  - instruction-authoring-prose — Use when creating or revising docs, plans, records, PR text, handoffs, or other prose that should be sparse, direct, and low-context. Not for code changes, log output, status strings, or agent-facing instruction surfaces (use instruction-authoring-instructions for those).
    - alias: human-writing → load with name=instruction-authoring-prose
- **[orchestration]**
  - multi-agent-work — Use only when unsure which multi-agent-work child skill applies — it routes to the child. For a concrete dispatch or orchestration action, load that child directly.
  - multi-agent-work-dispatch — Use when 2+ independent tasks, failures, research lanes, exploration lanes, or path-scoped investigations can run in separate ownership lanes; pair with branch-lifecycle-worktree before any lane may edit files. Not for shared-root-cause failures, whole-system tracing, or tasks requiring the same file.
    - alias: dispatching-parallel-agents → load with name=multi-agent-work-dispatch
  - multi-agent-work-orchestrate — Use when executing a written implementation plan, or dispatching 2+ independent implementation tasks (research, audit, exploration, or coding lanes), through implementer/review/fix/integration gates. Not for ad hoc parallel failures without a written plan (use dispatch) or small inline work when subagents are unavailable.
    - alias: subagent-driven-development → load with name=multi-agent-work-orchestrate
  - purpose-messaging-root — Use when Purpose should soft-notice, settle dead lanes, assign leftover work via the swarm bus, land through repo vcs, or invite a development team into an agent's leased worktree. Not for inventing merges, stealing live foreign leases, or bypassing repo vcs.
  - swarm-messaging — Use when two or more agents, models, clients, or independent threads need reliable workspace-scoped coordination through the durable repo-memory swarm bus. Not for durable evidence, secrets, or remote hosts without MCP gateway access.
- **[diagnostics]**
  - monitoring — Use when debugging, investigating, or verifying system behavior that requires querying metrics, logs, or health signals from monitoring backends (VictoriaMetrics, Prometheus, Kubernetes, Longhorn, CNPG, Holmes, or any registered provider). Not for general debugging without metrics — use code-quality-debug first.

**Prepared-opposer review:** use "/redteam" or call downstream `mcp_tool_call(server=redteam, tool=redteam_run, arguments={ mode, input })`. Valid modes: review, architect, plan, decision, bughunt, verify, hack, ultrareview, harvest. Each result includes a jobId for downstream trace/result reads.

## Templates and scoped instructions

`install_skills` exposes template hints for plans, specs, evidence records, runbooks, and scoped `AGENTS.md` files. Nested scoped `AGENTS.md` files (e.g. `docs/AGENTS.md`) can also carry this managed block; pass them as `instructionFiles`.

Purpose-First artifact homes are the default repo normalizer: plans use `docs/plans/`, evidence and policy/control records use `docs/records/`, ADRs use `docs/adr/`, specs use `docs/specs/`. Framework names and control IDs stay repo-local. Plan-based workfiles from the disk-first work harness live under `docs/work/<change-id>/` as `purpose.contract.json`, `work.spec.json`, and `evidence.bundle.json`.

## Repo instruction sync

Compute the current bundle hash from `list_skills.bundleHash` and the instruction-block hash from `install_skills.agentsBlock.hash`. If the active repo `AGENTS.md` does not contain a managed block with bundle hash `d58f229ad264` and the current instruction hash, run `install_skills` to refresh it. Preserve all handwritten content outside the managed block.

## This block is managed

Do not edit manually. Refresh with `install_skills`.
<!-- END purpose-tool skills -->
<!-- prettier-ignore-end -->
<!-- markdownlint-enable -->
