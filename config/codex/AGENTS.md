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

## Codex v2 subagent lifecycle

When `spawn_agent` reports `agent thread limit reached`, inspect the live agent
tree before declaring subagents unavailable. In multi-agent v2, `interrupt_agent`
stops only the current turn; the agent identity remains reusable and should not
be described as permanently consuming an unreleasable slot.

An interrupted or completed resident is normally eligible for eviction on the
next spawn, but an active turn or queued mailbox input can prevent eviction. If
an obsolete agent blocks capacity:

1. send a short `followup_task` that asks it to finish immediately, clearing
   pending mailbox input;
2. wait for completion, or interrupt that drain turn after it starts;
3. retry the requested spawn;
4. verify the requested model and reasoning override from the successful tool
   result instead of substituting another model silently.

If behavior still disagrees with the exposed tool contract, inspect the current
Codex source or manual before generalizing from one failed call.

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

## Managed Tool Instructions

<!-- markdownlint-disable -->
<!-- prettier-ignore-start -->
<!-- BEGIN purpose-tool skills (47440c934104) -->
Instruction block hash: f7f85657c851
## Purpose-First hard gate

Before any repo, runtime, infra, GitOps, Kubernetes, policy, planning, debugging, or implementation task:

1. **Load `using-skills` first.** Call `load_skill({ name: "using-skills" })` before any other tool or answer.
2. **Follow the skill it tells you to load.** `using-skills` routes your task to the right rule.
3. **Router-only clients:** use `mcp_tool_call(server=purpose_tool, tool=purpose_tool_load_skill, arguments={name:"using-skills"})`.

## What this means

Purpose-First Development: purpose → contract test → evidence on disk.
No behavior, plan, prompt, skill, code, test, or operational change without a clear purpose, consumer, contract, evidence, and falsifier.

**DOUBT:** Process doubt is ordinal 0–4 on claims. Load `skill_file_read({ name: "purpose-first", path: "references/doubt-doctrine.md" })` before ship or review gates. Never use 0.98-style self-confidence for merge decisions.

## Quick path

- **Start:** `load_skill({ name: "using-skills" })`; router fallback: `mcp_tool_call(server=purpose_tool, tool=purpose_tool_load_skill, arguments={name:"using-skills"})`.
- **Behind CentralCloud proxy:** direct wrappers are supported shortcuts named like `purpose_tool__load_skill`. If a wrapper is hidden, absent, or fails with a wrapper/schema/tool-name error, retry through `mcp_tool_call(server=purpose_tool, tool=purpose_tool_<tool>, arguments={...})` before declaring the downstream tool unavailable.
- **Setup / refresh:** `list_skills` for `bundleHash`; `install_skills` for `agentsBlock.full`; `check_agents_block({ repoRoot })` to verify installed instruction blocks. Router tools: `purpose_tool_list_skills`, `purpose_tool_install_skills`, `purpose_tool_check_agents_block`.
- **Redteam:** `redteam_run({ mode, input })`; router tool: `purpose_tool_redteam_run`; modes: review, architect, plan, decision, hack, bughunt, harvest, verify, ultrareview. Poll long jobs with `redteam_job_trace({ jobId })` / `redteam_job_result({ jobId })` or router tools `purpose_tool_redteam_job_trace` / `purpose_tool_redteam_job_result`.
- **RTI:** `purpose_research_to_implementation` translates research evidence into local options; router tool: `purpose_tool_purpose_research_to_implementation`; read back with its job trace/result tools.

## How to use skills

- **Find the skill:** run `list_skills`. Match your task to the skill trigger.
- **Load it:** call `load_skill({ name })`. Aliases resolve to canonical names (e.g. `brainstorming` → `workflow-discover`).
- **Router-only gateway:** do not hardcode generated wrapper names. Use `mcp_tool_call` with the exact downstream tool name. Wrapper failure is not downstream failure unless the same call fails through `mcp_tool_call`.

## CentralCloud MCP discovery gate

