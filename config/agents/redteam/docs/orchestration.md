# Redteam orchestration (Claude reads this)

You run slash commands. The user speaks plainly; you translate to `panel.mjs` flags.

## Operator commands (Codex-style)

| Command | Use |
|---------|-----|
| `/redteam:setup` | Harness health check |
| `/redteam:provider-status` | Provider config, live `/models`, lineage, and bench evidence status |
| `/redteam:status` | Active/recent jobs — **use instead of polling** |
| `/redteam:result <job-id>` | Final merged JSON for a completed job |
| `/redteam:cancel <job-id>` | Stop a background panel |
| `/redteam:bench` | Discover/benchmark lane candidates for routing |

## Commands — when to use what

| User intent | Slash command | Notes |
|-------------|---------------|-------|
| Review code/diff before shipping | `/redteam:review` | Default. Lean loop: 1–2 lineages → fix → repeat. |
| Review architecture / ADR / system design | `/redteam:architect` | Forces `--lane architect`; uses bench-backed architect candidates when evidence exists. |
| Security / exploit paths only | `/redteam:hack` | Not review with a focus flag — dedicated command. |
| Review an implementation plan | `/redteam:plan` | Grounding, sequencing, falsifier, and false-completion review. |
| Review a decision / ADR | `/redteam:decision` | Option/approach review; doc or pasted prose, not a diff. |
| Hunt bugs across the tree | `/redteam:bughunt` | 2-3 scout models scan candidate files; heavy deep-dives selected hotspots. |
| Find good patterns to import | `/redteam:harvest` | Positive scan vs `main` by default; pass `--base <ref>` to override. |
| Verify a finding or fix | `/redteam:verify` | Refute reported bugs or validate the fix with a different lineage. |
| Deep pre-merge sweep | `/redteam:ultrareview` | Multi-lens + optional verify. |
| Refresh model routing evidence | `/redteam:bench --run --write` | Writes `model-bench.json`; routing uses passed candidates with a distinct failover. |
| Let an LLM rank eligible lane candidates | `--lane-planner-model provider/model` | Planner may reorder candidates only; deterministic code rejects unavailable, unbenchmarked, or same-lineage failover choices. |

After any review, present findings and STOP. Ask which items to fix before editing; redteam is read-only.

## User language → flags (you set these)

| User says | You pass |
|-----------|----------|
| quick / one opinion / sanity-check | `-n 1` + pick lineage (see `docs/lineages.md`) |
| review my changes (no size) | omit `-n` (panel default = 2 stratified lineages) |
| two models / pair of critics | `-n 2` |
| triage / three | `-n 3` or `--package triage` |
| audit / deeper / five | `--package audit` |
| full panel / all lineages | `--package audit` or `-n 10` |
| use qwen / deepseek + minimax | `--models qwen,deepseek,minimax` |
| vs main / against main | `--base main` |
| verify / kill false positives | `/redteam:verify` or `--verify` |
| focus on auth / drain path | `--focus "…"` |
| review this plan / plan review / plan file | `/redteam:plan --plan <path>` |
| that ADR about X / doc probably called … | Glob/Grep repo → `/redteam:architect --input <path>` |
| pasted decision | `--text "…"` |

## Harness entrypoint

```bash
node "${CLAUDE_PLUGIN_ROOT}/scripts/panel.mjs" [flags…]
```

Plan adds `--mode plan` or `--plan <file>`. Decision adds `--mode decision`. Hack adds `--mode security`. Ultrareview adds `--ultrareview`.

## Lane Routing

Default panel selection first tries a bench-backed lane route:

```text
configured alias + live /models + metadata + passing bench row + distinct same-lane failover
```

If that contract is not satisfied, panel falls back to the existing stratified
lineage picker. Use `--lane architect|review|deep-review|scout|builder|verify|summarize`
to force a lane, `--bench <file>` to test a bench artifact, or
`--no-lane-route` to disable bench-backed routing.

An optional planner model can rank the eligible set:

```bash
node "${CLAUDE_PLUGIN_ROOT}/scripts/panel.mjs" --lane architect --lane-planner-model provider/model
```

You can also set `REDTEAM_LANE_PLANNER_MODEL=provider/model`. Use
`--no-lane-planner` to disable that environment default for one run.

The planner is advisory. It sees only the already eligible candidate list and
must return `{"primary":"provider/model","failover":["provider/model"],"reason":"..."}`.
Deterministic code still enforces configured alias + live `/models` + metadata +
passing bench row + distinct failover. If the planner invents a model, picks an
unbenchmarked candidate, or uses a same-lineage failover, redteam logs the
rejection and falls back to the score-ranked bench route.

## Discipline

- Invoke the slash command; do not hand-roll `runner.mjs` unless customizing a one-off prompt.
- **Execution:** follow [`docs/execution.md`](execution.md) — background for slow runs; **never poll** results dir, `tail -f`, or `BashOutput` loops.
- Present verdict `summary` + findings when the run completes (foreground or notification).
- Provider flakiness is normal — rotate lineage or widen panel; do not chase one failed model.

## Canonical config files

| File | What |
|------|------|
| `docs/execution.md` | Foreground vs background; do not poll |
| `models.json` | Lineage policy, provider order, narrow model params |
| `model-bench.json` | Generated lane evidence from `/redteam:bench --run --write` |
| `docs/lineages.md` | When to pick which lineage (operational selection hints) |
| `scripts/panel.mjs` | Packages (`triage`/`audit`/`harvest`), default `-n 2`, fan-out behavior |
| `scripts/companion.mjs provider-status` | Provider health without model invocation |
| `prompts/route-pdd.md` | Tool-free planner prompt for optional lane ranking |
| `prompts/*.md` | What each `--mode` asks models to do |
