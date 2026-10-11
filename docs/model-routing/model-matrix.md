# Model matrix

Last updated: 2026-10-11 (claude-fbe0939f). Living file. Prices from models.dev cache 2026-09-27
unless noted (d=1 stale/single-source). Operator decisions: GLM-5.3-Express = GLM-5.3-Flash;
Grok = 4.7 (not grok-build); all subscriptions usable by towers (no ToS gating);
failover for the current towers stays MiniMax coding-plan ↔ backup until the role table below is applied.

## Model facts

| Model | Where (config ids) | List $/1M in/out | Ctx | Quality signal | Token efficiency | Best for |
|---|---|---|---|---|---|---|
| Claude Opus 5.5 | Claude Max (Claude Code); add opencode/anthropic API | 4/20 | 1M | SWE-Pro 89.9 (vendor, d=2) | — | Hard bugs, big refactors |
| GPT-6.1 Sol / GPT-6 Astra | ChatGPT Pro (codex); add opencode/openai | 2/10 (cache 0.10) ; 10/50 | 1.05M | DeepSWE Sol 68.8, Astra 74.1 (d=3) | Astra ~27k out tok/task, lean (d=1) | Architect, reviewer |
| GPT-6 Luna | add opencode-go/gpt-6-luna | 0.1/0.5 | 1.05M | DeepSWE 66.6 (d=3) | cheap | Compaction, scouts |
| Grok 4.7 | opencode-go/grok-4.7; add xai/grok-4.7 | 2/6 | 500k | AA 46, coding-agent 56 (d=1) | xhigh ~81k tok/task — verbose | Reviewer/architect second opinion at high |
| Kimi K3 | kimi-code/k3 (1M), opencode-go, ollama, deepinfra | 3/15 | 1M | AA 57 max / 47 low (d=1) | low 8.6M vs max 130M tok — use low/high | Hard bugs, long-context reasoning |
| Kimi K3-256k | kimi-code/k3-256k | plan | 262k | as K3 | cheaper context per call | Worker on hard slices, reviewer |
| Kimi K2.8 (kimi-for-coding) | kimi-code/kimi-for-coding | plan | 1M (config) | — (d=3) | defaults to max; run at high | Interactive pairing, worker |
| GLM-5.3 | opencode-go, deepinfra, ollama, qwencloud; add zai | 1.4/4.4 (DI 0.9/4) | 1M | AA 60, TB2.1 88.2 (d=2) | verbose at max (170M vs 72M median, d=1) | Reviewer, research |
| GLM-5.3-Flash (= Express) | opencode-go, deepinfra, ollama; add zai | 0.15/0.5 | 1M | AA 57 (d=2) | cheap | Scouts, verifier |
| DeepSeek V4.1-Flash | opencode-go, deepinfra, ollama, qwencloud | 0.15/0.6 | 1M | TB2.1 90.6 (d=2), AA ~40 | verbose (250M vs 140M median, d=2) | Worker, verifier, research |
| DeepSeek V4-Pro | opencode-go, deepinfra, qwencloud | 0.435/0.87 direct | 1M | — | high/max only | Deep reasoning |
| MiniMax M3 | minimax-coding-plan, minimax-backup, opencode-go, deepinfra | plan (list 0.3/1.2) | 1M | SWE-Pro 59, TB2.1 66 (vendor, d=2) | moderate | Orchestrator, worker |
| MiniMax M3.1-Flash-Preview | minimax-coding-plan | plan | 512k | no public evals | effort low…max | Scouts, bounded edits |
| Qwen 3.8 Max | qwencloud, deepinfra; add opencode-go | 2/6 | 1M | TB2.1 86.6, SWE-Pro 67.7 (d=2) | — | Research, reviewer |
| Qwen 3.8 Flash | qwencloud; add opencode-go | 0.15/0.47 | 1M | no data | cheap | Fast lane, compaction |
| Qwen3.8-27B / Qwen3.6-35B-A3B | hetzner, deepinfra | 0.2/2.5 ; 0.1/0.95 | 262k | small tier | thinking-off friendly | Scout fallback, own region |
| MiMo v2.6 Pro/Flash | xiaomi plan (401 now), opencode-go | — | — | not researched | cheap | Compaction filler |

