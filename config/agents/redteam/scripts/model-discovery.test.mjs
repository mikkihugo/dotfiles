import assert from "node:assert/strict"
import test from "node:test"
import { writeFileSync, unlinkSync } from "node:fs"
import { join } from "node:path"
import { tmpdir } from "node:os"
import { classifyTier, classifyHuntTier, inferLineage, discoverModels, inspectProviderStatus, isHuntScanPoolModel, isHuntSolvePoolModel } from "./model-discovery.mjs"
import { rosterCacheWriteBody } from "./chain-logic.mjs"
import { isMinimaxM3Model } from "./chain-logic.mjs"

test("classifyTier — scan (small/fast)", () => {
  for (const m of [
    "ollama-cloud/gemma4:31b",
    "ollama-cloud/gemma3:4b",
    "ollama-cloud/deepseek-v4-flash",
    "ollama-cloud/gpt-oss:20b",
    "ollama-cloud/ministral-3:8b",
    "ollama-cloud/nemotron-3-nano:30b",
    "ollama-cloud/devstral-small-2:24b",
    "google/gemini-2.5-flash",
  ]) {
    assert.equal(classifyTier(m), "scan", m)
  }
})

test("classifyTier — deep (heavyweight)", () => {
  for (const m of [
    "minimax-coding-plan/MiniMax-M3",
    "ollama-cloud/minimax-m3",
    "opencode-go/minimax-m3-free",
    "ollama-cloud/mistral-large-3:675b",
    "ollama-cloud/cogito-2.1:671b",
    "ollama-cloud/deepseek-v4-pro",
    "opencode-go/qwen3.7-max",
    "ollama-cloud/kimi-k2:1t",
    "ollama-cloud/qwen3.5:397b",
    "ollama-cloud/qwen3-coder:480b",
    "ollama-cloud/gpt-oss:120b",
    "ollama-cloud/glm-5.1", // no param, no keyword -> conservative deep
    "ollama-cloud/minimax-m2.7",
    "ollama-cloud/nemotron-3-super",
  ]) {
    assert.equal(classifyTier(m), "deep", m)
  }
})

test("classifyHuntTier — scan/small/solve rotation buckets", () => {
  assert.equal(classifyHuntTier("nemotron-3-nano:30b"), "scan")
  assert.equal(classifyHuntTier("minimax-coding-plan/MiniMax-M3"), "solve")
  assert.equal(classifyHuntTier("ollama-cloud/minimax-m3"), "solve")
  assert.equal(classifyHuntTier("minimax-coding-plan/MiniMax-M2.7"), "solve")
  assert.equal(classifyHuntTier("ollama-cloud/minimax-m2.7"), "solve")
  assert.equal(classifyHuntTier("deepseek-v4-flash"), "scan")
  assert.equal(classifyHuntTier("gemma3:12b"), "small")
  assert.equal(classifyHuntTier("deepseek-v4-pro"), "solve")
  assert.equal(classifyHuntTier("glm-5.2"), "solve")
})

test("isMinimaxM3Model — M3 only, not M2.x", () => {
  assert.equal(isMinimaxM3Model("minimax-coding-plan/MiniMax-M3"), true)
  assert.equal(isMinimaxM3Model("opencode-go/minimax-m3-free"), true)
  assert.equal(isMinimaxM3Model("MiniMax-M2.7-highspeed"), false)
  assert.equal(isMinimaxM3Model("minimax-m2.5"), false)
})

test("isHuntScanPoolModel / isHuntSolvePoolModel — M3 in both pools", () => {
  const m3 = "minimax-coding-plan/MiniMax-M3"
  assert.equal(isHuntScanPoolModel(m3), true)
  assert.equal(isHuntSolvePoolModel(m3), true)
  assert.equal(isHuntScanPoolModel("deepseek-v4-flash"), true)
  assert.equal(isHuntSolvePoolModel("deepseek-v4-flash"), false)
})

