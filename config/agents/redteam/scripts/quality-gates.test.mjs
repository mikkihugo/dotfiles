import assert from "node:assert/strict"
import test from "node:test"
import { applyHallucinationGate, findMissingSymbols, verifySchemaAndHardCap } from "./lib/quality-gates.mjs"

test("verifySchemaAndHardCap preserves schema-warning findings from reached verdicts", () => {
  const raw = JSON.stringify({
    verdict: "needs-attention",
    summary: "model reached a verdict with useful but schema-drifted findings",
    findings: [
      {
        severity: "high",
        title: "Missing bounded wait",
        body: "File: scripts/companion.mjs\nLines: 10-12\nConfidence: 0.9\nThe wait path can block indefinitely.",
        recommendation: "Bound the wait or require an explicit unbounded mode.",
      },
    ],
    next_steps: ["Inspect the wait path."],
    schema_warning: "/findings/0 must have required property 'confidence'",
  })

  const verdict = verifySchemaAndHardCap(raw, "ollama-cloud/gpt-oss:120b")

  assert.equal(verdict.verdict, "needs-attention")
  assert.equal(verdict._auto, undefined)
  assert.equal(verdict.findings.length, 1)
  assert.equal(verdict.schema_warning, "/findings/0 must have required property 'confidence'")
})

test("hallucination gate is enabled by default and catches double-underscore symbols", () => {
  const old = process.env.REDTEAM_HALLUCINATION_GATE
  delete process.env.REDTEAM_HALLUCINATION_GATE
  const asserted = "__SF_" + "MISSING_REVIEW_CACHE_98765"
  const missing = findMissingSymbols([asserted], process.cwd())
  assert.deepEqual(missing, [asserted])
  if (old !== undefined) process.env.REDTEAM_HALLUCINATION_GATE = old
  else delete process.env.REDTEAM_HALLUCINATION_GATE
})

test("applyHallucinationGate annotates findings with missing asserted symbols by default", () => {
  const old = process.env.REDTEAM_HALLUCINATION_GATE
  delete process.env.REDTEAM_HALLUCINATION_GATE
  const asserted = "__SF_" + "MISSING_REVIEW_CACHE_98765"
  const [row] = applyHallucinationGate([
    {
      model: "ollama-cloud/qwen3-coder-next",
      findings: [
        {
          severity: "critical",
          title: "Global cache persists across test runs",
          body: `The code uses globalThis.${asserted} to cache data.`,
          file: "src/resources/extensions/sf/tools/inputs/self-feedback-corpus.ts",
          line_start: 15,
          line_end: 35,
          confidence: 0.95,
          recommendation: "Remove the cache.",
        },
      ],
    },
  ], { repoRoot: process.cwd(), record: false })
  assert.match(row.findings[0].title, /HALLUCINATED SYMBOLS/)
  assert.deepEqual(row.findings[0]._hallucination.missing, [
    asserted,
    `globalThis.${asserted}`,
  ])
  if (old !== undefined) process.env.REDTEAM_HALLUCINATION_GATE = old
  else delete process.env.REDTEAM_HALLUCINATION_GATE
})