## Ranking: top model vs flash tier per vendor (2026-10-11, judgment d=2)

Evidence: AA = Artificial Analysis intelligence index; SWE-Pro; TB2.1 = Terminal-Bench 2.1 (BenchLM); DeepSWE.
Vendor-reported numbers are d=2. Sources disagree (DS V4.1-Flash: TB2.1 90.6 but AA ~40), so the order is judgment, not a single score.
Falsifier: our own bake-off (same tasks, pass rate per $) reorders it.

### Top models
| # | Model | Evidence | Note |
|---|---|---|---|
| 1 | Claude Opus 5.5 | SWE-Pro 89.9 (vendor) | strongest coder; Claude Max / API |
| 2 | GPT-6 Astra / GPT-6.1 Sol | DeepSWE 74.1 / 68.8; very lean tokens | ChatGPT Pro (codex) |
| 3 | GLM-5.3 | AA 60, TB2.1 88 | best open-weight; verbose at max |
| 4 | Kimi K3 | AA 57 (max) / 47 (low) | long context; effort matters a lot |
| 5 | Qwen3.8-Max | SWE-Pro 67.7, TB2.1 86.6 | strong; Qwen plan |
| 6 | MiniMax M3 | SWE-Pro 59, TB2.1 66 (vendor) | the workhorse, not the strongest |
| 7 | Grok 4.7 | AA 46, coding-agent 56 | verbose at xhigh |
| ? | DeepSeek V4-Pro, MiMo V2.6-Pro, Muse Spark 1.3, Gemini 3.8 Flash | little or no data | unranked |

### Flash tier
| # | Model | Evidence | Note |
|---|---|---|---|
| 1 | GLM-5.3-Flash | AA 57 (≈ K3 at max!) | best flash; scouts, verify, even review |
| 2 | GPT-6 Luna | DeepSWE 66.6 | cheap, lean |
| 3 | DeepSeek V4.1-Flash | TB2.1 90.6 (d=2), AA ~40 | strong at terminal tasks, weak on reasoning index; verbose |
| 4 | Qwen3.8-Flash / Flash-Next (125B-A6B) | Flash-Next SWE-bench 62.5 (one blog, d=3) | promising; untested |
| 5 | MiniMax M3.1-Flash | no public evals | subagent default; prove it in the bake-off |
| 6 | MiMo V2.6-Flash | no data | cheap filler |
| 7 | GLM-4.7-Flash / GLM-4.5-Flash (Z.ai free) | previous gen | free scouts |

### Price and price/performance (list prices, models.dev 2026-09-27, d=1; scores d=2)

**Blend** = $/1M for typical agent traffic: 90% input (80% of it cache hits) + 10% output = 0.9×(0.2·in + 0.8·cache) + 0.1·out.
**Score/$** = benchmark score ÷ blend. It is only comparable within the same benchmark column.
OpenAI official (developers.openai.com/api/docs/pricing, read 2026-10-11): there is no gpt-6.1-luna; 6.1 exists only as gpt-6.1-sol.
Prices double for >272k context: Sol $4/$15, Luna $0.20/$0.75, Astra $20/$75.
Flat plans (MiniMax, Kimi, Qwen, Ollama, opencode-go, Claude Max, ChatGPT Pro) cost $0 marginal until their quota runs out.
There, blend tells you which quota to spend first.

