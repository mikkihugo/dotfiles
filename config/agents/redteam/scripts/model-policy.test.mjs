import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import { dirname, join } from "node:path"
import test from "node:test"
import { fileURLToPath } from "node:url"
import { FORBIDDEN_MODEL_POLICY_KEYS, validateModelsPolicy } from "./model-policy.mjs"

const HERE = dirname(fileURLToPath(import.meta.url))

test("models.json is lineage policy, not a concrete model registry", () => {
  const cfg = JSON.parse(readFileSync(join(HERE, "..", "models.json"), "utf8"))
  const policy = validateModelsPolicy(cfg)
  assert.deepEqual(policy.errors, [])
  for (const key of FORBIDDEN_MODEL_POLICY_KEYS) {
    assert.equal(Object.hasOwn(cfg, key), false, `${key} must stay out of models.json`)
  }
  assert.ok(Object.keys(cfg.lineage_provider_seeds || {}).length > 0, "lineage provider policy is required")
  assert.deepEqual(
    Object.keys(cfg.model_params || {}).filter((key) => key !== "_default").sort(),
    ["opencode-go/kimi-k2.7-code", "opencode-go/qwen3.7-max"].sort(),
  )
})

test("models policy rejects old concrete registry keys", () => {
  const policy = validateModelsPolicy({
    lineages: { qwen: "Qwen" },
    lineage_provider_seeds: { qwen: ["opencode-go"] },
    model_params: { _default: { temperature: [0] } },
    roster: ["opencode-go/qwen3.7-plus"],
  })
  assert.equal(policy.ok, false)
  assert.match(policy.errors.join("\n"), /roster is forbidden/)
})

test("models policy validates disabled and deprioritized lineage knobs", () => {
  const policy = validateModelsPolicy({
    lineages: { qwen: "Qwen" },
    lineage_provider_seeds: { qwen: ["ollama-cloud"] },
    model_params: { _default: { temperature: [0] } },
    disabled_lineages: { missing: "stale" },
    deprioritized_lineages: { qwen: "" },
    disabled_models: { "opencode-go/qwen": "disabled by provider" },
  })
  assert.equal(policy.ok, false)
  assert.match(policy.errors.join("\n"), /disabled_lineages\.missing has no matching lineage/)
  assert.match(policy.errors.join("\n"), /deprioritized_lineages\.qwen must be a non-empty string reason/)
})