- **Operational reads:** when the CentralCloud MCP gateway is available, inspect `mcp_router_hints` before Forgejo, Kubernetes, Flux, logs, metrics, memory, browser, or other remote-system reads.
- **Discovery:** use discover -> describe selected listing -> checkout: grouped search tools first, `mcp_tool_describe` when schema detail matters, then direct wrapper or `mcp_tool_call` with the exact downstream server and tool. Do not infer that a capability is missing from an absent direct wrapper or a failing direct wrapper.
- **Local grounding:** when work depends on local code behavior, use workspace scope/tools first when a workspace authority exists, then repo metadata/taxonomy/runbooks, then repo-declared code-intel/repo-map/feature-map tools when present, `ast-grep` for structural matches when available, and `rg` for text fallback. Record the scope, metadata source, path, symbol, test, trace, or runtime proof used.
- **Docs grounding:** when work depends on current dependency behavior, upstream repo structure, framework/API docs, or repo/wiki context, use `search_docs` first. Prefer DeepWiki first for upstream repo/wiki/dependency architecture; use Context7 for library/framework/API docs and examples. Do this before guessing from memory. Treat docs as external evidence; local source, tests, traces, or runtime state prove local behavior.
- **Boundary:** use provider MCP tools for remote state. Use the local shell for repository edits and repo-owned verification, or when MCP lacks the required capability; state the fallback.

## Critical rules for every task

- **Scoped instructions:** before editing a path, look upward for the nearest `AGENTS.md` / `CLAUDE.md` / host instruction file. Deeper files override parent files. Update the scoped file when your edit changes ownership, workflow, verification, runtime wiring, public contract, or generated artifacts.
- **VCS orchestration:** use the repository's declared VCS orchestration surface exclusively for all VCS reads, mutations, workspace lifecycle, remote synchronization, and publication. Native `git` and `jj` commands are forbidden outside the facade implementation. If no facade exists, add a minimal repository-owned facade before any VCS action; do not fall back to agent-facing native commands. Detect and verify the declared surface from root instructions and the repository command registry.
- **VCS facade backend:** inside the facade implementation, use jj when `.jj/` exists; otherwise use Git only when the current path is a validated Git worktree or repository root. Do not classify a directory as a Git repository from an unvalidated ancestor `.git` marker. Git in jj repos is limited to documented interop inside the facade, such as CI mirrors, remotes, object inspection, or publication.
- **Worktree guard:** before multi-step, multi-file, branch-scale, or concurrent editing work on `main`, `master`, or a shared primary checkout, load `branch-lifecycle-worktree` and create an isolated session workspace. Reuse an existing workspace only for the same task after verifying its owner and state. Refresh remote state through the declared VCS facade and create from the freshly fetched integration revision, never an arbitrary current checkout or stale local bookmark. Use `jj_workspace_spawn` for jj repos and `git_worktree_add` for Git repos.
- **Workspace closure:** before handoff, inventory session-created and stale workspaces. Close a workspace only when its work is integrated or explicitly abandoned, clean, and not owned by a live process. Prove every non-empty task commit or change is reachable from the integration branch; Filesystem cleanliness alone is insufficient. If reachability fails, preserve and report the workspace as unintegrated. Before closing a workspace from another registered workspace, refresh that workspace to the integrated revision and verify its current managed instruction hash and declared VCS facade/closure command; a bundle hash alone is insufficient. Fail closed when either proof is missing. Preserve and report dirty, unintegrated, or active workspaces. Unregister through the selected VCS backend; if Purpose Tool returns `cleanup_required`, route `directory_preserved_at` and `preservation_record_at` through the repository's declared VCS cleanup authority and do not use raw recursive deletion or claim closure while either remains.
- **Workspace identity:** distinguish repository root, current working directory, registered workspace name/path, and shared VCS store. A Git worktree or Jujutsu workspace is a checkout view, not an independent repository. Resolve commands against the intended registered workspace; inventory and cleanup through the canonical repository registry and workspace root.
- **Publication closure:** when the user authorizes commit, merge, and push, continue through description/commit, integration, guarded publication, remote revision readback, and clean session-workspace removal. Do not stop at a verified diff. Inventory generated/build garbage; remove only reproducible, unowned artifacts within scope, and report anything preserved.
- **Repo command layers:** root instructions name the generated `repo` command contract; implementation-scope instructions own backend tools; deeper scoped AGENTS files name local declared `repo` verification commands. Follow the nearest scoped layer. Do not keep aliases for an implementation tool as a public command surface.
- **Repo commands:** resolve and enter the intended repository root, then start with `repo help` and invoke only declared `repo` commands for focused or repo-wide operations. The repository command contract owns command names, argument shapes, and Nix-backed implementations. A Nix-backed repository must make the generated CLI executable in its canonical shell and prove `nix develop path:. --command repo help`. If a recurring operation is missing, add it to the contract and regenerate `repo`; do not teach agents an implementation-tool workaround.
- **Command-surface ownership:** treat generated `repo` as the stable agent-facing facade for repository operations, including checks, VCS, discovery, repo maps, feature maps, and structural search when declared. A declared `repo vcs` group owns status, mutation, workspaces, remote sync, and publication; do not duplicate publication under `ops`. Reserve `ops` for runtime and service operations. Purpose Tool owns generic doctrine and compilation; repository instructions record only concrete mappings, constraints, and exceptions.
- **Nix environment:** if the resolved repository root has `flake.nix`, declared `repo` commands must run inside `nix develop path:.` from that root. Do not omit the flake installable or rely on implicit `.` discovery: ancestor VCS markers can redirect Nix outside a jj workspace. A repo-owned nix-direnv entrypoint must use `use flake path:.`; do not accept `NIX_DIRENV_DID_FALLBACK=1` as verification evidence. For `shell.nix` or `default.nix` without a flake, use the repo-declared Nix or direnv entrypoint. Check `IN_NIX_SHELL`. Fail loudly outside Nix. Use direct package-manager commands only for dependency installation or one-off work with no declared repo command.
- **Durable memory:** if prior decisions, runbooks, incidents, or operational memory matter, call `search_memory` first. Share findings through `operations_memory` with evidence, named consumer, and scope.
- **Repo observations:** before finishing non-trivial work, explicitly account for harvestable side observations from research, exploration, debugging, review, or implementation: append a valid `OBSERVATIONS.md` entry and verify it, or state that no harvestable side observation was found. Use the declared `repo` observation check when available.
- **Repo-local skills:** `.agents/skills/` are overlays only — repo paths, verify commands, org facts on top of a base skill. Load the Purpose Tool base first, overlay second. Do not embed repo routes in the managed block; if generic, improve Purpose Tool instead.

