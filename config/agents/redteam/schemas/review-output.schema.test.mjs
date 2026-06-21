/**
 * review-output.schema.test.mjs — node:test suite for schemas/review-output.schema.json
 *
 * Run: node --test schemas/review-output.schema.test.mjs
 * (from /home/mhugo/.claude/redteam)
 */
import { readFileSync } from "node:fs"
import { dirname, join } from "node:path"
import { fileURLToPath } from "node:url"
import { describe, it } from "node:test"
import assert from "node:assert/strict"

// Mirror the exact Ajv construction used in runner.mjs (line 18/214):
// `import Ajv2020 from "ajv/dist/2020.js"` + `new Ajv2020({ allErrors: true })`
import Ajv2020 from "ajv/dist/2020.js"

const HERE = dirname(fileURLToPath(import.meta.url))
const schema = JSON.parse(readFileSync(join(HERE, "review-output.schema.json"), "utf8"))

const ajv = new Ajv2020({ allErrors: true })
const validate = ajv.compile(schema)

// Minimal valid finding — satisfies all required fields
function makeFind(overrides = {}) {
  return {
    severity: "high",
    title: "SQL injection in query builder",
    body: "User input is concatenated directly into the SQL string at src/db.ts:42.",
    file: "src/db.ts",
    line_start: 42,
    line_end: 44,
    confidence: 0.9,
    recommendation: "Use parameterized queries.",
    ...overrides,
  }
}

// Minimal valid review verdict
function makeVerdict(overrides = {}) {
  return {
    verdict: "approve",
    summary: "No issues found.",
    findings: [],
    next_steps: [],
    ...overrides,
  }
}

// ── (a) needs-attention with 0 findings must FAIL ───────────────────────────
describe("needs-attention + empty findings", () => {
  it("fails validation when findings is empty", () => {
    const obj = makeVerdict({ verdict: "needs-attention", summary: "Something looks off." })
    const ok = validate(obj)
    assert.equal(ok, false, "Expected validation to fail for needs-attention with 0 findings")
    const msgs = (validate.errors || []).map((e) => `${e.instancePath} ${e.message}`)
    assert.ok(
      msgs.some((m) => /findings.*minItems|minItems.*1|must NOT have fewer/i.test(m)),
      `Expected a minItems error on findings, got: ${msgs.join("; ")}`,
    )
  })
})

// ── (b) needs-attention with ≥1 finding must PASS ───────────────────────────
describe("needs-attention + non-empty findings", () => {
  it("passes validation when findings has at least one entry", () => {
    const obj = makeVerdict({
      verdict: "needs-attention",
      summary: "Critical SQL injection found.",
      findings: [makeFind()],
    })
    const ok = validate(obj)
    assert.equal(ok, true, `Expected validation to pass, errors: ${JSON.stringify(validate.errors)}`)
  })

  it("passes validation when findings has multiple entries", () => {
    const obj = makeVerdict({
      verdict: "needs-attention",
      summary: "Multiple issues.",
      findings: [makeFind(), makeFind({ severity: "medium", title: "Missing input sanitisation", file: "src/api.ts", line_start: 10, line_end: 12 })],
    })
    const ok = validate(obj)
    assert.equal(ok, true, `Expected validation to pass, errors: ${JSON.stringify(validate.errors)}`)
  })
})

// ── (c) approve with 0 findings must PASS ───────────────────────────────────
describe("approve + empty findings", () => {
  it("passes validation with empty findings", () => {
    const obj = makeVerdict({ verdict: "approve", summary: "LGTM." })
    const ok = validate(obj)
    assert.equal(ok, true, `Expected validation to pass, errors: ${JSON.stringify(validate.errors)}`)
  })

  it("passes validation with non-empty findings (approve may still list low findings)", () => {
    const obj = makeVerdict({
      verdict: "approve",
      summary: "Looks good, minor nit only.",
      findings: [makeFind({ severity: "low", confidence: 0.3 })],
    })
    const ok = validate(obj)
    assert.equal(ok, true, `Expected validation to pass, errors: ${JSON.stringify(validate.errors)}`)
  })
})

// ── (d) injected model and schema_warning properties must PASS ──────────────
//    Evidence:
//      model         — runner.mjs line 800: normalized.model = bridgeResult.provider || modelArg
//      schema_warning — runner.mjs line 243: verdict.schema_warning = validateReview.errors?.map(...).join("; ")
describe("pipeline-injected top-level properties", () => {
  it("passes with model string injected (the normal case)", () => {
    const obj = {
      ...makeVerdict({ verdict: "approve", summary: "LGTM." }),
      model: "kimi-for-coding/k2p6",
    }
    const ok = validate(obj)
    assert.equal(ok, true, `Expected validation to pass with model, errors: ${JSON.stringify(validate.errors)}`)
  })

  it("passes with schema_warning string injected (repair-then-validate fallback)", () => {
    const obj = {
      ...makeVerdict({ verdict: "approve", summary: "Shape nit annotated." }),
      model: "ollama-cloud/mistral-large-3:675b",
      schema_warning: "/ findings must NOT have fewer than 1 items",
    }
    const ok = validate(obj)
    assert.equal(ok, true, `Expected validation to pass with schema_warning, errors: ${JSON.stringify(validate.errors)}`)
  })

  it("fails when an unknown injected property appears (additionalProperties: false is not loosened)", () => {
    const obj = {
      ...makeVerdict({ verdict: "approve", summary: "LGTM." }),
      model: "kimi",
      providerFailures: [],  // NOT injected onto the verdict — lives on bridgeResult only
    }
    const ok = validate(obj)
    assert.equal(ok, false, "Expected validation to FAIL for a property not declared in the schema (providerFailures)")
  })
})

// ── (e) verify-mode objects are out of scope (bypassed before validateReview) ─
//    Evidence: runner.mjs line 228:
//      if (mode === "verify") return verdict   ← early return, validateReview never called
//    Therefore the schema correctly does NOT cover real/false-positive verdicts.
//    We assert this by confirming verify objects fail the review schema (correct behaviour).
describe("verify-mode objects (out of scope)", () => {
  it("correctly rejects a verify-mode verdict (real) — schema is review-only", () => {
    const obj = {
      verdict: "real",
      confidence: 0.95,
      reason: "The race condition is present at src/lock.ts:17.",
    }
    const ok = validate(obj)
    // verdict "real" is not in the review enum, and required fields (summary etc.) are absent.
    // Failure is EXPECTED and CORRECT — verify objects bypass validateReview at line 228.
    assert.equal(ok, false, "Verify-mode object should fail the review schema — it is intentionally out of scope")
  })

  it("correctly rejects a verify-mode verdict (false-positive)", () => {
    const obj = {
      verdict: "false-positive",
      confidence: 0.7,
      reason: "The lock is always held before the shared state is read.",
    }
    const ok = validate(obj)
    assert.equal(ok, false, "Verify-mode object should fail the review schema — it is intentionally out of scope")
  })
})