| Rank | Model | $/1M in / out / cache | Blend | AA | AA/$ | SWE-Pro | SWE/$ | DeepSWE | DSWE/$ |
|---|---|---|---|---|---|---|---|---|---|
| T1 | Claude Opus 5.5 | 4 / 20 / 0.2 | 2.86 | – | – | 89.9 | 31 | – | – |
| T2 | GPT-6 Astra | 10 / 50 / 1 | 7.52 | – | – | – | – | 74.1 | 10 |
| T2 | GPT-6.1 Sol | 2 / 10 / 0.10 | 1.43 | – | – | – | – | 68.8 (GPT-6 Sol) | 48 |
| T3 | GLM-5.3 | 1.4 / 4.4 / 0.26 | 0.88 | 60 | 68 | – | – | – | – |
| T4 | Kimi K3 | 3 / 15 / 0.3 | 2.26 | 57 | 25 | – | – | – | – |
| T5 | Qwen3.8-Max | 2 / 6 / 0.25 | 1.14 | – | – | 67.7 | 59 | – | – |
| T6 | MiniMax M3 | 0.3 / 1.2 / 0.06 | 0.22 | – | – | 59 | 272 | – | – |
| T7 | Grok 4.7 | 2 / 6 / 0.5 | 1.32 | 46 | 35 | – | – | – | – |
| F1 | GLM-5.3-Flash | 0.15 / 0.5 / 0.03 | 0.10 | 57 | **576** | – | – | – | – |
| F2 | GPT-6 Luna | 0.1 / 0.5 / 0.01 | 0.075 | – | – | – | – | 66.6 | **888** |
| F3 | DeepSeek V4.1-Flash | 0.2 / 0.6 / 0.006 | 0.10 | ~40 | 400 (≈220 after verbosity) | – | – | – | – |
| F4 | Qwen3.8-Flash | 0.15 / 0.47 / 0.016 | 0.086 | – | – | – | – | – | – |
| F6 | MiMo V2.6-Flash | 0.14 / 0.28 / 0.003 | 0.055 | – | – | – | – | – | – |

Token verbosity changes the real cost per task:
- GLM-5.3 at max uses ~2.4× median tokens.
- DS V4.1-Flash uses ~1.8× median.
- K3 at low effort uses ~15× fewer tokens than at max, so K3-low costs ≈ GLM-5.3 per task for AA 47.
- Grok 4.7 at xhigh is verbose. GPT-6 Astra is very lean, which partly offsets its high list price.

Readout:
- **Value leaders:** GLM-5.3-Flash and GPT-6 Luna, near-top scores at flash prices.
- **Workhorse:** MiniMax M3, best SWE-Pro per $ among the tops.
- **Best top for $:** GLM-5.3 (AA/$ 68), then Qwen3.8-Max.
- **Pay for it only when it matters:** Opus 5.5 and GPT-6 Astra, for the few hard tokens.
- **Spend plan quota rather than list $:** K3 and Grok 4.7, which have poor AA/$ at list price.

**GPT-6.1 Sol vs GPT-6 Astra:** Astra is ~5 points higher on DeepSWE (74.1 vs 68.8) at ~5× the blend ($7.52 vs $1.43).
Sol gets ~93% of the score for ~19% of the price, so Sol is the default architect/reviewer and Astra is reserved for the hardest
problems or a retry after Sol fails. Astra's lean token use narrows the per-task gap but doesn't close it (d=2).

**GPT-5.6 Terra:** previous generation (2026-07-09). $2 / $12 / cache 0.20, blend ≈ $1.70, 1.05M context. In config as
opencode/gpt-5.6-terra (opencode charges $2.5/$15). GPT-6 has no Terra (OpenAI pricing page: Astra, Sol, Luna; 6.1: Sol only).
Terra is dominated by GPT-6.1 Sol, which is newer, cheaper (blend 1.43) and stronger, so don't route to it unless our own run shows an edge.

**K3 vs DS V4.1-Flash:** a different class. K3 is a deep reasoner for review, design and hard bugs. DS V4.1-Flash is a fast,
cheap executor that does well on terminal tasks but is much weaker on general reasoning (AA ~40 vs 57). Use it for
mechanical work (run, read the exit code, bounded edits), never as the judge of K3-level work.

## Family rosters (relevant models only)

