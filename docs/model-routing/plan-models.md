# Plan models we have (kimi config, read 2026-10-11)

Source: `~/.kimi-code/config.toml` `[models.*]`. Context and capabilities are copied from the config.
Descriptions come from model-matrix.md. Prices are list prices for reference (d=1, models.dev 2026-09-27); the plans themselves are flat-rate.
Size class: S = scout / verify / compaction, M = worker, L = reviewer / research, XL = architect / hard bug.

## Kimi Code plan (`managed:kimi-code`): 4 models
| Alias | Ctx | Description | Class |
|---|---|---|---|
| k3 | 1M | Kimi K3, Moonshot's frontier model, always thinking. AA 57 at max effort / 47 at low; low effort uses ~15× fewer tokens. Best for long-context review and hard bugs. Run at high, not max (config default is max). | XL |
| k3-256k | 262k | The same K3 with a cheaper 256k window. Good as a reviewer or hard-slice worker when 1M isn't needed. | L |
| kimi-for-coding | 1M | **K2.8 Preview**, the coding-tuned model and the kimi default. Interactive pairing or worker. Defaults to max effort. | M/L |
| kimi-for-coding-highspeed | 262k | **K2.7 Code Highspeed**, a faster previous-gen coder. Quick edits. | M |

## MiniMax Token Plan (`minimax-coding-plan`): 8 models, plus `minimax-backup`: 3 models
| Alias | Ctx | Description | Class |
|---|---|---|---|
| MiniMax-M3 | 1M | Main worker and tower orchestrator. SWE-Pro 59 / TB2.1 66 (vendor). Flat plan, ~20× value. | M |
| MiniMax-M3.1-Flash-Preview | 512k | **Subagent default.** Fast new tier, adjustable effort, no public benchmarks yet. Scouts, bounded edits, volume coding. | S/M |
| MiniMax-M2.7 / M2.7-highspeed | 200k | Previous gen, cheap, solid for bounded edits; highspeed is faster. Once the M2.7 subagent default. | S/M |
| MiniMax-M2.5 / M2.5-highspeed, M2.1, M2 | 200k | Legacy. Use only as last-resort fallback. | S |
| backup: MiniMax-M3, M3-400k, M2.7 | 1M / 1M / 200k | The same models on the second key, a separate quota pool. Failover target. | M |

## Ollama Cloud (`ollama-cloud`): 17 models
| Alias | Ctx | Description | Class |
|---|---|---|---|
| glm-5.3 | 1M | Z.ai flagship, always thinking. AA 60, TB2.1 88 (d=2); verbose at max. Reviewer / research. | L |
| glm-5.3-flash | 1M | GLM "Express": cheap, strong, AA 57. Best scout / verifier. | S |
| glm-5.2 | 976k | Previous GLM flagship; cheaper fallback reviewer. | M |
| deepseek-v4.1-flash | 1M | TB2.1 90.6 (d=2), cheap but verbose. Worker / verifier / research. | M |
| deepseek-v4-pro:0813 | 1M | Deep reasoning, high/max only. Hard reasoning slices. | L |
| kimi-k3 | 1M | K3 via Ollama, a second K3 quota pool. | XL |
| kimi-k2.7-code / kimi-k2.6 | 262k | Older Kimi coders. Fallback workers. | M |
| minimax-m3 / minimax-m2.7 | 512k / 197k | MiniMax via Ollama, a third MiniMax pool. | M |
| mistral-large-3:675b | 262k | Mistral (EU) large open model, no thinking flag. Vendor-diverse reviewer. | L |
| gemma4:31b | 262k | Google small open model. Scout. | S |
| nemotron-3-ultra / -super / -nano:30b | 262k / 262k / 1M | NVIDIA open MoE family. Ultra = reviewer candidate, super = worker, nano = cheap scout. | L / M / S |
| gpt-oss:120b / gpt-oss:20b | 131k | OpenAI open-weight MoE (~5B / ~3.6B active). Very cheap volume coder / scout, short context. | S |

Quota note: the Ollama weekly allowance was 0% left until 2026-10-12 00:00Z when read.

## Qwen Token Plan (`qwencloud`): 14 models
| Alias | Ctx | Description | Class |
|---|---|---|---|
| qwen3.8-max | 1M | Alibaba flagship. TB2.1 86.6, SWE-Pro 67.7 (d=2). Research / reviewer. | L |
| qwen3.8-flash | 1M | Fast, cheap 3.8 tier. Compaction / fast lane. | S |
| qwen3.7-max / qwen3.7-plus | 1M | Previous gen max / mid. Fallbacks. | L / M |
| qwen3.6-flash | 1M | Older flash. Fallback scout. | S |
| glm-5.3, glm-5.2 | 1M | GLM served from the Qwen plan, a separate GLM quota pool. | L / M |
| deepseek-v4-pro, deepseek-v4.1-flash, deepseek-v4-flash-0731 | 1M | DeepSeek served from the Qwen plan, a separate DeepSeek pool. | L / M / S |
| qwen-audio-3.0-realtime-plus / tts-plus | 128k / 8k | Audio, not for coding. | — |
| wan2.7-image / image-pro | 8k | Image generation, not for coding. | — |

## Z.ai GLM Coding plan: **not configured**
No `zai` provider exists in the kimi config, so the plan is paid but unused. To add it:
- **Provider:** `zai-coding-plan`, base `https://api.z.ai/api/coding/paas/v4` (OpenAI-compatible).
- **Models:** glm-5.3, glm-5.3-flash, glm-5.3-highspeed (the plan's fast GLM-5.3).
- **Use:** an extra GLM pool for reviewer (5.3) and scouts (5.3-flash).

## Same model, several pools
Use these for failover chains, so one exhausted quota never stops a role:
- **GLM-5.3:** ollama-cloud, qwencloud, (z.ai once added), opencode-go, deepinfra
- **DeepSeek V4.1-Flash:** ollama-cloud, qwencloud, opencode-go, deepinfra
- **K3:** kimi-code, ollama-cloud, opencode-go, deepinfra
- **MiniMax M3:** coding-plan, backup, ollama-cloud, opencode-go, deepinfra
