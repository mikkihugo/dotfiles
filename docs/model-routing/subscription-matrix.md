# Subscription matrix

Last updated: 2026-10-11 (claude-fbe0939f). Living file — update numbers from each console.
Operator rules: all subscriptions are usable by towers/automated TUIs (kimi, jcode, qoder, codex, claude);
no ToS gating in routing. Value multiple = list-price cost of usable tokens ÷ monthly price.
"Blend" = 90% input (80% cached) / 10% output at list price. d = doubt 0–4; shared falsifier:
the vendor console or official page shows a different number.

## Index — value per $ and live use (read 2026-10-11 ~10:15Z)

Value × = est. list-price worth ÷ price (see table below; d=2–3). Live use is from each plan's quota endpoint, observed now (d=0).

| Rank | Plan | Value × | Live use now | Fully used? | Action |
|---|---|---|---|---|---|
| 1 | opencode-go (Go $10) | ~30× (caps $1,200 list) | rolling 0%, weekly 35%, **monthly 100%: rate-limited until 2026-10-16** | **Yes, maxed** | upgrade to Go Plus ($40, ~2–8× caps). Best value we have, and it's the binding limit |
| 2 | MiniMax Token Plan ×2 keys | ~20× | coding-plan: 98% interval / 100% week left; backup: 99% / 98% left | **No, nearly idle** | route volume coding here first (M3.1-Flash, M2.7 for bulk; M3 for design slices); both keys in parallel |
| 3 | Ollama Cloud | ~3× (d=3) | session 100% left, **weekly 0% left until 2026-10-12 00:00Z** | **Yes, weekly maxed** | keep as overflow; the 5h session is unusable while the weekly is out |
| 4 | ChatGPT Pro | high (frontier, unpublished caps) | not probed (no headless API) | unknown | use codex for architect / hard-bug slices; likely underused |
| 5 | Claude Max 20× | high | not probed | unknown | Opus for hard bugs / big refactors; likely underused outside this session |
| 6 | Kimi Code plan | unknown | **probe failed: both stored tokens return 401** (devbox token stale after re-login) | unknown | re-read from the TUI `/usage`; K3 / K3-256k / K2.8 for review + hard bugs |
| 7 | Qwen Token Plan | unknown (credits) | console only | unknown | research / review on qwen3.8-max; check credits in console |
| 8 | Z.ai GLM Coding | unknown (credits) | not configured in kimi | **0% (unused)** | add the coding-plan provider: GLM-5.3 reviewer + 5.3-Flash scouts |
| 9 | Xiaomi MiMo plan | unknown | **key returns 401: plan paid, unusable** | **0% (broken)** | fix the key, or MiMo via opencode-go only |
| 10 | Qoder | unknown | not probed | unknown | read tier and usage from qodercli |
| — | DeepInfra PAYG | 1× | balance n/a | n/a | last resort only |

**Summary:** the two cheapest-per-worth plans are opposite: opencode-go is maxed, MiniMax is almost idle.
Z.ai and Xiaomi are paid for but deliver 0%. Kimi, ChatGPT Pro, Claude Max, Qwen and Qoder are unmeasured.

### Slicing so every sub is used (fill order)
1. **Use-it-or-lose-it windows first:** a 5h window resets whether you use it or not. So keep MiniMax (both keys) and Ollama (when its weekly is open) busy continuously with volume coding, scouts and verify.
2. **Weekly / monthly pools next:** opencode-go per-model caps hold Grok 4.7, GLM-5.3, DS V4.1-Flash and GPT-6 Luna. Spend them on the roles where they are best: review, research and compaction.
3. **Frontier plans for the few expensive tokens:** ChatGPT Pro (codex) for architect, Claude Max (Opus) for hard bugs, Kimi K3 for long-context review.
4. **Credit plans (Qwen, Z.ai) for diversity:** a second-vendor reviewer and research synthesis.
5. **PAYG (DeepInfra) only when every plan in that size class is exhausted.**

Per mission, roughly: scouts + verify + volume coding on MiniMax/Ollama (~80% of tokens) → review on GLM (Z.ai/opencode) or K3
(Kimi) → plan on codex/K3 → escalation on Opus. Re-read this index weekly by re-running the probes.

## Plan details