## MCP tools you will need

- **Skill guidance:** `load_skill`, `list_skills`, `skill_file_read`, `skill_manifest`, `file_read`, `install_skills`, `check_agents_block`.
- **Local jj workspaces:** `jj_workspace_spawn`, `jj_workspace_list`, `jj_workspace_inspect`, `jj_workspace_adopt_root`, `jj_workspace_forget`, `jj_workspace_prepare_abandon`, `jj_workspace_confirm_abandon`, `jj_classify_command` (mounted canonical jj repository workspaces on this MCP host only).
- **Research-to-implementation:** `purpose_research_to_implementation` and its job-trace/result readers.
- **Redteam:** `redteam_run`, `redteam_job_trace`, `redteam_job_result`.
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
  - branch-lifecycle — Use only when unsure which branch-lifecycle child skill applies — it routes to the child. For a concrete branch or worktree action, load that child directly.
  - branch-lifecycle-finish — Use when implementation is complete, verification passes, and the remaining decision is how to integrate, merge, PR, clean up, or finish the branch. Not for throwaway branches, docs-only single commits, or trivial edits where merge/PR ceremony adds no value.
    - alias: finishing-a-development-branch → load with name=branch-lifecycle-finish
  - branch-lifecycle-worktree — Use when creating, reusing, recovering, or cleaning up isolated Git worktrees or jj workspaces; when branch-scale work, parallel agents, generated wrappers, crash recovery, or dirty checkout isolation matters. Also use when optional isolation is skipped for narrow work but the tree is shared with another possibly-concurrent agent. Not for already-isolated workspaces or single-file low-risk edits in a verified unshared checkout.
    - alias: using-git-worktrees → load with name=branch-lifecycle-worktree
  - code-quality — Use only when unsure which code-quality child skill applies — it routes to the child. For a concrete quality action, load that child directly.
  - code-quality-contracts — Use when changing production behavior, tests, policy gates, validators, docs, or exceptions where correctness, hidden debt, magic constants, stale contracts, or silent failures could ship. Not for cosmetic changes that cannot affect behavior, proof, observability, policy scope, or a public contract.
    - alias: quality-contracts → load with name=code-quality-contracts
  - code-quality-debug — Use when encountering a bug, test failure, production incident, unexpected behavior, performance issue, build failure, or integration failure before proposing fixes. Not for cases where root cause is already proven by reproducible evidence and a minimal fix target is known.
    - alias: systematic-debugging → load with name=code-quality-debug
  - code-quality-tdd — Use when implementing any feature or bugfix, before writing implementation code, to turn the Purpose-First contract into executable proof. Not for pure refactors, docs-only, test-only, formatting, or compiler-directed migrations with no behavior change.
    - alias: test-driven-development → load with name=code-quality-tdd
  - code-quality-verify — Use when about to claim work is complete, fixed, passing, ready to commit, or ready for PR, especially after code, docs, config, or validator changes. Not for trivial one-liners, single commands with no repo consequence, or pure cosmetic changes.
    - alias: verification-before-completion → load with name=code-quality-verify
  - research — Use when starting scoped research that should progress from an outline through deep evidence collection to a durable report. Not for final architecture/adoption decisions or local implementation planning.
  - research-deep — Use when executing item-by-item deep research from an outline into structured evidence files with resumable batches, source quality screening, validation, and synthesis handoff. Not for preliminary outline creation or final implementation planning.
  - research-report — Use when validated deep-research evidence must be synthesized into a durable source-backed report. Not for collecting missing evidence or making adoption and implementation decisions.
  - research-to-implementation — Use when a task needs external research, local source tracing, benchmark comparison, architecture pattern extraction, agent-role design, self-evolution design, memory/planning systems, or a grounded implementation plan. Not for ordinary bugfixes or bounded implementation work where local behavior is already clear.
  - source-tracing — Use when source, runtime path, data origin, config flow, generated artifacts, or ownership must be traced before claiming behavior present, partial, obsolete, or missing — including conversational answers that call anything dead, unused, obsolete, legacy, superseded, or zero-callers; status words are classification claims. Not for bug symptoms with a known failure; use code-quality-debug and root-cause tracing for those.
    - alias: runtime-path-tracing → load with name=source-tracing
    - alias: provenance-tracing → load with name=source-tracing
  - version-control-with-jj — Use when the local repository has `.jj/` and any VCS read, mutation, remote synchronization, or workspace isolation is needed. Requires a repository-owned VCS facade and forbids agent-facing native jj and Git commands. Not for pure-Git repos (`.git` only, no `.jj`).
    - alias: using-jj → load with name=version-control-with-jj
  - workflow — Use only when unsure which workflow child skill applies — it routes to the child. For a concrete workflow action, load that child directly.
  - workflow-check-existing — Use when adding or changing a capability surface such as a public function, API, command, prompt, workflow, schema/helper, policy, or reusable instruction. Not for pure formatting, refactoring, or test-only changes that do not alter a contract or reusable surface.
    - alias: existing-capability-first → load with name=workflow-check-existing
  - workflow-discover — Use when a request needs product/design exploration, unclear requirements, multiple viable approaches, UI/UX choices, naming/ownership decisions, or new behavior whose intent is not yet bounded. Not for obvious bug fixes, small config changes, mechanical edits, or operator-directed tasks that are mechanically specified with exact target, behavior, constraints, and acceptance evidence.
    - alias: brainstorming → load with name=workflow-discover
  - workflow-execute — Use when executing a written implementation plan in the current session. Not for plans that need per-task subagent implementers and review gates — use subagent-driven-development instead.
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
  - workflow-work-harness — Use when creating or validating disk-first Purpose-first work directories (purpose.contract.json, work.spec.json, evidence.bundle.json) before or after implementation. Not for markdown-only plans without JSON contracts.
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
  - swarm-messaging — Use when two or more agents, models, clients, or independent threads need reliable workspace-scoped coordination through a shared filesystem. Not for durable evidence, secrets, or systems without a shared host filesystem.
