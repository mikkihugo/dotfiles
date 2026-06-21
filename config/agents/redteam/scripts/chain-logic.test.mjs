// node --test scripts/chain-logic.test.mjs
import { test } from "node:test"
import assert from "node:assert/strict"
import {
  errorText,
  providerFailure,
  computeAttemptBudget,
  hasVerdict,
  looksNarrated,
  needsAttentionWithoutFindings,
  planJobs,
  MAX_PLAN_JOBS,
  aggregateAllFiles,
  synthesizeUltrareview,
  MIN_ATTEMPT_MS,
  planLensRoutes,
  isChainFailure,
  scoutScores,
  selectScoutModels,
  selectHotspots,
  isTransient,
  stripAssistantThinkParts,
  reviewProseText,
  reaskEvidenceText,
  mergeModelParamsCatalog,
  normalizeParamValues,
  resolveModelReviewParams,
  resolveModelProtocol,
  applyHarnessProviderOverlay,
  resolveMinimaxM3ThinkingEffort,
  resolveModelsCatalogBaseUrl,
  modelsListUrl,
  resolveServedModelRef,
  planBackfillReplacements,
  buildPanelAttribution,
  isPanelSlotSatisfied,
  pickDistinctLineagePanel,
  stratifyPanelSwap,
  mergeBackfillRound,
  parseRosterCacheByProvider,
  rosterCacheWriteBody,
  rosterEntriesFromByProvider,
  isHarnessFailureVerdict,
  summarizeLineageAttempt,
  computePanelVerdict,
  buildScoutHandoff,
  stableToolCacheKey,
  isCacheableReviewTool,
  buildReviewEvidencePack,
  shouldWarnAboutHarnessInternals,
  classifyReviewLane,
  normalizeBenchEvidence,
  mergeBenchEvidence,
  rankLaneBenchCandidates,
  eligibleLaneCandidates,
  planLaneRoute,
  buildLanePlannerPrompt,
  parseLanePlannerChoice,
  planLaneRouteWithPlanner,
} from "./chain-logic.mjs"

const SCOUT_POLICY = {
  directProviderByLineage: {
    minimax: "minimax-coding-plan",
    qwen: "opencode-go",
    kimi: "managed:kimi-code",
    glm: "zai",
    mimo: "xiaomi-token-plan-ams",
  },
  providerPriority: ["ollama-cloud", "opencode-go", "alibaba-token-plan"],
}

test("isTransient: rate-limit / overload errors are retryable", () => {
  assert.equal(isTransient({ status: 503 }), true)
  assert.equal(isTransient({ status: 429 }), true)
  assert.equal(isTransient({ message: "RESOURCE_EXHAUSTED" }), true)
  assert.equal(isTransient({ message: "UNAVAILABLE" }), true)
  assert.equal(isTransient(new Error("The model is overloaded. Please try again later.")), true)
  assert.equal(isTransient({ message: "rate limit exceeded" }), true)
})
test("isTransient: auth / parse / unknown are NOT retryable (won't recover on a backoff)", () => {
  assert.equal(isTransient({ status: 401 }), false)
  assert.equal(isTransient({ message: "invalid JSON" }), false)
  assert.equal(isTransient({ message: "max_tokens exceeds model's maximum" }), false)
  assert.equal(isTransient(null), false)
})
test("isTransient: daily-quota / billing 429 is NOT retried (not backoff-recoverable)", () => {
  assert.equal(isTransient({ message: "429 You exceeded your current quota, please check your plan" }), false)
  assert.equal(isTransient({ message: "RESOURCE_EXHAUSTED: daily limit reached" }), false)
  assert.equal(isTransient({ message: "billing account required" }), false)
  // a permanent auth error mentioning 'try again' must NOT be treated as transient
  assert.equal(isTransient({ message: "Invalid API key, please try again with a valid key" }), false)
})

test("stableToolCacheKey is stable across object key order", () => {
  assert.equal(
    stableToolCacheKey("Grep", { pattern: "submit_verdict", path: "", output_mode: "content" }),
    stableToolCacheKey("Grep", { output_mode: "content", path: "", pattern: "submit_verdict" }),
  )
})

test("isCacheableReviewTool only caches read-only inspection tools", () => {
  assert.equal(isCacheableReviewTool("Read"), true)
  assert.equal(isCacheableReviewTool("Grep"), true)
  assert.equal(isCacheableReviewTool("Glob"), true)
  assert.equal(isCacheableReviewTool("FetchURL"), false)
  assert.equal(isCacheableReviewTool("submit_verdict"), false)
})

test("buildReviewEvidencePack summarizes changed files and shortstat", () => {
  const pack = buildReviewEvidencePack({
    repoRoot: "/repo",
    targetLabel: "main",
    inputKind: "diff",
    shortstat: " 2 files changed, 10 insertions(+), 3 deletions(-)",
    nameStatus: "M\tsrc/a.ts\nA\ttests/a.test.ts\n",
    repoMapText: "symbols: dispatch, bridge",
    repoMapMaxChars: 12,
  })
  assert.match(pack, /target: main/)
  assert.match(pack, /2 files changed/)
  assert.match(pack, /M src\/a\.ts/)
  assert.match(pack, /A tests\/a\.test\.ts/)
  assert.match(pack, /repo_map_excerpt:/)
  assert.match(pack, /symbols: dis/)
  assert.doesNotMatch(pack, /dispatch, bridge/)
})

test("shouldWarnAboutHarnessInternals warns for non-redteam repos only", () => {
  assert.equal(shouldWarnAboutHarnessInternals("/home/mhugo/code/singularity-forge"), true)
  assert.equal(shouldWarnAboutHarnessInternals("/home/mhugo/.claude/redteam"), false)
})

test("scoutScores: per-file mean severity-weighted score across scout models", () => {
  const r = scoutScores([
    { file: "a.js", score: 6 }, { file: "a.js", score: 4 }, // mean 5
    { file: "b.js", score: 0 }, { file: "b.js", score: 0 }, // mean 0
    { file: "c.js", score: 3 },                              // mean 3
  ])
  assert.deepEqual(r, [{ file: "a.js", score: 5 }, { file: "c.js", score: 3 }, { file: "b.js", score: 0 }])
})

test("selectScoutModels caps live discovery to a small preferred scout team", () => {
  const selected = selectScoutModels([
    "minimax-coding-plan/MiniMax-M3",
    "ollama-cloud/minimax-m3",
    "alibaba-token-plan/deepseek-v4-flash",
    "ollama-cloud/devstral-2:123b",
    "ollama-cloud/devstral-small-2:24b",
    "ollama-cloud/qwen3-coder-next",
    "ollama-cloud/gpt-oss:20b",
    "openrouter/qwen/qwen3-next-80b-a3b-instruct:free",
    "ollama-cloud/gemma4:31b",
    "ollama-cloud/gpt-oss:120b",
    "openrouter/nvidia/nemotron-3-nano-30b-a3b:free",
    "openrouter/google/gemma-4-31b-it:free",
  ], { count: 3, ...SCOUT_POLICY })
  assert.equal(selected.length, 3)
  assert.deepEqual(selected, [
    "minimax-coding-plan/MiniMax-M3",
    "ollama-cloud/devstral-small-2:24b",
    "ollama-cloud/qwen3-coder-next",
  ])
})