| Plan ($/mo) | Quota mechanism → usable tokens | Eff. $/1M | Value × | Models unlocked | Probe |
|---|---|---|---|---|---|
| MiniMax Token Plan — coding-plan + backup keys (Plus $22 / Max $55 / Ultra $132) | 5h rolling + weekly bar; est. Plus ~1.7B, Max ~5.1B, Ultra ~12.5B tok/mo (d=3) | ~0.011 (Max, d=3) | ~20× (d=3) | MiniMax-M3, M3.1-Flash-Preview, M2.7 | `GET api.minimax.io/v1/token_plan/remains` (live) |
| opencode-go (Go $10 / Go Plus $40) | per-model $ cap: 20%/5h, 50%/week, 100%/month. Go: DS V4.1-Flash $60≈674M tok, GLM-5.3-Flash $60≈606M, M3 $60≈276M, GPT-6 Luna $15≈200M, GLM-5.3 $15≈17M, Qwen3.8-Max $15≈13M, Grok 4.7 $15≈11M, K3 $15≈6.6M (Go Plus ≈2–8× per model) | ~0.01–0.03 | 30–120× (caps total $1,200 list on Go; realistic ~30×, d=2) | ~30 models incl. Grok 4.7, GPT-6 Luna, Qwen3.8 Max/Flash, K3, GLM-5.3(-Flash), DS V4.x, M3 | `/zen/go/v1/usage` (needs `x-opencode-session`) |
| Ollama Cloud (Pro $20 / Max $100) | session + weekly %; metering unclear (GPU-time vs $60/$300 credits, d=3) | ? | ~3× if credits (d=3) | glm-5.3(-flash), kimi-k3, deepseek-v4-pro, minimax-m3, nemotron-3-ultra | `/api/balance` (live) |
| Kimi Code ($19 / $39 / $99 / $199; tier TBD) | weekly + 5h windows, unpublished | ? (d=4) | ? | **K3 (1M), K3-256k, K2.8 (kimi-for-coding), K2.7 highspeed** | `api.kimi.com/coding/v1/usages` (live) |
| Qwen Token Plan / qwencloud (Lite ~$6–8 … Pro ~$68–80; tier TBD) | monthly credits (Pro 180k); weekly window removed 2026-09-22 | ? (d=4) | ? | qwen3.8-max/flash, glm-5.3, deepseek-v4-pro, deepseek-v4.1-flash | console only |
| Xiaomi MiMo plan (price TBD) | lowest tier ≈500M tok after 2026-05-27 raise (d=3) | ? | ~ $84 list per 500M (MiMo-V2.6-Pro blend) | mimo-v2.5/2.6 (pro/flash) | console only; key currently 401 |
| Z.ai GLM Coding (Lite $18; Pro ~$72–80, Max ~$160–168, d=2) | credits per 5h/week: 2k/10k, 12k/60k, 28k/140k; token multiplier unpublished | ? (d=4) | ? (GLM-5.3 API blend $0.879) | GLM-5.3, GLM-5.3-Flash (= "Express") | TBD |
| Qoder (tier/price TBD, d=3) | TBD — read from qodercli/console | ? | ? | TBD (qodercli at `~/.local/bin/qodercli`) | TBD |
| ChatGPT Pro $200 / $500 | no 5h window; weekly unpublished; $200 ≈ 10–20× Plus, $500 ≈ 25× (d=3); rough 92M / 230M counted tok/week (d=3) | ? | high (GPT-6 Sol blend $1.50, Astra $7.52) | GPT-6.1 Sol, Astra, Luna via codex; Ultrafast on $500 | codex `/status` |
| Claude Max 20× $200 | 5h + weekly, Opus counted separately, unpublished (d=3) | ? | high (Opus 5.5 blend $2.86) | Opus 5.5, Sonnet 5.5, Fable 5.1 | Claude Code `/usage` |
| SuperGrok Heavy $300 | app limits; no API credits included | n/a | — | Grok in app; for automation use xAI API ($2/$6) or opencode-go/grok-4.7 | — |
| GitHub Copilot Pro+ $39 | usage-based since 2026-06-01 (legacy 1,500 premium requests) | ? | ? | Copilot clients | — |
| DeepInfra (PAYG) | balance | = list | 1× (often cheapest list) | GLM-5.3 $0.9/$4, M3 $0.28/$1.10, DS V4-Flash, Qwen3.8-27B, K3, gpt-oss | `/v1/me` (no balance) |

## Open gaps
- Operator's actual tier on MiniMax, Kimi, Qwen, Z.ai, Ollama, Qoder — fill from consoles.
- Xiaomi key 401; opencode Zen 403 on model access.
- Replace estimated token numbers with readbacks from the probes above (jcode PR #1241 fixes MiniMax/Ollama/Kimi probe parsing).

Sources: platform.minimax.io token-plan pricing; codingplan.org/en/plans/minimax; opencode.ai/docs/go;
devtoolhub Ollama; codeagentswarm Kimi; alibabacloud token-plan overview; 36kr MiMo; docs.z.ai/devpack;
aipricing.guru GLM; developersdigest Codex limits; claudelog limits; ai-toolbox Grok; docs.github.com Copilot requests;
models.dev cache `~/.cache/opencode/models.json` (2026-09-27).
