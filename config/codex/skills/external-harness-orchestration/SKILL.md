---
name: external-harness-orchestration
description: Use when Codex root must delegate implementation to external workers (Kimi CLI or Cursor) while remaining coordinator, verifier, and sole publisher. Not for Codex-internal Default/Plan UI modes or multi-agent v1/v2 lifecycle alone.
---

<SUBAGENT-STOP>
If dispatched as a bounded subagent for a specific task, stop and return to Codex root; do not apply this orchestration skill.
</SUBAGENT-STOP>

# External harness orchestration

**Purpose:** Keep Codex root as coordinator, verifier, and sole publisher when work is delegated outside Codex.
**Consumer:** Codex root sessions that launch bounded Kimi CLI or Cursor workers.
**Failure consequence:** Workers inherit non-portable Responses state, gain VCS/publication authority, or ship unverified changes.
**Falsifier:** Cross-provider child-thread history transfer of Responses `encrypted_content` is proven lossless (including inherited child turns and tool calls), or encrypted reasoning can be disabled for the worker path.

## Roles

- Codex root: coordinator, verifier, and sole publisher. MUST NOT use Codex subagents for delegated work.
- This skill activates only in Codex root. External workers cannot load it, so each worker prompt MUST inline its ownership/evidence boundaries. `<SUBAGENT-STOP>` works only when the full skill is loaded, so Codex root MUST NOT dispatch this skill itself to subagents.
- External workers: receive fresh portable prompts and bounded owned paths. No VCS/publication authority (no commit, land, push, publish, Home Manager activate, secrets edit).
- The no-VCS/no-publication rule is instruction policy, not a sandbox: Kimi CLI and Cursor can technically mutate/publish. Launch each worker with the strongest available least-privilege boundary and keep publication credentials/commands unavailable where practical. The coordinator treats worker state/report as untrusted and verifies local repo VCS state/diff/tests before publication.
- Workers return machine-readable evidence. Coordinator independently verifies before any publication.

## Encrypted content

Provider-bound Responses `encrypted_content` is not assumed portable. Pass unchanged only to a compatible same-upstream opaque replay. MUST NOT be translated to chat/Anthropic/external models or silently stripped from an inherited thread. Otherwise fail closed or start a fresh portable session/prompt containing only transferable instructions/transcript.

Codex Default/Plan and multi-agent v1/v2 are lifecycle/UI modes, not protocol fixes.

## Worker launch

### Kimi CLI (prompt mode)

```text
kimi --model kimi-code/k3 --output-format stream-json --prompt <task>
```

MUST NOT combine `--prompt` with `--auto` or `--yolo`.

Behavior proven by local Kimi 0.28.1: `--prompt` is noninteractive; sessions are created/resumed with `auto` permission; an approval handler auto-approves tool calls and a null question handler is installed, so the worker cannot ask questions; `validateOptions` rejects combining `--prompt` with `--auto` or `--yolo`.

### Cursor (subscription)

Implementation command proven by installed `cursor-agent --help` (2026.07.23-e383d2b) and official Cursor CLI docs:

```text
cursor-agent --print --force --sandbox enabled --output-format stream-json --model <model> <task>
```

`--print` is headless. Without `--force` changes are proposed only and files are not modified; print mode without `--force` silently denies unapproved commands, so implementation needs `--print --force`. `--sandbox enabled` is the strongest current runtime boundary. Project permissions live in `.cursor/cli.json`; deny takes precedence.

Read-only review/plan command (no `--force`):

```text
cursor-agent --print --mode plan --output-format stream-json --model <model> <task>
```

`--sandbox`/`--force` still do not prove exact per-path or VCS isolation. Use task-scoped permissions when available and verify them before launch. If the required write/command boundary cannot be proven, keep Cursor read-only (review/plan command) and use another bounded implementation harness.

Cursor CLI invocation is version-dependent: discover the print/noninteractive/output/model/permission options from `cursor-agent --help` or the actual binary on each host, pin them in the ownership packet, and do not launch if they cannot be proven. Do not invent flags.

Preferred models: `cursor-grok-4.5-high` and non-fast `composer-2.5`.
MUST NOT select `*-fast`.