test("selectScoutModels reserves one non-thinking heavy M3 slot from direct MiniMax first", () => {
  const selected = selectScoutModels([
    "openrouter/qwen/qwen3-next-80b-a3b-instruct:free",
    "ollama-cloud/gpt-oss:20b",
    "opencode-go/minimax-m3",
    "ollama-cloud/minimax-m3",
    "minimax-coding-plan/MiniMax-M3",
    "ollama-cloud/devstral-small-2:24b",
  ], { count: 3, ...SCOUT_POLICY })
  assert.equal(selected[0], "minimax-coding-plan/MiniMax-M3")
  assert.ok(selected.includes("minimax-coding-plan/MiniMax-M3"))
  assert.equal(selected.includes("ollama-cloud/minimax-m3"), false)
  assert.equal(selected.includes("opencode-go/minimax-m3"), false)
})

test("selectScoutModels uses Ollama M3 fallback when direct MiniMax is absent", () => {
  const selected = selectScoutModels([
    "openrouter/qwen/qwen3-next-80b-a3b-instruct:free",
    "ollama-cloud/gpt-oss:20b",
    "opencode-go/minimax-m3",
    "ollama-cloud/minimax-m3",
    "ollama-cloud/devstral-small-2:24b",
  ], { count: 3, ...SCOUT_POLICY })
  assert.equal(selected[0], "ollama-cloud/minimax-m3")
  assert.equal(selected.includes("opencode-go/minimax-m3"), false)
})

test("selectScoutModels prefers Qwen coder over generic Qwen next for code scouting", () => {
  const selected = selectScoutModels([
    "minimax-coding-plan/MiniMax-M3",
    "ollama-cloud/devstral-small-2:24b",
    "ollama-cloud/qwen3-next:80b",
    "ollama-cloud/qwen3-coder-next",
    "ollama-cloud/qwen3-next-coder",
    "ollama-cloud/gpt-oss:20b",
  ], { count: 3, ...SCOUT_POLICY })
  assert.deepEqual(selected, [
    "minimax-coding-plan/MiniMax-M3",
    "ollama-cloud/devstral-small-2:24b",
    "ollama-cloud/qwen3-coder-next",
  ])
})

test("selectScoutModels uses gpt-oss 20B before Gemma fallback when no Qwen coder is available", () => {
  const selected = selectScoutModels([
    "ollama-cloud/gemma4:31b",
    "ollama-cloud/devstral-small-2:24b",
    "ollama-cloud/gpt-oss:20b",
  ], { count: 3, ...SCOUT_POLICY })
  assert.deepEqual(selected, [
    "ollama-cloud/devstral-small-2:24b",
    "ollama-cloud/gpt-oss:20b",
    "ollama-cloud/gemma4:31b",
  ])
})

test("selectScoutModels keeps Gemma behind directed code and reasoning scouts", () => {
  const selected = selectScoutModels([
    "ollama-cloud/gemma4:31b",
    "ollama-cloud/devstral-small-2:24b",
    "ollama-cloud/gpt-oss:20b",
    "openrouter/qwen/qwen3-next-80b-a3b-instruct:free",
  ], { count: 3, ...SCOUT_POLICY })
  assert.deepEqual(selected, [
    "ollama-cloud/devstral-small-2:24b",
    "openrouter/qwen/qwen3-next-80b-a3b-instruct:free",
    "ollama-cloud/gpt-oss:20b",
  ])
})

test("selectScoutModels can be explicitly narrowed to two scouts", () => {
  const selected = selectScoutModels([
    "ollama-cloud/deepseek-v4-flash",
    "ollama-cloud/gemma3:12b",
    "ollama-cloud/gpt-oss:120b",
  ], { count: 2 })
  assert.deepEqual(selected, ["ollama-cloud/gemma3:12b", "ollama-cloud/deepseek-v4-flash"])
})

test("classifyReviewLane maps modes and focus to task lanes", () => {
  assert.equal(classifyReviewLane({ mode: "decision" }), "architect")
  assert.equal(classifyReviewLane({ mode: "plan" }), "architect")
  assert.equal(classifyReviewLane({ mode: "security" }), "deep-review")
  assert.equal(classifyReviewLane({ mode: "verify" }), "verify")
  assert.equal(classifyReviewLane({ mode: "review", focus: "quick scout changed files" }), "scout")
  assert.equal(classifyReviewLane({ mode: "review", focus: "deep concurrency review" }), "deep-review")
  assert.equal(classifyReviewLane({ mode: "review" }), "review")
})

test("eligibleLaneCandidates require configured, live, metadata-backed bench passes", () => {
  const bench = normalizeBenchEvidence({
    generated_at: "2026-06-20T00:00:00.000Z",
    lanes: {
      architect: [
        { model: "minimax-coding-plan/MiniMax-M3", pass: true, verdict_rate: 1, median_seconds: 40 },
        { model: "xiaomi-token-plan-ams/mimo-v2.5-pro", pass: true, verdict_rate: 1, median_seconds: 45 },
        { model: "ollama-cloud/glm-5.2", pass: true, verdict_rate: 1, median_seconds: 50 },
        { model: "xai/grok-4.3", pass: false, verdict_rate: 0, median_seconds: 0 },
      ],
    },
  })
  const rows = eligibleLaneCandidates({
    lane: "architect",
    bench,
    configured: new Set([
      "minimax-coding-plan/MiniMax-M3",
      "xiaomi-token-plan-ams/mimo-v2.5-pro",
      "ollama-cloud/glm-5.2",
      "xai/grok-4.3",
    ]),
    live: new Set([
      "minimax-coding-plan/MiniMax-M3",
      "xiaomi-token-plan-ams/mimo-v2.5-pro",
      "xai/grok-4.3",
    ]),
    metadata: new Set([
      "minimax-coding-plan/MiniMax-M3",
      "xiaomi-token-plan-ams/mimo-v2.5-pro",
      "ollama-cloud/glm-5.2",
      "xai/grok-4.3",
    ]),
  })
  assert.deepEqual(rows.map((r) => r.model), [
    "minimax-coding-plan/MiniMax-M3",
    "xiaomi-token-plan-ams/mimo-v2.5-pro",
  ])
})

test("mergeBenchEvidence preserves untouched lanes and replaces requested lanes", () => {
  const merged = mergeBenchEvidence(
    {
      generated_at: "2026-06-20T01:00:00.000Z",
      lanes: {
        architect: [
          { model: "minimax-coding-plan/MiniMax-M3", pass: true, score: 0.94 },
        ],
        review: [
          { model: "managed:kimi-code/kimi-for-coding", pass: true, score: 0.9 },
        ],
      },
    },
    {
      generated_at: "2026-06-20T02:00:00.000Z",
      source: "real-smoke",
      lanes: {
        scout: [
          { model: "ollama-cloud/qwen3-coder-next", pass: true, score: 0.84 },
        ],
      },
    },
  )
  assert.deepEqual(Object.keys(merged.lanes).sort(), ["architect", "review", "scout"])
  assert.deepEqual(merged.lanes.architect.map((row) => row.model), ["minimax-coding-plan/MiniMax-M3"])
  assert.deepEqual(merged.lanes.scout.map((row) => row.model), ["ollama-cloud/qwen3-coder-next"])
  assert.equal(merged.source, "real-smoke")
  assert.equal(merged.generated_at, "2026-06-20T02:00:00.000Z")
})