List $/1M in/out is the cheapest common list price in the models.dev cache (2026-09-27, d=1). Size class drives slicing:
S = scout / verify / compaction, M = worker, L = reviewer / research, XL = architect / hard bug.

### GLM (Z.ai)
| Model | Config ids today | List $/1M | Ctx | Class | Note |
|---|---|---|---|---|---|
| GLM-5.3 | opencode-go, opencode, deepinfra, ollama-cloud, qwencloud | 0.9/4 (DI) – 1.4/4.4 | 1M | L | flagship; verbose at max |
| GLM-5.3-Flash (= Express) | opencode-go, opencode, deepinfra, ollama-cloud | 0.15/0.5 | 1M | S | best cheap scout |
| GLM-5.3-FlashX | add zai | 0.37/1.25 | 1M | S/M | Z.ai API only |
| GLM-5.3-highspeed | zai coding plan (add) | plan | 1M | M | fast GLM-5.3 on the plan |
| GLM-5.2 | opencode-go, opencode, deepinfra, ollama-cloud, qwencloud | 0.75/2.4 | 1M | M | cheaper previous flagship |

### DeepSeek
| Model | Config ids today | List $/1M | Ctx | Class | Note |
|---|---|---|---|---|---|
| V4.1-Flash | opencode-go, deepinfra, ollama-cloud, qwencloud | 0.2/0.6 | 1M | M | TB2.1 90.6 (d=2); verbose |
| V4-Flash (0731) | opencode-go, opencode, deepinfra, qwencloud | 0.06–0.14/0.18–0.28 | 1M | S | cheapest strong flash |
| V4-Flash-Vision-Exp | opencode-go, opencode, deepinfra | 0.22/0.66 | 1M | S | screenshots / images |
| V4-Pro (0813) | opencode-go, opencode, deepinfra, ollama-cloud, qwencloud | 0.66/1.98 (ollama) – 1.3/2.6 | 1M | L | deep reasoning, high/max only |

### Xiaomi MiMo
| Model | Config ids today | List $/1M | Ctx | Class | Note |
|---|---|---|---|---|---|
| MiMo-V2.6-Pro | opencode-go | 0.435/0.87 | 1M | M/L | cheap strong; xiaomi plan key 401 now |
| MiMo-V2.6-Flash | opencode-go | 0.14/0.28 | 1M | S | compaction / scout |

### MiniMax
| Model | Config ids today | List $/1M | Ctx | Class | Note |
|---|---|---|---|---|---|
| MiniMax-M3 | minimax-coding-plan, minimax-backup, opencode-go, opencode, deepinfra, ollama-cloud | 0.28/1.1 | 512k–1M | M | main worker on the flat plan |
| MiniMax-M3.1-Flash-Preview | minimax-coding-plan | plan | 512k | S | new; no public evals |
| MiniMax-M2.7 / M2.7-highspeed | minimax-coding-plan, minimax-backup, opencode-go, opencode, ollama-cloud | 0.25/1 | 200k | S/M | current subagent default; cheap bounded edits |

### Qwen
| Model | Config ids today | List $/1M | Ctx | Class | Note |
|---|---|---|---|---|---|
| Qwen3.8-Max | qwencloud, opencode-go, deepinfra | 1.6–2/4.8–6 | 1M | L | TB2.1 86.6, SWE-Pro 67.7 (d=2); research / review |
| Qwen3.8-2.4T-A95B | deepinfra (262k in config) | 1.95/5.95 | 262k–970k | L | open-weight Max-class MoE, 95B active; always thinking |
| Qwen3.8-Flash | qwencloud, opencode-go | 0.11–0.16/0.39–0.47 | 1M | S | fast lane, compaction |
| Qwen3.7-Flash | (catalog; qwencloud has 3.7-max/plus) | 0.03/0.13 | 1M | S | cheapest 1M-ctx flash on the list |
| Qwen3.8-Flash-Next (125B-A6B MoE, open weights) | not in config (add via deepinfra/amd or self-host on hetzner) | 0.15–0.2/0.47–0.5 | 262k (1M via YaRN) | S/M | Qwen4-architecture preview; 6B active; SWE-bench 62.5 per one blog (d=3) |
| Qwen3.8-27B (dense) | hetzner (own), deepinfra | 0.08–0.17/0.35–0.5 | 262k | S/M | dense 27B: smarter per token, slower |
| Qwen3.6-35B-A3B (MoE) | hetzner (own), deepinfra | 0.07–0.09/0.42–0.6 | 262k | S | 3B active: much faster/cheaper, weaker reasoning |