test("inferLineage — families incl. the scan-tier additions", () => {
  const cases = {
    "ollama-cloud/gemma4:31b": "google",
    "ollama-cloud/devstral-small-2:24b": "mistral",
    "ollama-cloud/ministral-3:8b": "mistral",
    "ollama-cloud/mistral-large-3:675b": "mistral",
    "ollama-cloud/deepseek-v4-flash": "deepseek",
    "ollama-cloud/gpt-oss:20b": "gpt-oss",
    "ollama-cloud/nemotron-3-nano:30b": "nemotron",
    "opencode-go/qwen3.7-max": "qwen",
    "ollama-cloud/kimi-k2.6": "kimi",
    "ollama-cloud/glm-5.1": "glm",
    "ollama-cloud/minimax-m3": "minimax",
    "opencode-go/mimo-v2.5-pro": "mimo",
    "ollama-cloud/cogito-2.1:671b": "cogito",
  }
  for (const [id, lin] of Object.entries(cases)) assert.equal(inferLineage(id), lin, id)
  assert.equal(inferLineage("something-unknown"), null)
})

test("discoverModels — cache fast-path, no network", async () => {
  const cachePath = join(tmpdir(), `rt-discovery-cache-${process.pid}.json`)
  writeFileSync(
    cachePath,
    JSON.stringify(
      rosterCacheWriteBody({
        "ollama-cloud": ["gemma4:31b"],
      }, Date.now()),
    ),
  )
  let fetched = false
  const models = await discoverModels({
    cachePath,
    now: () => Date.now(),
    fetchImpl: async () => {
      fetched = true
      return { ok: true, json: async () => ({ data: [] }) }
    },
    configPath: "/nonexistent",
    ttlMs: 60_000,
  })
  try { unlinkSync(cachePath) } catch {}
  assert.equal(fetched, false)
  assert.equal(models.length, 1)
  assert.equal(models[0].id, "ollama-cloud/gemma4:31b")
})

test("discoverModels — graceful [] when config + cache both unavailable", async () => {
  const models = await discoverModels({
    configPath: "/definitely/missing/config.toml",
    cachePath: "/definitely/missing/cache.json",
    fetchImpl: async () => ({ ok: false }),
  })
  assert.deepEqual(models, [])
})

test("discoverModels — configured direct MiniMax aliases participate when live catalog is absent", async () => {
  const configPath = join(tmpdir(), `rt-discovery-config-${process.pid}.toml`)
  writeFileSync(
    configPath,
    [
      '[providers.minimax-coding-plan]',
      'type = "anthropic"',
      'api_key = "k"',
      'base_url = "https://api.minimax.io/anthropic"',
      '[providers.ollama-cloud]',
      'type = "openai"',
      'api_key = "k"',
      'base_url = "https://ollama.com/v1"',
      '[models."minimax-coding-plan/MiniMax-M3"]',
      'provider = "minimax-coding-plan"',
      'model = "MiniMax-M3"',
      '[models."ollama-cloud/minimax-m3"]',
      'provider = "ollama-cloud"',
      'model = "minimax-m3"',
    ].join("\n"),
  )
  const models = await discoverModels({
    configPath,
    cachePath: null,
    fetchImpl: async () => ({ ok: false }),
  })
  try { unlinkSync(configPath) } catch {}
  assert.ok(models.some((m) => m.id === "minimax-coding-plan/MiniMax-M3"))
  assert.ok(models.some((m) => m.id === "ollama-cloud/minimax-m3"))
})

test("discoverModels — default selection excludes live-only models without configured metadata", async () => {
  const configPath = join(tmpdir(), `rt-discovery-live-only-${process.pid}.toml`)
  writeFileSync(
    configPath,
    [
      '[providers.ollama-cloud]',
      'type = "openai"',
      'api_key = "k"',
      'base_url = "https://ollama.com/v1"',
      '[models."ollama-cloud/glm-5.1"]',
      'provider = "ollama-cloud"',
      'model = "glm-5.1"',
      'max_context_size = 202752',
      'capabilities = ["thinking", "tool_use"]',
    ].join("\n"),
  )
  const models = await discoverModels({
    configPath,
    cachePath: null,
    fetchImpl: async () => ({
      ok: true,
      json: async () => ({ data: [{ id: "glm-5.1" }, { id: "glm-5.2" }] }),
    }),
  })
  try { unlinkSync(configPath) } catch {}
  assert.deepEqual(models.map((m) => m.id), ["ollama-cloud/glm-5.1"])
})