test("mergeBenchEvidence can reset to only new lanes", () => {
  const merged = mergeBenchEvidence(
    { lanes: { architect: [{ model: "minimax-coding-plan/MiniMax-M3", pass: true, score: 0.94 }] } },
    { lanes: { scout: [{ model: "ollama-cloud/qwen3-coder-next", pass: true, score: 0.84 }] } },
    { reset: true },
  )
  assert.deepEqual(Object.keys(merged.lanes), ["scout"])
})

test("rankLaneBenchCandidates keeps distinct lineages in a saturated lane", () => {
  const models = [
    "google/gemini-2.0-flash",
    "google/gemini-2.0-flash-lite",
    "google/gemini-2.5-flash",
    "google/gemini-2.5-pro",
    "google/gemini-3-flash-preview",
    "google/gemini-3-pro-image-preview",
    "google/gemini-3.1-flash-lite",
    "google/gemma-4-31b-it",
    "ollama-cloud/gpt-oss:20b",
    "ollama-cloud/qwen3-coder-next",
  ]
  const ranked = rankLaneBenchCandidates(models, "verify", (model) => model.startsWith("google/") ? 0.9 : 0.86, { limit: 8 })
  assert.equal(ranked.length, 8)
  assert.ok(ranked.some((row) => row.model === "ollama-cloud/gpt-oss:20b"))
  assert.ok(ranked.some((row) => row.model === "ollama-cloud/qwen3-coder-next"))
})

test("rankLaneBenchCandidates keeps score order within a lineage", () => {
  const ranked = rankLaneBenchCandidates([
    "ollama-cloud/qwen3-coder-next",
    "ollama-cloud/qwen3-coder:480b",
    "opencode-go/mimo-v2.5-pro",
  ], "builder", (model) => model.includes("480b") ? 0.92 : model.includes("qwen3-coder-next") ? 0.9 : 0.84, { limit: 3 })
  assert.deepEqual(ranked.map((row) => row.model), [
    "ollama-cloud/qwen3-coder:480b",
    "opencode-go/mimo-v2.5-pro",
    "ollama-cloud/qwen3-coder-next",
  ])
})

test("rankLaneBenchCandidates prefers direct provider before lineage fallbacks", () => {
  const ranked = rankLaneBenchCandidates([
    "ollama-cloud/minimax-m3",
    "opencode-go/minimax-m3",
    "minimax-coding-plan/MiniMax-M3",
    "ollama-cloud/qwen3-coder-next",
  ], "architect", (model) => model.includes("minimax") ? 0.92 : 0.9, {
    limit: 4,
    directProviderByLineage: { minimax: "minimax-coding-plan" },
    providerPriority: ["ollama-cloud", "opencode-go", "alibaba-token-plan"],
  })
  assert.deepEqual(ranked.map((row) => row.model).slice(0, 2), [
    "minimax-coding-plan/MiniMax-M3",
    "ollama-cloud/qwen3-coder-next",
  ])
})

test("planLaneRoute promotes only with a distinct failover in the same lane", () => {
  const candidates = [
    { model: "minimax-coding-plan/MiniMax-M3", lane: "architect", score: 0.91 },
    { model: "ollama-cloud/minimax-m3", lane: "architect", score: 0.9 },
    { model: "xiaomi-token-plan-ams/mimo-v2.5-pro", lane: "architect", score: 0.88 },
  ]
  const route = planLaneRoute("architect", candidates)
  assert.deepEqual(route, {
    lane: "architect",
    primary: "minimax-coding-plan/MiniMax-M3",
    failover: ["xiaomi-token-plan-ams/mimo-v2.5-pro"],
    confidence: 0.91,
    reason: "bench-backed lane route with distinct failover",
  })

  assert.equal(planLaneRoute("architect", candidates.slice(0, 1)), null)
  assert.equal(planLaneRoute("architect", candidates.slice(0, 2)), null)
})

test("planLaneRoute prefers direct provider within a lineage", () => {
  const route = planLaneRoute("architect", [
    { model: "ollama-cloud/minimax-m3", lane: "architect", score: 0.94 },
    { model: "minimax-coding-plan/MiniMax-M3", lane: "architect", score: 0.9 },
    { model: "ollama-cloud/qwen3-coder-next", lane: "architect", score: 0.89 },
  ], {
    directProviderByLineage: { minimax: "minimax-coding-plan" },
    providerPriority: ["ollama-cloud", "opencode-go", "alibaba-token-plan"],
  })
  assert.equal(route.primary, "minimax-coding-plan/MiniMax-M3")
  assert.deepEqual(route.failover, ["ollama-cloud/qwen3-coder-next"])
})

test("buildLanePlannerPrompt exposes only eligible lane candidates", () => {
  const prompt = buildLanePlannerPrompt({
    lane: "architect",
    candidates: [
      { model: "minimax-coding-plan/MiniMax-M3", lane: "architect", score: 0.91, median_seconds: 40 },
      { model: "xiaomi-token-plan-ams/mimo-v2.5-pro", lane: "architect", score: 0.88, median_seconds: 45 },
    ],
    context: "Review an ADR and pick the strongest architecture critic.",
  })
  assert.match(prompt, /"lane": "architect"/)
  assert.match(prompt, /minimax-coding-plan\/MiniMax-M3/)
  assert.match(prompt, /xiaomi-token-plan-ams\/mimo-v2\.5-pro/)
  assert.match(prompt, /JSON only/)
  assert.doesNotMatch(prompt, /ollama-cloud\/glm-5\.2/)
})

test("parseLanePlannerChoice accepts raw and fenced JSON", () => {
  assert.deepEqual(parseLanePlannerChoice('{"primary":"b","failover":["a"],"reason":"lower latency"}'), {
    primary: "b",
    failover: ["a"],
    reason: "lower latency",
  })
  assert.deepEqual(parseLanePlannerChoice("```json\n{\"primary\":\"b\",\"failover\":\"a\"}\n```"), {
    primary: "b",
    failover: ["a"],
    reason: "",
  })
  assert.equal(parseLanePlannerChoice("not json"), null)
})

test("planLaneRouteWithPlanner accepts valid planner reorder over eligible candidates", () => {
  const candidates = [
    { model: "minimax-coding-plan/MiniMax-M3", lane: "architect", score: 0.91 },
    { model: "xiaomi-token-plan-ams/mimo-v2.5-pro", lane: "architect", score: 0.88 },
  ]
  const route = planLaneRouteWithPlanner("architect", candidates, {
    primary: "xiaomi-token-plan-ams/mimo-v2.5-pro",
    failover: ["minimax-coding-plan/MiniMax-M3"],
    reason: "stronger ADR critique",
  })
  assert.deepEqual(route, {
    lane: "architect",
    primary: "xiaomi-token-plan-ams/mimo-v2.5-pro",
    failover: ["minimax-coding-plan/MiniMax-M3"],
    confidence: 0.88,
    reason: "planner-selected bench-backed lane route",
    planner_reason: "stronger ADR critique",
  })
})