27B dense vs MoE (3.6-35B-A3B, or the newer 3.8-Flash-Next 125B-A6B): the dense 27B does bounded edits, verification and reading code. The MoE does high-volume scouting, grep-and-summarize and classification, where speed counts more than depth. The 27B and 35B-A3B already run on our hetzner endpoint (no plan quota); Flash-Next is not configured yet. d=2 (inferred from architecture and price); falsifier: a same-task A/B in tower transcripts shows the MoE matching the 27B's pass rate.

## Volume coders (sparse MoE, flash prices) — candidates, UNTESTED

Idea: large total parameters with few active ones give near-mid-tier code quality at scout prices. Use them for bulk
mechanical coding (renames, call-site migrations, test scaffolds, lint fixes, small bounded edits) at high parallelism, with
a strong reviewer behind them. Every quality claim here is d=3 (single-source or inferred).

| Model | Total / active | List $/1M in/out | Ctx | Config ids today | Note |
|---|---|---|---|---|---|
| Qwen3.8-Flash-Next | 125B / 6B | 0.15–0.2/0.47–0.5 | 262k (1M YaRN) | **add** (deepinfra/amd/self-host) | Qwen4-arch preview; SWE-bench 62.5 per one blog |
| DeepSeek V4-Flash (0731) | ~284B / ? | 0.06–0.14/0.18–0.28 | 1M | opencode-go, deepinfra, qwencloud | cheapest strong 1M ctx |
| MiMo-V2.6-Flash | ? / ? | 0.14/0.28 | 1M | opencode-go | cheap; unbenchmarked here |
| GLM-5.3-Flash | ? / ? | 0.15/0.5 | 1M | opencode-go, deepinfra, ollama | AA 57 (d=2) |
| MiniMax M3.1-Flash-Preview | ? / ? | plan | 512k | minimax-coding-plan | free on the flat plan |
| gpt-oss-120b | 117B / ~5B | 0.03–0.09/0.17–0.36 | 131k | deepinfra, ollama-cloud | very cheap; short ctx |
| Qwen3.5-122B-A10B | 122B / 10B | 0.115/0.917 | 262k | **add** | previous-gen Qwen MoE |
| Nemotron-3 Super / 120B-A12B | 120B / 12B | 0.5/1.5 | 256k | ollama-cloud (super, ultra) | NVIDIA; already on ollama |
| Ling-3.0-Flash | ? / ? | 0.021/0.063 | 262k | **add** | extremely cheap; unknown quality |

**Bake-off (do before routing bulk work):** take 10 real bounded tasks from tower missions (one file to a few files, with tests).
Run each candidate at low or medium effort and record pass rate, total tokens, wall time and $/solved task. Promote the top 2 to
the "Volume coder" role. Owner: a hightower or jcode mission once quota allows. Falsifier: a candidate whose pass rate
is below 70% of MiniMax-M3's on the same tasks is not a volume coder.

## Other relevant models (catalog scan, released since 2026-07, d=3 unless noted)