### Concurrency

Fan-out is resource-budgeted and provider-aware, inside operator hard ceilings. Mikael's hard limits: at most 10 total Kimi agents per Kimi coordinator/swarm including the lead, and at most 30 Kimi agents globally. These are hard ceilings, not targets; resource and independent-lane checks must select a lower live count. Before launching workers, verify current host RAM/headroom and provider capacity with a live memory check. Use multiple external workers only when at least two independent ownership lanes exist and resources allow. Cap each batch to the smaller of independent lanes, verified provider capacity, a conservative host-memory budget, and the remaining operator ceiling. Stop launches before swap/available-memory pressure worsens. Each Kimi launch reserves an agent budget including the lead through the provenance launcher below; the launcher rejects a per-coordinator budget above 10 and fails closed when the global sum of active reserved Kimi budgets would exceed 30. One writer per workspace/file lane.

## Run provenance launcher

Every external worker launch MUST go through the Codex-only launcher `codex-external-run`, owned at `config/codex/bin/codex-external-run.mjs` and installed only under `~/.codex/bin/codex-external-run` (not `~/.agents`, not global PATH). It wraps exactly the proven Kimi/Cursor commands above; do not invent CLI flags.

```text
codex-external-run --harness kimi --root-task-id <root> --parent-task-id <parent> --task-id <task> \
  --coordinator codex-root --workspace <abs-path> --model kimi-code/k3 --agent-budget <n> -- \
  kimi --model kimi-code/k3 --output-format stream-json --prompt <task>
```

- Explicit root/parent/task identity is required at launch; no silent anonymous default. A top-level child may set `parent_task_id` equal to `root_task_id`. Nested external runs inherit `root_task_id` and set their immediate task/lead as `parent_task_id`.
- Each launch creates a crash-recoverable, per-run machine-readable record under `$XDG_STATE_HOME/codex/external-runs` (fallback `~/.local/state/codex/external-runs`) with a 0700 directory and a 0600 record where the platform permits.
- Record provenance: schema version, `root_task_id`, `parent_task_id`, `task_id`, `run_id`, `coordinator`, `harness`, `model`, absolute workspace, declared Kimi agent budget, launcher PID, child PID, start/end timestamps, lifecycle status, and exit/signal result. The record never persists prompt content, command arguments, environment, credentials, or tool output.
- Kimi launches reserve an agent budget including the lead. The launcher rejects a budget above 10, reconciles stale dead-PID records, sums active reserved Kimi budgets, and rejects a launch that would exceed 30 globally. Check-and-reserve runs under an advisory lock with one atomic record file per run; the launcher fails closed if provenance cannot be written or the global reservation cannot be proven.
- Run IDs are collision-resistant generated run IDs, not a uniqueness proof; an existing run record is rejected (the launcher rejects an existing run record rather than overwriting it).
- The launcher injects the declared ancestry/budget into the worker via `CODEX_EXTERNAL_RUN_*` environment variables without logging the task prompt. For Kimi internal swarm children, Kimi's own `parentAgentId` graph supplies immediate agent ancestry while the launcher record anchors the lead session to root/parent/task; the lead must not exceed its reserved total-agent budget.
- repo-memory stores durable outcomes/decisions after completion; it is not the primary transient PID/run registry.

## Ownership packet

Every worker prompt includes exact owned paths, forbidden paths/actions, no VCS/publication authority, acceptance evidence the coordinator will verify, where to write status for repo-memory continuation, and — because external workers cannot load this skill — the worker's ownership/evidence boundaries inlined in full.

## Worker evidence (fail-closed minimum)

Each worker report MUST include: task/lane id, owned paths touched, commands with exit status, test output summary, and unresolved issues. Evidence is advisory/untrusted; no cryptographic signature is needed. Malformed, absent, or incomplete evidence: do not publish — inspect/discard the worker output. Regardless of reported evidence, the coordinator independently reruns status/diff/tests before publication.

## Contract test

`node --test scripts/test-codex-external-harness-skill.mjs`
`node --test scripts/test-codex-external-run.mjs`

## Continuation

Use repo-memory for durable continuation. Do not rely on inherited encrypted reasoning across providers.