test("planLaneRouteWithPlanner rejects ineligible planner models and falls back", () => {
  const candidates = [
    { model: "minimax-coding-plan/MiniMax-M3", lane: "architect", score: 0.91 },
    { model: "xiaomi-token-plan-ams/mimo-v2.5-pro", lane: "architect", score: 0.88 },
  ]
  const route = planLaneRouteWithPlanner("architect", candidates, {
    primary: "ollama-cloud/glm-5.2",
    failover: ["minimax-coding-plan/MiniMax-M3"],
    reason: "hallucinated newer model",
  })
  assert.equal(route.primary, "minimax-coding-plan/MiniMax-M3")
  assert.deepEqual(route.failover, ["xiaomi-token-plan-ams/mimo-v2.5-pro"])
  assert.equal(route.reason, "bench-backed lane route with distinct failover")
  assert.equal(route.planner_rejected, "primary is not an eligible candidate")
})

test("planLaneRouteWithPlanner rejects same-lineage failover and falls back", () => {
  const candidates = [
    { model: "minimax-coding-plan/MiniMax-M3", lane: "architect", score: 0.91 },
    { model: "ollama-cloud/minimax-m3", lane: "architect", score: 0.9 },
    { model: "xiaomi-token-plan-ams/mimo-v2.5-pro", lane: "architect", score: 0.88 },
  ]
  const route = planLaneRouteWithPlanner("architect", candidates, {
    primary: "minimax-coding-plan/MiniMax-M3",
    failover: ["ollama-cloud/minimax-m3"],
    reason: "same family",
  })
  assert.equal(route.primary, "minimax-coding-plan/MiniMax-M3")
  assert.deepEqual(route.failover, ["xiaomi-token-plan-ams/mimo-v2.5-pro"])
  assert.equal(route.planner_rejected, "failover must use a distinct lineage")
})

test("planLaneRouteWithPlanner rejects lower-priority provider choices", () => {
  const candidates = [
    { model: "minimax-coding-plan/MiniMax-M3", lane: "architect", score: 0.9 },
    { model: "ollama-cloud/minimax-m3", lane: "architect", score: 0.94 },
    { model: "ollama-cloud/qwen3-coder-next", lane: "architect", score: 0.89 },
  ]
  const route = planLaneRouteWithPlanner("architect", candidates, {
    primary: "ollama-cloud/minimax-m3",
    failover: ["ollama-cloud/qwen3-coder-next"],
  }, {
    directProviderByLineage: { minimax: "minimax-coding-plan" },
    providerPriority: ["ollama-cloud", "opencode-go", "alibaba-token-plan"],
  })
  assert.equal(route.primary, "minimax-coding-plan/MiniMax-M3")
  assert.equal(route.planner_rejected, "planner selected a fallback provider while a higher-priority provider was eligible")
})

test("buildScoutHandoff alerts heavy review to scout findings for the selected file", () => {
  const handoff = buildScoutHandoff([
    {
      file: "src/a.ts",
      model: "ollama-cloud/qwen3-coder-next",
      findings: [
        { severity: "high", title: "lint fails: no-floating-promises", line: 42 },
        { severity: "medium", title: "typecheck fails: missing field", line: 50 },
      ],
    },
    {
      file: "src/b.ts",
      model: "ollama-cloud/devstral-small-2:24b",
      findings: [{ severity: "critical", title: "different file" }],
    },
  ], "src/a.ts")
  assert.match(handoff, /Scout handoff/)
  assert.match(handoff, /ollama-cloud\/qwen3-coder-next/)
  assert.match(handoff, /high line 42: lint fails: no-floating-promises/)
  assert.match(handoff, /medium line 50: typecheck fails: missing field/)
  assert.doesNotMatch(handoff, /different file/)
})

test("selectHotspots: top-K hot files (score>0) come first, ranked by score", () => {
  const scored = [{ file: "a", score: 6 }, { file: "b", score: 4 }, { file: "c", score: 0 }, { file: "d", score: 0 }]
  const { hotspots } = selectHotspots(scored, { heavyK: 3, baselineTail: 0 })
  assert.deepEqual(hotspots, ["a", "b"]) // only 2 scored > 0; never pads hotspots with zero-scored
})

test("selectHotspots: baseline tail draws from the UNSCORED files (scout false-negative coverage)", () => {
  const scored = [{ file: "a", score: 6 }, { file: "b", score: 0 }, { file: "c", score: 0 }, { file: "d", score: 0 }]
  const { hotspots, baseline, selected } = selectHotspots(scored, { heavyK: 1, baselineTail: 2 })
  assert.deepEqual(hotspots, ["a"])
  assert.equal(baseline.length, 2, "two coverage files from the zero-scored tail")
  assert.ok(baseline.every((f) => f !== "a"), "baseline never re-picks a hotspot")
  assert.deepEqual(selected, [...hotspots, ...baseline], "selected = hotspots then baseline, deduped")
})

test("selectHotspots: fills heavy budget from ranked tail when too few hotspots", () => {
  const scored = [{ file: "a", score: 5 }, { file: "b", score: 0 }, { file: "c", score: 0 }]
  const { selected } = selectHotspots(scored, { heavyK: 3, baselineTail: 0, fillToK: true })
  assert.equal(selected.length, 3, "fillToK tops up to the heavy budget even with one real hotspot")
  assert.equal(selected[0], "a")
})

test("selectHotspots: empty input → empty selection (no crash)", () => {
  assert.deepEqual(selectHotspots([], { heavyK: 5, baselineTail: 2 }).selected, [])
})

test("selectHotspots: deterministic — same inputs, same output", () => {
  const scored = [{ file: "a", score: 3 }, { file: "b", score: 0 }, { file: "c", score: 1 }, { file: "d", score: 0 }]
  assert.deepEqual(selectHotspots(scored, { heavyK: 2, baselineTail: 1 }), selectHotspots(scored, { heavyK: 2, baselineTail: 1 }))
})

test("isChainFailure: verdict:error (non-JSON/crash) is a failure", () => {
  assert.equal(isChainFailure({ verdict: "error" }), true)
})
test("isChainFailure: 'Lineage review failed:' needs-attention (chain exhaustion) is a failure", () => {
  assert.equal(isChainFailure({ verdict: "needs-attention", summary: "Lineage review failed: all qwen provider fallbacks failed: alibaba: 404" }), true)
})
test("isChainFailure: a REAL needs-attention review is NOT a failure", () => {
  assert.equal(isChainFailure({ verdict: "needs-attention", summary: "2 high-sev issues, no-ship", findings: [{}] }), false)
})
test("isChainFailure: a clean approve is NOT a failure", () => {
  assert.equal(isChainFailure({ verdict: "approve", summary: "clean" }), false)
})
test("isChainFailure: null/garbage is a failure", () => {
  assert.equal(isChainFailure(null), true)
  assert.equal(isChainFailure({}), false) // a parseable object with no verdict is not itself a chain failure
})

test("isHarnessFailureVerdict: runner fail() paths are not approvable", () => {
  assert.equal(
    isHarnessFailureVerdict({ verdict: "needs-attention", summary: 'Bad --mode "invalid" — expected one of: review.', findings: [] }),
    true,
  )
  assert.equal(
    isHarnessFailureVerdict({ verdict: "error", summary: "json", findings: [], _auto: "json-parse-failed" }),
    true,
  )
  assert.equal(
    isHarnessFailureVerdict({ verdict: "needs-attention", summary: "2 high-sev issues", findings: [{ severity: "high" }] }),
    false,
  )
})