| Model | Lab | Open weights | List $/1M in/out | Ctx | Config ids today | Why relevant |
|---|---|---|---|---|---|---|
| Gemini 3.8 Flash | Google | no | 0.75/3.75 | 1M | **none** | only Google model in reach; adds a 4th vendor for review diversity |
| Gemini 3.5 Flash-Lite | Google | no | 0.15/1.25 | 1M | **none** | cheap 1M-ctx scout / compaction |
| Laguna-S-2.1 / XS-2.1 | Poolside (coding-specialist) | yes | 0.09/0.18 ; 0.06/0.12 | 1M ; 262k | **none** | built for code; volume-coder candidate |
| Hy3 | Tencent Hunyuan | yes | 0.066/0.26 | 262k | opencode-go/hy3 | very cheap; volume-coder candidate |
| Hy4-preview | Tencent Hunyuan | yes | 0.67/2 | 1M | opencode-go/hy4-preview | preview; mid-tier alternative |
| Inkling / Inkling-Small | Thinking Machines | yes | 0.95/4.05 ; 0.45/1.2 | 524k | deepinfra | new lab; diversity reviewer/worker candidate |
| Mercury-2.5 | Inception (diffusion LLM) | no | 0.04/0.15 | 260k | **none** | very fast generation; quick small edits / autocomplete-style |
| Nemotron-3.5-Lightning | NVIDIA | yes | 0.05/0.2 | 262k | opencode (free) | free scout |
| Muse Spark 1.3 | Meta (MSL) | no | 1.25/4.25 | 1M | opencode/muse-spark-1.3 | Meta frontier-ish; another vendor for review diversity |
| Muse Spark 1.3 Contributor | Meta | no | 0.1/0.2 (free on opencode) | 1M | opencode-go, opencode (free) | ~12× cheaper; "contributor" likely means prompts are shared with Meta for training (d=2), so keep private code off it |
| Muse Glimmer 30B | Meta | yes | 0.2–0.3/0.8–1.2 | 131k | **none** (deepinfra has it) | small open Meta model; scout / volume-coder candidate |
| Mistral Large 3 (675B) | Mistral | yes | — | — | ollama-cloud/mistral-large-3:675b | EU vendor; diversity reviewer |
| Gemma 4 31B | Google | yes | — | — | ollama-cloud/gemma4:31b | small open Google model; scout |
| Step-5-preview | StepFun | no | 0.96/2.74 | 1M | **none** | new frontier-ish entrant; watch only |

Bake-off additions: Laguna-S-2.1, Hy3, Mercury-2.5 and Inkling-Small join the volume-coder bake-off. Gemini 3.8 Flash, Inkling, Muse Spark 1.3 and Mistral Large 3
join a reviewer-diversity trial against GLM-5.3 and K3-256k.

## Role → model (subscription first, by value; PAYG last)

| Role | Primary | Fallback 1 | Fallback 2 | Effort |
|---|---|---|---|---|
| Tower orchestrator | minimax-coding-plan/MiniMax-M3 | minimax-backup/MiniMax-M3 | kimi-code/k3-256k | medium |
| Build worker | minimax-coding-plan/MiniMax-M3 (M3.1-Flash for bounded slices) | opencode-go/deepseek-v4.1-flash | kimi-code/kimi-for-coding (K2.8) → deepinfra GLM-5.3 | high |
| Volume coder (bulk mechanical edits) | minimax M3.1-Flash (plan) | opencode-go/deepseek-v4-flash | Qwen3.8-Flash-Next (add) → gpt-oss-120b | low/medium |
| Scouts / locators / mailman | opencode-go/glm-5.3-flash | minimax M3.1-Flash-Preview | opencode-go/gpt-6-luna → hetzner Qwen3.8-27B | low / thinking off |
| Research synthesis | qwencloud/qwen3.8-max | opencode-go/deepseek-v4.1-flash | opencode-go/glm-5.3 | high |
| Architect | ChatGPT Pro codex (GPT-6.1 Sol / GPT-6 Astra) | kimi-code/k3 | opencode-go/grok-4.7 | high (not xhigh/max) |
| Adversarial reviewer (vendor ≠ worker) | zai coding plan / opencode-go glm-5.3 | kimi-code/k3-256k | opencode-go/grok-4.7 → codex GPT-6.1 Sol | high |
| Verifier | opencode-go/deepseek-v4.1-flash | opencode-go/glm-5.3-flash | deepinfra Qwen3.8-27B | low |
| Compaction | opencode-go/gpt-6-luna | qwencloud/qwen3.8-flash (thinking off) | minimax M3.1-Flash | low |
| Interactive pairing | kimi-code/kimi-for-coding (K2.8) | Claude Max (Opus 5.5) | qwencloud/qwen3.8-max | high |
| Big refactor / hard bug | Claude Max Opus 5.5 | codex GPT-6 Astra | kimi-code/k3 (1M) | high, max only on retry |

