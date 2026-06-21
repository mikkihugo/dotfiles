# Redteam

Cross-model adversarial review for code, plans, architecture, decisions, and
bug hunts. Redteam is read-only during review turns: it reports findings first
and waits for an explicit fix request before any code changes.

## Feature Surface

| Need | Command | Route |
|------|---------|-------|
| Review a code diff before shipping | `/redteam:review` | Default stratified panel, or bench-backed `review` lane |
| Critique architecture, ADRs, and system shape | `/redteam:architect` | Bench-backed `architect` lane |
| Review implementation sequencing and falsifiers | `/redteam:plan` | Plan prompt, usually `architect` lane |
| Review a decision or approach | `/redteam:decision` | Decision prompt |
| Security-only adversarial pass | `/redteam:hack` | Security prompt |
| Whole-tree bug discovery | `/redteam:bughunt` | Scout lane then deep-review lane |
| Verify or refute a reported finding | `/redteam:verify` | `verify` lane |
| Deep pre-merge sweep | `/redteam:ultrareview` | Multi-lens review and optional verify |
| Harvest useful patterns | `/redteam:harvest` | Positive scan vs base |
| Refresh routing evidence | `/redteam:bench --run --write` | Updates `model-bench.json` |

Operator commands:

| Command | Purpose |
|---------|---------|
| `/redteam:setup` | Check harness, command, prompt, model policy, and bench readiness |
| `/redteam:provider-status` | Check provider catalog health, configured aliases, and bench evidence |
| `/redteam:status` | Show background jobs; `--wait` blocks without polling files |
| `/redteam:result <job-id>` | Read the completed merged JSON result |
| `/redteam:cancel <job-id>` | Stop a background panel |

## Lane Routing

`model-bench.json` is generated evidence. A lane route is used only when the
candidate is configured locally, appears in live provider inventory, has
metadata, passed the bench smoke, and has a distinct-lineage failover.

`models.json` is the canonical routing policy:

- `lineage_provider_seeds` defines provider order per lineage.
- `direct_provider_by_lineage` puts direct providers before generic fallbacks.
- `provider_priority` is compatibility fallback for older paths.
- `disabled_lineages`, `deprioritized_lineages`, and `disabled_models` preserve
  trace-backed exclusions without deleting the lineage policy.

Optional planner routing is advisory only. `--lane-planner-model provider/model`
or `REDTEAM_LANE_PLANNER_MODEL` lets a model rank already eligible candidates,
but deterministic code rejects invented models, same-lineage failovers, and
fallback-provider choices when a higher-priority provider is eligible.

## Execution Discipline

Long reviews should run in the background. Do not poll results directories or
tail output. Use `/redteam:status`, `/redteam:status <job-id> --wait`, and
`/redteam:result <job-id>`.

Foreground runs print `=== REDTEAM EXIT status=<code> ===` at process exit.
Present the JSON summary and findings, then stop and ask before fixing.

The symbol hallucination gate is enabled by default. Findings that assert
code-like identifiers absent from the repo are annotated with
`[HALLUCINATED SYMBOLS]`; set `REDTEAM_HALLUCINATION_GATE=0` only for an
explicit diagnostic run where grep-based symbol checks are known to be noisy.

## Canonical Files

| File | Role |
|------|------|
| `docs/orchestration.md` | Command selection and user-language translation |
| `docs/execution.md` | Foreground/background rules and no-poll contract |
| `docs/lineages.md` | Lineage selection, speed, and reliability notes |
| `models.json` | Lineage policy and provider order |
| `model-bench.json` | Current bench evidence for lane routing |
| `prompts/*.md` | Mode-specific review contracts |
| `scripts/panel.mjs` | Panel orchestrator |
| `scripts/lane-bench.mjs` | Bench evidence writer |
| `scripts/companion.mjs` | Setup/provider-status/status/result/cancel operator surface |