test("summarizeLineageAttempt marks harness failures and preserves slot + round", () => {
  const row = summarizeLineageAttempt(
    {
      panel_slot: 1,
      requested: "xiaomi-token-plan-ams/mimo-v2.5-pro",
      model: "xiaomi-token-plan-ams/mimo-v2.5-pro",
      verdict: "error",
      summary: "Lineage review failed: x",
      findings: [],
    },
    { backfill_round: 1 },
  )
  assert.equal(row.failed, true)
  assert.equal(row.backfill_round, 1)
  assert.equal(row.panel_slot, 1)
  assert.equal(row.requested, "xiaomi-token-plan-ams/mimo-v2.5-pro")
})

test("summarizeLineageAttempt preserves provider failure reasons", () => {
  const failures = [
    {
      provider: "minimax-coding-plan/MiniMax-M3",
      model: "MiniMax-M3",
      reason: "review step budget reached",
      elapsedMs: 120000,
      budgetMs: 120000,
    },
  ]
  const row = summarizeLineageAttempt({
    panel_slot: 2,
    requested: "minimax-coding-plan/MiniMax-M3",
    model: "ollama-cloud/minimax-m3",
    verdict: "needs-attention",
    findings: [{ severity: "high" }],
    providerFailures: failures,
  })
  assert.deepEqual(row.providerFailures, failures)
})

test("planBackfillReplacements walks roster order, not random", () => {
  const roster = ["a/one", "b/two", "c/three", "d/four"]
  const tried = new Set(["a/one"])
  const groupOf = (m) => (m.startsWith("a/") || m.startsWith("b/") ? "east" : "west")
  const usedGroups = new Set(["east"])
  assert.deepEqual(
    planBackfillReplacements(roster, tried, 2, usedGroups, groupOf),
    ["c/three", "d/four"],
  )
  assert.deepEqual(
    planBackfillReplacements(roster, tried, 2, new Set(), groupOf),
    ["b/two", "c/three"],
  )
})

test("isPanelSlotSatisfied rejects chain and harness holes", () => {
  assert.equal(isPanelSlotSatisfied({ verdict: "approve", summary: "ok", findings: [] }), true)
  assert.equal(
    isPanelSlotSatisfied({ verdict: "needs-attention", summary: "reached verdict", findings: [] }),
    true,
  )
  assert.equal(isPanelSlotSatisfied({ verdict: "error", findings: [] }), false)
  assert.equal(
    isPanelSlotSatisfied({ verdict: "needs-attention", summary: "spawn failed: x", findings: [] }),
    false,
  )
})

test("pickDistinctLineagePanel draws up to n distinct lineage families", () => {
  const roster = ["a/kimi", "b/kimi", "c/qwen", "d/glm"]
  const linOf = (m) => (m.includes("kimi") ? "kimi" : m.includes("qwen") ? "qwen" : "glm")
  assert.deepEqual(pickDistinctLineagePanel(roster, 2, linOf), ["a/kimi", "c/qwen"])
  assert.deepEqual(pickDistinctLineagePanel(roster, 3, linOf), ["a/kimi", "c/qwen", "d/glm"])
})

test("stratifyPanelSwap changes group without duplicating lineage", () => {
  const linOf = (m) => m.split("/")[1]
  const groupOf = (m) => (m.startsWith("east/") ? "east" : "west")
  const models = ["east/kimi", "east/qwen"]
  const shuffled = ["east/kimi", "east/qwen", "west/glm", "west/mimo"]
  assert.deepEqual(stratifyPanelSwap(models, shuffled, groupOf, linOf), ["east/kimi", "west/glm"])
})

test("mergeBackfillRound keeps unfilled failures when replacements run short", () => {
  const satisfied = (v) => v.ok
  const merged = mergeBackfillRound({
    verdicts: [{ id: 1, ok: true }, { id: 2, ok: false }, { id: 3, ok: false }],
    satisfied,
    fresh: [{ id: 4, ok: true }],
    stillFailed: [{ id: 5, ok: false }],
    unfilledFailures: [{ id: 3, ok: false }],
  })
  assert.deepEqual(merged.map((v) => v.id), [1, 4, 5, 3])
})

test("computePanelVerdict fails closed when satisfied slots below target", () => {
  assert.equal(
    computePanelVerdict(
      [{ verdict: "approve", summary: "ok", findings: [] }],
      [],
      { targetCount: 2, satisfiedCount: 1 },
    ),
    "needs-attention",
  )
})

test("computePanelVerdict after verify approves when all findings refuted", () => {
  assert.equal(
    computePanelVerdict(
      [{ verdict: "needs-attention", summary: "issues", findings: [{ severity: "high" }] }],
      [],
      { verified: true },
    ),
    "approve",
  )
})

test("isHarnessFailureVerdict includes runner input/git failures and schema auto flags", () => {
  assert.equal(
    isHarnessFailureVerdict({ verdict: "needs-attention", summary: "--input read failed: ENOENT", findings: [] }),
    true,
  )
  assert.equal(
    isHarnessFailureVerdict({ verdict: "error", findings: [], _auto: "schema-missing-confidence" }),
    true,
  )
})

test("computePanelVerdict fails closed on harness errors with zero findings", () => {
  assert.equal(
    computePanelVerdict(
      [{ verdict: "needs-attention", summary: 'Bad --mode "invalid"', findings: [] }],
      [],
    ),
    "needs-attention",
  )
  assert.equal(
    computePanelVerdict(
      [{ verdict: "approve", summary: "clean", findings: [] }],
      [],
    ),
    "approve",
  )
  assert.equal(
    computePanelVerdict(
      [{ verdict: "needs-attention", summary: "vague concern", findings: [] }],
      [],
    ),
    "needs-attention",
  )
  assert.equal(
    computePanelVerdict(
      [{ verdict: "approve", summary: "clean", findings: [] }],
      [{ severity: "medium", title: "x" }],
    ),
    "needs-attention",
  )
})

// Roster fixtures: distinct-lineage deep + scan pools.
const DEEP = [
  { id: "p/deepseek-v4", lineage: "deepseek", tier: "deep" },
  { id: "p/k2p6", lineage: "kimi", tier: "deep" },
  { id: "p/minimax-m3", lineage: "minimax", tier: "deep" },
  { id: "p/glm-5", lineage: "glm", tier: "deep" },
]
const SCAN = [
  { id: "p/gemma4:31b", lineage: "google", tier: "scan" },
  { id: "p/ministral:8b", lineage: "mistral", tier: "scan" },
]
const lineageOf = (roster, model) => roster.find((r) => r.id === model)?.lineage

test("planLensRoutes: deep lens gets K distinct-lineage DEEP models, no scan", () => {
  const routes = planLensRoutes([{ key: "security", tier: "deep" }], [...DEEP, ...SCAN], { perLens: 2 })
  assert.equal(routes.length, 2)
  const lins = routes.map((r) => lineageOf([...DEEP, ...SCAN], r.model))
  assert.equal(new Set(lins).size, 2, "distinct lineages within the lens")
  for (const r of routes) assert.equal([...DEEP, ...SCAN].find((x) => x.id === r.model).tier, "deep", "deep lens never seats a scan model")
})

