# Lineages — when to pick which (Claude reads this)

**Canonical policy:** read `models.json` at plugin root.

- `lineages` — allowed lineage names for panel selection.
- `lineage_provider_seeds` — ordered provider preference per lineage. This is
  the chain contract; do not infer a global fallback order.
- `disabled_lineages` — excluded from automatic random/backfill/scatter selection
  after trace evidence. Explicit `--models` can still target them for diagnosis.
- `deprioritized_lineages` — kept available but moved to the end of automatic
  candidate pools.
- `disabled_models` — exact provider/model refs skipped inside fallback chains
  after confirmed disabled/broken-provider evidence.
- `model_params` — narrow provider/model overrides when catalog metadata cannot
  express the working wire format.

Do not maintain concrete model ids here. Automatic panel/scout selection uses
configured Kimi aliases for metadata and live provider `/models` only as a
liveness/inventory signal. A model that appears in `/models` but has no configured
alias is not selected automatically because context/tool/thinking metadata is
unknown. Use explicit inventory/debug paths for live-only models, then add an
alias or metadata override before normal routing.

Invocation semantics:

- `--lineage kimi` uses the lineage chain.
- bare `provider/model` tries that direct model first, then falls through the same lineage chain on temporary quota/provider failure.
- `--model provider/model` is an exact pin; it must not fall through or silently substitute another model.

## Default lean loop (code review)

Rotate **1–2 fast strong critics** per round; fix; repeat. Reserve width for final sign-off.

| Situation | Lineage | Why |
|-----------|---------|-----|
| Fast reliable coding pass | minimax | Fast, dependable direct lineage |
| Strong coding / agentic | qwen | Strong coding lineage; current automatic chain prefers Ollama first |
| Deep real-world / agentic | deepseek | Deprioritized after 2026-06-20 trace waste; use explicitly only when needed |
| Cheap long-horizon eng | glm | Cost-efficient; results vary by provider |
| Agentic reasoning | kimi | Reliable general critic |
| Verify / refute findings | google | Fast verifier; rate-limited — low volume only |
| Math / reasoning angle | gpt-oss | Efficient reasoning lineage |
| Multi-agent perspective | nemotron | Disabled for automatic selection until a provider returns verdicts |
| Broad semantic (slow) | mistral | Heavy; use sparingly |

## Speed classes

- **Fast:** minimax, google, gpt-oss, nemotron — good for `-n 1` quick passes.
- **Slow:** deepseek, mistral, qwen — budget time; do not re-run on timeout.

## Reliability (expect flakes)

- `opencode-go/*` and `minimax` — intermittent `fetch failed`.
- `ollama-cloud/*`, `kimi-for-coding`, `google` — generally more reliable.
- `opencode-go/*` has per-model format support. In OpenCode code, `format=openai` means
  `/responses`, while `format=oa-compat` means `/chat/completions`. Live checks showed
  `qwen3.7-max` rejects `oa-compat` (`not supported for format oa-compat`) and
  `/responses` returns 404, while Anthropic `/messages` works. Redteam therefore keeps
  `opencode-go` OpenAI-compatible by default and uses model-level overrides for exceptions.
- Provider order is per lineage in `lineage_provider_seeds`.
- GLM is `zai` → `ollama-cloud` → `opencode-go` → `alibaba-token-plan`.
- Qwen is `ollama-cloud` → `opencode-go` → `alibaba-token-plan` because
  2026-06-20 trace `nosession-RSZcsS` showed Ollama returned a verdict quickly
  after opencode/alibaba attempts wasted calls.
- `opencode-go/deepseek-v4-pro` is disabled in the chain policy because it
  returned `401 Model is disabled` in trace `nosession-RSZcsS`.
- Minimax is `minimax-coding-plan` → `ollama-cloud` → `opencode-go`.
- Kimi is managed Kimi Code → `ollama-cloud` → `opencode-go` → `alibaba-token-plan`.
- Minimax is not a GLM fallback. Alibaba is not a Minimax fallback unless a
  lineage seed explicitly says so.
- A failed lineage is not a harness bug; switch or use panel diversity.

## User names a lineage

User: *"use qwen"* → `--models qwen`.

User: *"qwen and minimax"* → `--models qwen,minimax`.

User does not name lineages → omit `--models`; panel picks stratified random lineages (`-n` default 2).