- **[diagnostics]**
  - monitoring — Use when debugging, investigating, or verifying system behavior that requires querying metrics, logs, or health signals from monitoring backends (VictoriaMetrics, Prometheus, Kubernetes, Longhorn, CNPG, Holmes, or any registered provider). Not for general debugging without metrics — use code-quality-debug first.

**Prepared-opposer review:** use "/redteam" or call `redteam_run({ mode, input })`. Valid modes: review, architect, plan, decision, hack, bughunt, harvest, verify, ultrareview. Each result includes a jobId for trace/result reads.

## Templates and scoped instructions

`install_skills` exposes template hints for plans, specs, evidence records, runbooks, and scoped `AGENTS.md` files. Nested scoped `AGENTS.md` files (e.g. `docs/AGENTS.md`) can also carry this managed block; pass them as `instructionFiles`.

Purpose-First artifact homes are the default repo normalizer: plans use `docs/plans/`, evidence and policy/control records use `docs/records/`, ADRs use `docs/adr/`, specs use `docs/specs/`. Framework names and control IDs stay repo-local. Plan-based workfiles from the disk-first work harness live under `docs/work/<change-id>/` as `purpose.contract.json`, `work.spec.json`, and `evidence.bundle.json`.

## Repo instruction sync

Compute the current bundle hash from `list_skills.bundleHash` and the instruction-block hash from `install_skills.agentsBlock.hash`. If the active repo `AGENTS.md` does not contain a managed block with bundle hash `47440c934104` and the current instruction hash, run `install_skills` to refresh it. Preserve all handwritten content outside the managed block.

## This block is managed

Do not edit manually. Refresh with `install_skills`.
<!-- END purpose-tool skills -->
<!-- prettier-ignore-end -->
<!-- markdownlint-enable -->