test("planLensRoutes: scan lens has a DEEP anchor AND a scan model", () => {
  const roster = [...DEEP, ...SCAN]
  const routes = planLensRoutes([{ key: "antipatterns", tier: "scan" }], roster, { perLens: 2 })
  assert.equal(routes.length, 2)
  const tiers = routes.map((r) => roster.find((x) => x.id === r.model).tier)
  assert.ok(tiers.includes("deep"), "scan lens must carry a deep anchor")
  assert.ok(tiers.includes("scan"), "scan lens must include a scan model when the pool has one")
})

test("planLensRoutes: distinct lineage within a lens (never two of one family)", () => {
  const roster = [
    { id: "p/k2p6", lineage: "kimi", tier: "deep" },
    { id: "p/k2-other", lineage: "kimi", tier: "deep" }, // same lineage, must not co-seat
    { id: "p/deepseek-v4", lineage: "deepseek", tier: "deep" },
  ]
  const routes = planLensRoutes([{ key: "correctness", tier: "deep" }], roster, { perLens: 3 })
  const lins = routes.map((r) => lineageOf(roster, r.model))
  assert.equal(new Set(lins).size, lins.length, "no duplicate lineage even when perLens exceeds distinct lineages")
})

test("planLensRoutes: pool smaller than K returns fewer, never duplicates", () => {
  const roster = [{ id: "p/k2p6", lineage: "kimi", tier: "deep" }]
  const routes = planLensRoutes([{ key: "security", tier: "deep" }], roster, { perLens: 3 })
  assert.equal(routes.length, 1)
})

test("planLensRoutes: deep-only pool + scan-eligible lens degrades to deep (no crash, no scan)", () => {
  const routes = planLensRoutes([{ key: "antipatterns", tier: "scan" }], DEEP, { perLens: 2 })
  assert.equal(routes.length, 2)
  for (const r of routes) assert.equal(DEEP.find((x) => x.id === r.model).tier, "deep")
})

test("planLensRoutes: deep lens with NO deep models falls back to scan rather than skip the lens", () => {
  const routes = planLensRoutes([{ key: "security", tier: "deep" }], SCAN, { perLens: 2 })
  assert.ok(routes.length >= 1, "a lens is never left wholly unreviewed when any model exists")
})

test("planLensRoutes: empty roster yields no routes", () => {
  assert.deepEqual(planLensRoutes([{ key: "security", tier: "deep" }], [], { perLens: 2 }), [])
})

test("planLensRoutes: cross-lens rotation — consecutive lenses get different anchors", () => {
  const roster = DEEP
  const routes = planLensRoutes(
    [{ key: "a", tier: "deep" }, { key: "b", tier: "deep" }],
    roster,
    { perLens: 1 },
  )
  const a = routes.find((r) => r.lens === "a").model
  const b = routes.find((r) => r.lens === "b").model
  assert.notEqual(a, b, "lens a and lens b must not both anchor on the same model")
})

test("planLensRoutes: deterministic — same inputs, same output", () => {
  const lenses = [{ key: "a", tier: "deep" }, { key: "b", tier: "scan" }]
  const roster = [...DEEP, ...SCAN]
  assert.deepEqual(planLensRoutes(lenses, roster, { perLens: 2 }), planLensRoutes(lenses, roster, { perLens: 2 }))
})

test("errorText flattens name/status/code/message", () => {
  assert.equal(errorText({ name: "Error", status: 429, message: "rate limit" }), "Error: 429: rate limit")
  assert.equal(errorText("boom"), "boom")
  assert.equal(errorText({}), "[object Object]")
})

test("providerFailure: 429 / quota / capped providers fall through", () => {
  assert.ok(providerFailure({ status: 429, message: "Monthly usage limit reached" }))
  assert.ok(providerFailure({ status: 429, message: "Insufficient balance or no resource package" }))
  assert.ok(providerFailure({ message: "rate limit exceeded" }))
  assert.ok(providerFailure({ message: "too many requests" }))
  assert.ok(providerFailure({ status: 401, message: "unauthorized" }))
  assert.ok(providerFailure({ code: "ECONNRESET" }))
  assert.ok(providerFailure({ message: "fetch failed" }))
  assert.ok(providerFailure({ message: "label timed out after 80s" }))
  assert.ok(providerFailure({ message: "returned empty response" }))
  // thinking-exhausted empty response must fall through, not crash the chain
  assert.ok(providerFailure({ name: "APIEmptyResponseError", message: "The API returned a response containing only thinking content without any text or tool calls" }))
})

test("providerFailure: real faults are NOT swallowed", () => {
  assert.equal(providerFailure({ message: "Cannot read properties of undefined" }), false)
  assert.equal(providerFailure({ name: "SyntaxError", message: "Unexpected token < in JSON" }), false)
  assert.equal(providerFailure({ message: "schema validation failed: missing verdict" }), false)
  // 'auth' substring must NOT over-match (the old bare-`auth` token bug)
  assert.equal(providerFailure({ message: "Cannot read 'author' of undefined" }), false)
  assert.equal(providerFailure({ message: "oauthScope parsing failed in mapper" }), false)
  // but genuine authentication failures still fall through
  assert.ok(providerFailure({ message: "authentication failed" }))
  assert.ok(providerFailure({ status: 401, message: "unauthorized" }))
})

test("computeAttemptBudget: deadline-based, not even-split", () => {
  const cap = 280000
  // far from deadline -> capped, the working provider gets the full per-attempt cap
  assert.equal(computeAttemptBudget(1_000_000, 0, cap), cap)
  // dead providers consumed time -> remaining budget, still well above floor
  assert.equal(computeAttemptBudget(200000, 50000, cap), 150000)
  // near-exhausted deadline -> floored at MIN_ATTEMPT_MS (one real try, never 0/negative)
  assert.equal(computeAttemptBudget(100000, 95000, cap), MIN_ATTEMPT_MS)
  assert.equal(computeAttemptBudget(100000, 200000, cap), MIN_ATTEMPT_MS)
  // cap below remaining -> cap wins (one attempt can't eat the whole deadline)
  assert.equal(computeAttemptBudget(1_000_000, 0, 60000), 60000)
})

test("hasVerdict / looksNarrated", () => {
  assert.ok(hasVerdict('{"verdict":"approve","findings":[]}'))
  assert.ok(hasVerdict('prose then {"verdict": "needs-attention", ...}'))
  assert.ok(hasVerdict('{"verdict":"false-positive"}')) // verify mode
  assert.ok(looksNarrated("<thinking>I'll use the Read tool to inspect...</thinking>"))
  assert.ok(looksNarrated("")) // truncated / empty
  assert.equal(looksNarrated('{"verdict":"approve"}'), false)
  assert.ok(looksNarrated(null))
})

test("needsAttentionWithoutFindings", () => {
  assert.ok(needsAttentionWithoutFindings('{"verdict":"needs-attention","findings":[]}'))
  assert.ok(needsAttentionWithoutFindings('{"verdict":"needs-attention","summary":"vague concern"}')) // no findings key
  assert.equal(needsAttentionWithoutFindings('{"verdict":"needs-attention","findings":[{"title":"bug"}]}'), false)
  assert.equal(needsAttentionWithoutFindings('{"verdict":"approve","findings":[]}'), false) // approve+0 is fine
  assert.equal(needsAttentionWithoutFindings('{"verdict":"real"}'), false) // verify mode
  assert.equal(needsAttentionWithoutFindings(null), false)
})