test("discoverModels — explicit includeLiveOnly keeps live inventory mode available", async () => {
  const configPath = join(tmpdir(), `rt-discovery-live-inventory-${process.pid}.toml`)
  writeFileSync(
    configPath,
    [
      '[providers.ollama-cloud]',
      'type = "openai"',
      'api_key = "k"',
      'base_url = "https://ollama.com/v1"',
      '[models."ollama-cloud/glm-5.1"]',
      'provider = "ollama-cloud"',
      'model = "glm-5.1"',
    ].join("\n"),
  )
  const models = await discoverModels({
    configPath,
    cachePath: null,
    includeLiveOnly: true,
    fetchImpl: async () => ({
      ok: true,
      json: async () => ({ data: [{ id: "glm-5.1" }, { id: "glm-5.2" }] }),
    }),
  })
  try { unlinkSync(configPath) } catch {}
  assert.deepEqual(models.map((m) => m.id), ["ollama-cloud/glm-5.1", "ollama-cloud/glm-5.2"])
})

test("inspectProviderStatus reports configured providers, live catalog, and lineages", async () => {
  const configPath = join(tmpdir(), `rt-provider-status-${process.pid}.toml`)
  writeFileSync(
    configPath,
    [
      '[providers.ollama-cloud]',
      'type = "openai"',
      'api_key = "k"',
      'base_url = "https://ollama.com/v1"',
      '[providers.google]',
      'type = "google"',
      'base_url = "https://generativelanguage.googleapis.com/v1beta"',
      '[models."ollama-cloud/qwen3-coder-next"]',
      'provider = "ollama-cloud"',
      'model = "qwen3-coder-next"',
      '[models."ollama-cloud/gpt-oss:20b"]',
      'provider = "ollama-cloud"',
      'model = "gpt-oss:20b"',
      '[models."google/gemini-2.5-flash"]',
      'provider = "google"',
      'model = "gemini-2.5-flash"',
    ].join("\n"),
  )
  const rows = await inspectProviderStatus({
    configPath,
    fetchImpl: async (url) => {
      assert.equal(String(url), "https://ollama.com/v1/models")
      return { ok: true, status: 200, json: async () => ({ data: [{ id: "qwen3-coder-next" }, { id: "gpt-oss:20b" }] }) }
    },
  })
  try { unlinkSync(configPath) } catch {}
  assert.deepEqual(rows.map((row) => row.provider), ["google", "ollama-cloud"])
  assert.deepEqual(rows.find((row) => row.provider === "ollama-cloud"), {
    provider: "ollama-cloud",
    configured: true,
    has_key: true,
    type: "openai",
    catalog_url: "https://ollama.com/v1/models",
    live: "ok",
    live_model_count: 2,
    declared_aliases: 2,
    live_declared_aliases: 2,
    lineages: ["gpt-oss", "qwen"],
    error: "",
  })
  assert.equal(rows.find((row) => row.provider === "google")?.live, "missing-key")
})

test("inspectProviderStatus treats managed Kimi env key as configured", async () => {
  const configPath = join(tmpdir(), `rt-provider-status-kimi-${process.pid}.toml`)
  writeFileSync(
    configPath,
    [
      '[providers."managed:kimi-code"]',
      'type = "kimi"',
      'base_url = "https://api.kimi.com/coding"',
      '[models."kimi-code/kimi-for-coding"]',
      'provider = "managed:kimi-code"',
      'model = "kimi-for-coding"',
    ].join("\n"),
  )
  const rows = await inspectProviderStatus({
    configPath,
    live: false,
    env: { KIMI_API_KEY: "k" },
  })
  try { unlinkSync(configPath) } catch {}
  assert.equal(rows[0].provider, "managed:kimi-code")
  assert.equal(rows[0].has_key, true)
})

test("inspectProviderStatus uses Gemini catalog default and API-key header", async () => {
  const configPath = join(tmpdir(), `rt-provider-status-google-${process.pid}.toml`)
  writeFileSync(
    configPath,
    [
      '[providers.google]',
      'type = "google-genai"',
      'api_key = "g"',
      '[models."google/gemini-2.5-flash"]',
      'provider = "google"',
      'model = "gemini-2.5-flash"',
    ].join("\n"),
  )
  const rows = await inspectProviderStatus({
    configPath,
    fetchImpl: async (url, init = {}) => {
      assert.equal(String(url), "https://generativelanguage.googleapis.com/v1beta/models")
      assert.equal(init.headers["x-goog-api-key"], "g")
      assert.equal(init.headers.Authorization, undefined)
      return { ok: true, status: 200, json: async () => ({ models: [{ name: "models/gemini-2.5-flash" }] }) }
    },
  })
  try { unlinkSync(configPath) } catch {}
  assert.equal(rows[0].live, "ok")
  assert.equal(rows[0].live_declared_aliases, 1)
})
