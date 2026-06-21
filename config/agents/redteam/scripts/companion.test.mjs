// node --test scripts/companion.test.mjs
import { test } from "node:test"
import assert from "node:assert/strict"
import { execFileSync } from "node:child_process"
import { existsSync, readFileSync } from "node:fs"
import { dirname, join } from "node:path"
import { fileURLToPath } from "node:url"

const HERE = dirname(fileURLToPath(import.meta.url))
const ROOT = join(HERE, "..")

test("setup reports lane routing surfaces and bench evidence status", () => {
  const out = execFileSync(process.execPath, [join(HERE, "companion.mjs"), "setup", "--json"], {
    cwd: ROOT,
    encoding: "utf8",
  })
  const payload = JSON.parse(out)
  const checks = new Map(payload.checks.map((check) => [check.name, check]))
  assert.equal(checks.get("command:architect")?.ok, true)
  assert.equal(checks.get("prompt:route")?.ok, true)
  assert.equal(checks.get("model-bench.json")?.ok, true)
  assert.match(checks.get("model-bench.json")?.detail || "", /passed lane entries/)
})

test("architect command is a first-class bench-backed lane command", () => {
  const commandPath = join(ROOT, "commands", "architect.md")
  assert.equal(existsSync(commandPath), true)
  const body = readFileSync(commandPath, "utf8")
  assert.match(body, /--lane architect/)
  assert.match(body, /--mode decision/)
  assert.match(body, /REDTEAM_LANE_PLANNER_MODEL|--lane-planner-model/)
})

test("package metadata ships docs and the feature index", () => {
  const pkg = JSON.parse(readFileSync(join(ROOT, "package.json"), "utf8"))
  assert.ok(pkg.files.includes("README.md"))
  assert.ok(pkg.files.includes("docs"))
})

test("provider-status command is a packaged operator command", () => {
  const commandPath = join(ROOT, "commands", "provider-status.md")
  assert.equal(existsSync(commandPath), true)
  const body = readFileSync(commandPath, "utf8")
  assert.match(body, /companion\.mjs" provider-status/)
  assert.match(body, /--json/)
})