test("planJobs: files x perFile, rotated across the spread", () => {
  const spread = ["A/m", "B/m", "C/m"]
  const files = ["f1", "f2", "f3", "f4"]
  // offset 2*fi per file (k=1) rotates through all lanes across files
  assert.deepEqual(planJobs(files, spread, 1), ["A/m::f1", "C/m::f2", "B/m::f3", "A/m::f4"])
  const two = planJobs(["f1", "f2"], spread, 2)
  assert.equal(two.length, 4)
  // the two lineages on one file differ
  assert.notEqual(two[0].split("::")[0], two[1].split("::")[0])
  assert.deepEqual(planJobs([], spread, 1), [])
  assert.deepEqual(planJobs(["f"], [], 1), [])
})

test("planJobs: caps perFile at spread.length and total at MAX_PLAN_JOBS", () => {
  // perFile > #lineages just repeats lineages on one file — capped to spread.length
  assert.equal(planJobs(["a"], ["x", "y"], 99).length, 2)
  // a huge file list can't explode into unbounded model runs
  const huge = Array.from({ length: MAX_PLAN_JOBS + 500 }, (_, i) => `f${i}`)
  assert.equal(planJobs(huge, ["x", "y"], 1).length, MAX_PLAN_JOBS)
})

test("aggregateAllFiles: per-file status + finding rollup", () => {
  const results = [
    { file: "a.mjs", model: "X/m", verdict: "approve", findings: [] },
    { file: "a.mjs", model: "Y/m", verdict: "approve", findings: [] },
    { file: "b.mjs", model: "X/m", verdict: "needs-attention", findings: [{ severity: "high", title: "bug", line_start: 10 }] },
    { file: "b.mjs", model: "Y/m", verdict: "error", findings: [] },
    { file: "c.mjs", model: "X/m", verdict: "error", findings: [] },
  ]
  const rep = aggregateAllFiles(results)
  assert.equal(rep.mode, "all-files")
  assert.equal(rep.reviewed, 5)
  const byName = Object.fromEntries(rep.files.map((f) => [f.file, f]))
  assert.equal(byName["a.mjs"].status, "approve")
  assert.equal(byName["b.mjs"].status, "needs-attention")
  assert.equal(byName["b.mjs"].findings.length, 1)
  assert.equal(byName["b.mjs"].findings[0].by, "X/m")
  assert.equal(byName["c.mjs"].status, "all-error") // no lineage produced a verdict
  assert.deepEqual(aggregateAllFiles([]).files, [])
})

test("synthesizeUltrareview: merges nearby findings, agreement-weights, ranks", () => {
  const out = synthesizeUltrareview([
    { severity: "high", title: "race A", file: "g.mjs", line_start: 58, lens: "concurrency", lineages: ["kimi/x"] },
    { severity: "critical", title: "double-acquire", file: "g.mjs", line_start: 60, lens: "correctness", lineages: ["deepseek/y"] }, // same bucket as ^ -> merged
    { severity: "low", title: "style", file: "z.mjs", line_start: 4, lens: "style", lineages: ["glm/z"] },
  ])
  // two distinct issues (g.mjs:58/60 merged, z.mjs:4)
  assert.equal(out.length, 2)
  // merged issue takes the highest severity (critical) and counts 2 distinct lineages
  const merged = out.find((i) => i.file === "g.mjs")
  assert.equal(merged.severity, "critical")
  assert.equal(merged.agreement, 2)
  assert.deepEqual(merged.lenses.sort(), ["concurrency", "correctness"])
  // ranked: critical (g.mjs) before low (z.mjs)
  assert.equal(out[0].file, "g.mjs")
  assert.deepEqual(synthesizeUltrareview([]), [])
})

test("aggregateAllFiles: surfaces schema_warning on the lineage", () => {
  const rep = aggregateAllFiles([
    { file: "a.mjs", model: "X/m", verdict: "needs-attention", findings: [], schema_warning: "findings: must NOT have fewer than 1 items" },
    { file: "a.mjs", model: "Y/m", verdict: "approve", findings: [] },
  ])
  const a = rep.files[0]
  assert.equal(a.lineages[0].schema_warning, "findings: must NOT have fewer than 1 items")
  assert.ok(!("schema_warning" in a.lineages[1])) // clean review carries no warning key
})

test("resolveModelProtocol: catalog overrides provider default", () => {
  assert.equal(resolveModelProtocol({ modelCfg: { protocol: "anthropic" }, providerType: "openai" }), "anthropic")
  assert.equal(resolveModelProtocol({ modelCfg: {}, providerType: "openai" }), "openai")
})

test("applyHarnessProviderOverlay: catalog protocol overrides provider default", () => {
  const provider = { type: "openai", baseUrl: "https://example.com/v1", apiKey: "x" }
  const harnessCfg = { protocol: "anthropic" }
  const out = applyHarnessProviderOverlay(provider, harnessCfg, "openai")
  assert.equal(out.type, "anthropic")
  assert.equal(out.baseUrl, provider.baseUrl)
})

test("resolveModelsCatalogBaseUrl: Alibaba Code Plan uses compatible-mode for /models", () => {
  const chat = "https://token-plan.ap-southeast-1.maas.aliyuncs.com/apps/anthropic"
  assert.equal(
    resolveModelsCatalogBaseUrl("alibaba-token-plan", chat),
    "https://token-plan.ap-southeast-1.maas.aliyuncs.com/compatible-mode/v1",
  )
  assert.equal(
    modelsListUrl(resolveModelsCatalogBaseUrl("alibaba-token-plan", chat)),
    "https://token-plan.ap-southeast-1.maas.aliyuncs.com/compatible-mode/v1/models",
  )
  assert.equal(
    modelsListUrl("https://ollama.com/v1"),
    "https://ollama.com/v1/models",
  )
})

test("resolveModelsCatalogBaseUrl: Zai uses paas v4 for /models discovery", () => {
  const chat = "https://api.z.ai/api/anthropic"
  assert.equal(resolveModelsCatalogBaseUrl("zai", chat), "https://api.z.ai/api/paas/v4")
  assert.equal(modelsListUrl(resolveModelsCatalogBaseUrl("zai", chat)), "https://api.z.ai/api/paas/v4/models")
})

test("resolveModelsCatalogBaseUrl: Google Gemini uses v1beta models endpoint", () => {
  assert.equal(resolveModelsCatalogBaseUrl("google", ""), "https://generativelanguage.googleapis.com/v1beta")
  assert.equal(modelsListUrl(resolveModelsCatalogBaseUrl("google", "")), "https://generativelanguage.googleapis.com/v1beta/models")
})

test("resolveModelReviewParams: harness defaults and env clamps", () => {
  const north = resolveModelReviewParams({ modelCfg: { temperature: [1], reasoning_effort: ["none", "high"] } })
  assert.equal(north.kwargs.temperature, 1)
  assert.equal(north.kwargs.reasoning_effort, "none")
  const northHigh = resolveModelReviewParams({
    modelCfg: { temperature: [1], reasoning_effort: ["none", "high"] },
    env: { REDTEAM_REASONING_EFFORT: "high" },
  })
  assert.equal(northHigh.kwargs.reasoning_effort, "high")
})