## Slicing a mission across models (cost per stage)

Assumed traffic per stage; cost at list price (on a subscription it comes out of the plan quota instead).
d=3 (inferred from list prices + typical agent token use); falsifier: measured tokens per stage from tower transcripts.

| Stage | Agents × model (size) | Tokens per agent | List cost per stage | Why this size |
|---|---|---|---|---|
| 1. Scout / locate | 3–6 × glm-5.3-flash or gpt-6-luna (small) | ~100–200k in, 5k out | ~$0.05–0.15 | read-heavy, cheap, parallel |
| 2. Research synth | 1 × deepseek-v4.1-flash or qwen3.8-max (mid/large) | ~300k in, 20k out | ~$0.06 / ~$0.70 | long context, one merge point |
| 3. Plan / architect | 1 × GPT-6.1 Sol (codex) or K3 at high (frontier) | ~100k in, 15k out | ~$0.35 / ~$0.55 | few tokens, highest leverage |
| 4. Build | 2–4 × MiniMax-M3 for design-bearing slices; 4–10 × volume coder for mechanical slices | ~1–3M in (mostly cached), 50k out | plan quota (list ~$0.3–1 each) | bulk tokens on the flat plan |
| 5. Verify | 1 × deepseek-v4.1-flash low or glm-5.3-flash (small) | ~200k in, 5k out | ~$0.03 | runs commands, reads exit codes |
| 6. Review (vendor ≠ builder) | 1 × GLM-5.3 high or K3-256k (large) | ~300k in, 15k out | ~$0.50 | catches the builder's blind spots |
| 7. Hard-bug escalation (only on fail) | 1 × Opus 5.5 / GPT-6 Astra (frontier) | ~500k in, 30k out | ~$2.6 / ~$5.5 | expensive, used rarely |
| Compaction (any stage) | gpt-6-luna / qwen3.8-flash (small) | ~200k in, 10k out | ~$0.03 | summary only |

Rough mission total without escalation: ~$1–3 list, of which the build stage (~70% of tokens) rides the MiniMax plan.
Efficiency levers:
- Spend tokens on small models (scouts, verify, compaction) and few tokens on frontier ones (plan, review).
- Run K3 / Grok 4.7 / GLM-5.3 at low or high effort, not max/xhigh: K3 low uses ~15× fewer tokens for −10 AA points.
- Diversity: builder, reviewer and architect come from 3 different vendors (MiniMax build → GLM/Kimi review → GPT/Grok architect).
- Watch the verbose models (DS V4.1-Flash, GLM-5.3 max, Grok xhigh). Judge them by cost per solved task, not by $/1M.
- When the quota on one plan is spent, move that stage to the next plan in the same size class (see the role table above).

## Config deltas for `~/.kimi-code/config.toml` (not applied yet)
- Providers: xai, zai (PAYG + coding plan), deepseek, openai, anthropic.
- Volume-coder adds: Qwen3.8-Flash-Next, Qwen3.5-122B-A10B, Ling-3.0-Flash, Laguna-S-2.1, Mercury-2.5.
- Diversity adds: a Gemini provider (Gemini 3.8 Flash, 3.5 Flash-Lite).
- Aliases: opencode-go/{gpt-6-luna,qwen3.8-max,qwen3.8-flash}, opencode/{gpt-6-sol,claude-opus-5-5}, xai/grok-4.7, zai/{glm-5.3,glm-5.3-flash}, deepseek/*.
- Effort per role; K3 / K3-256k default `max` → high.