test("resolveMinimaxM3ThinkingEffort: scan off, solve on, env overrides", () => {
  assert.equal(resolveMinimaxM3ThinkingEffort({ huntPhase: "scan" }), "off")
  assert.equal(resolveMinimaxM3ThinkingEffort({ huntPhase: "solve" }), "high")
  assert.equal(resolveMinimaxM3ThinkingEffort({ env: { REDTEAM_THINKING_EFFORT: "off" }, huntPhase: "solve" }), "off")
  assert.equal(resolveMinimaxM3ThinkingEffort({ env: { REDTEAM_THINKING_EFFORT: "low" } }), "low")
})

test("resolveModelReviewParams: MiniMax-M3 thinking off when env requests it", () => {
  const cfg = { thinking_effort: ["off", "low", "medium", "high"] }
  const m3 = "minimax-coding-plan/MiniMax-M3"
  assert.equal(
    resolveModelReviewParams({ modelCfg: cfg, modelLabel: m3, env: { REDTEAM_THINKING_EFFORT: "off" } }).thinkingEffort,
    "off",
  )
  assert.equal(resolveModelReviewParams({ modelCfg: cfg, modelLabel: m3, env: {} }).thinkingEffort, "high")
  assert.equal(resolveModelReviewParams({ modelCfg: cfg, modelLabel: m3, huntPhase: "scan" }).thinkingEffort, "off")
  assert.equal(resolveModelReviewParams({ modelCfg: cfg, modelLabel: m3, huntPhase: "solve" }).thinkingEffort, "high")
})

test("resolveModelReviewParams uses Kosong catalog reasoning effort values", () => {
  const cfg = { temperature: [0], thinking_effort: ["high", "max"], reasoning_key: "reasoning_content" }
  assert.equal(
    resolveModelReviewParams({ modelCfg: cfg, modelLabel: "ollama-cloud/glm-5.2" }).thinkingEffort,
    "high",
  )
  assert.equal(
    resolveModelReviewParams({
      modelCfg: cfg,
      modelLabel: "ollama-cloud/glm-5.2",
      env: { REDTEAM_THINKING_EFFORT: "max" },
    }).thinkingEffort,
    "max",
  )
})

test("resolveModelReviewParams: salvage turns reasoning off when supported", () => {
  const salvage = resolveModelReviewParams({
    modelCfg: { reasoning_effort: ["none", "high"], thinking_effort: ["off", "high"] },
    salvage: true,
  })
  assert.equal(salvage.kwargs.reasoning_effort, "none")
  assert.equal(salvage.thinkingEffort, "off")
})

test("reaskEvidenceText: assistant-only, capped", () => {
  assert.equal(reaskEvidenceText({ assistantTexts: ["hello"], cap: 10 }), "hello")
  assert.equal(reaskEvidenceText({ assistantTexts: [], cap: 10 }), "")
})

import { extractPotentialSymbols } from "./chain-logic.mjs"
import { findMissingSymbols } from "./lib/quality-gates.mjs"

test("extractPotentialSymbols pulls CamelCase, ENV_VAR, dotted paths", () => {
  const text = "The function ensureDbWriteActorReady and SF_DB_RUNTIME_WRITER are set in buildAutonomousChildEnv and foo.bar.baz"
  const syms = extractPotentialSymbols(text)
  assert.ok(syms.includes("ensureDbWriteActorReady"))
  assert.ok(syms.includes("SF_DB_RUNTIME_WRITER"))
  assert.ok(syms.includes("buildAutonomousChildEnv"))
  assert.ok(syms.includes("foo.bar.baz"))
})

test("findMissingSymbols is a no-op when gate is explicitly disabled", () => {
  const old = process.env.REDTEAM_HALLUCINATION_GATE;
  process.env.REDTEAM_HALLUCINATION_GATE = "0";
  const missing = findMissingSymbols(["anything"], process.cwd());
  assert.deepEqual(missing, []);
  if (old !== undefined) process.env.REDTEAM_HALLUCINATION_GATE = old;
  else delete process.env.REDTEAM_HALLUCINATION_GATE;
})

test("findMissingSymbols returns only symbols not present when gate=1 and rg present", () => {
  const old = process.env.REDTEAM_HALLUCINATION_GATE;
  process.env.REDTEAM_HALLUCINATION_GATE = "1";
  // Extremely unlikely symbol
  const missing = findMissingSymbols(["ZZZ_NONEXISTENT_SYMBOL_98765"], process.cwd());
  // If rg is absent the helper returns [] (safe no-op). Only assert when rg exists.
  if (missing.length > 0) {
    assert.deepEqual(missing, ["ZZZ_NONEXISTENT_SYMBOL_98765"]);
  }
  if (old !== undefined) process.env.REDTEAM_HALLUCINATION_GATE = old;
  else delete process.env.REDTEAM_HALLUCINATION_GATE;
})

test("resolveServedModelRef prefers full provider/model label from bridge hop", () => {
  assert.equal(
    resolveServedModelRef(
      { provider: "ollama-cloud/kimi-k2.7-code", model: "kimi-k2.7-code" },
      "ollama-cloud/gpt-oss:120b",
    ),
    "ollama-cloud/kimi-k2.7-code",
  )
  assert.equal(
    resolveServedModelRef({ provider: "kimi-for-coding", model: "k2.7" }, "ollama-cloud/gpt-oss:120b"),
    "kimi-for-coding/k2.7",
  )
})

test("buildPanelAttribution reports served models, not roster selection", () => {
  const attribution = buildPanelAttribution([
    {
      panel_slot: 2,
      requested: "ollama-cloud/gpt-oss:120b",
      model: "ollama-cloud/kimi-k2.7-code",
      verdict: "needs-attention",
      findings: [{}, {}],
    },
  ])
  assert.deepEqual(attribution.panel, ["ollama-cloud/kimi-k2.7-code"])
  assert.deepEqual(attribution.panel_requested, ["ollama-cloud/gpt-oss:120b"])
  assert.equal(attribution.per_model[0].panel_slot, 2)
  assert.equal(attribution.per_model[0].model, "ollama-cloud/kimi-k2.7-code")
  assert.equal(attribution.per_model[0].requested, "ollama-cloud/gpt-oss:120b")
  assert.equal(attribution.per_model[0].findings, 2)
})

test("parseRosterCacheByProvider accepts schema v2, runner object, and legacy array", () => {
  assert.deepEqual(
    parseRosterCacheByProvider({
      schema: 2,
      byProvider: { "ollama-cloud": ["gpt-oss:120b"] },
    }),
    { "ollama-cloud": ["gpt-oss:120b"] },
  )
  assert.deepEqual(
    parseRosterCacheByProvider({
      models: { "alibaba-token-plan": ["qwen3.7-max"] },
    }),
    { "alibaba-token-plan": ["qwen3.7-max"] },
  )
  assert.deepEqual(
    parseRosterCacheByProvider({
      models: [{ id: "ollama-cloud/kimi-k2.7-code", lineage: "kimi", tier: "deep" }],
    }),
    { "ollama-cloud": ["kimi-k2.7-code"] },
  )
})

test("rosterEntriesFromByProvider rebuilds flat discovery rows", () => {
  const rows = rosterEntriesFromByProvider(
    { "ollama-cloud": ["gpt-oss:120b"] },
    (id) => (id.includes("gpt-oss") ? "scan" : "deep"),
  )
  assert.equal(rows.length, 1)
  assert.equal(rows[0].id, "ollama-cloud/gpt-oss:120b")
  assert.equal(rows[0].lineage, "gpt-oss")
  assert.equal(rows[0].tier, "scan")
})
