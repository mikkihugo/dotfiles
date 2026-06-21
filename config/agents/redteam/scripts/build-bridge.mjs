#!/usr/bin/env node
// Builds scripts/bridge.bundle.mjs — the runner reviewer bridge bundled
// (agent-core + kosong + deps → one JS) so the runner runs plain `node` instead
// of cold-starting tsx per call (~4.3s/call faster). RERUN after editing the
// BRIDGE template in runner.mjs or after pulling/updating kimi-code:
//   node scripts/build-bridge.mjs
import { mkdirSync, readFileSync, renameSync, writeFileSync } from "node:fs"
import { dirname, join } from "node:path"
import { fileURLToPath } from "node:url"
import * as esbuild from "esbuild"
import lockfile from "proper-lockfile"

const HERE = dirname(fileURLToPath(import.meta.url))
// Honor KIMI_CODE_ROOT like the runner does, so the bundle builds on any machine
// (the hardcoded default is only a fallback for the primary dev box).
const KIMI = process.env.KIMI_CODE_ROOT || "/home/mhugo/code/kimi-code"
const LOCK_DIR = join(HERE, "..", ".tmp")
mkdirSync(LOCK_DIR, { recursive: true })

const releaseBuildLock = await lockfile.lock(LOCK_DIR, {
  lockfilePath: join(LOCK_DIR, "bridge-build.lock"),
  retries: {
    retries: 60,
    factor: 1,
    minTimeout: 250,
    maxTimeout: 250,
  },
  stale: 120000,
})

try {

// Single source of truth: extract the BRIDGE String.raw template from the runner.
const runner = readFileSync(join(HERE, "runner.mjs"), "utf8")
const open = runner.indexOf("const BRIDGE = String.raw`")
const start = runner.indexOf("`", open) + 1
const end = runner.indexOf("\n`", start)
if (open < 0 || end < 0) throw new Error("could not extract BRIDGE template from runner.mjs")
writeFileSync(join(HERE, "bridge.entry.mts"), runner.slice(start, end))

const bundleOut = join(HERE, `bridge.bundle.${process.pid}.tmp.mjs`)
await esbuild.build({
  entryPoints: [join(HERE, "bridge.entry.mts")],
  bundle: true, platform: "node", format: "esm", target: "node22",
  outfile: bundleOut,
  loader: { ".md": "text", ".yaml": "text", ".yml": "text", ".node": "copy" },
  preserveSymlinks: true,
  nodePaths: [join(KIMI, "node_modules")],
  logLevel: "error",
  banner: { js: "import{createRequire as __cr}from'node:module';import{fileURLToPath as __f}from'node:url';import{dirname as __d}from'node:path';const require=__cr(import.meta.url);const __filename=__f(import.meta.url);const __dirname=__d(__filename);" },
})
// Patch kosong's google-genai adapter: it emits Python/REST-style snake_case field
// names (function_declarations, parameters_json_schema, function_call, function_response),
// but the @google/genai JS SDK expects camelCase and silently DROPS unrecognized keys —
// so every tool serialized to an empty {} and Gemini returned MALFORMED_FUNCTION_CALL,
// breaking ALL google models. Rename them to camelCase in the bundled output (the openai/
// anthropic `function_call: { arguments` converters are deliberately left untouched).
{
  const BUNDLE = bundleOut
  let b = readFileSync(BUNDLE, "utf8")
  // Each unique snake_case marker must appear EXACTLY once (the single google converter).
  // Assert the count up front so a future kosong layout change (extra/zero occurrences) fails
  // LOUDLY here instead of shipping a half-patched bundle that silently re-breaks google.
  for (const [find, repl] of [
    ["function_declarations: [", "functionDeclarations: ["],
    ["parameters_json_schema: tool.parameters", "parametersJsonSchema: tool.parameters"],
    ["function_response: {", "functionResponse: {"],
    // The ECHO of Gemini's thoughtSignature on a functionCall part. kosong captures it
    // (extras.thought_signature_b64) and re-emits it as snake_case thought_signature, which
    // the SDK drops → Gemini 3.x THINKING models 400 "missing thought_signature" on multi-turn
    // tool use. (The parser's p2["thought_signature"] read-fallback at _extractChunkParts is a
    // different occurrence and is deliberately NOT touched — it reads google's response.)
    ['functionCallPart["thought_signature"] =', 'functionCallPart["thoughtSignature"] ='],
  ]) {
    const n = b.split(find).length - 1
    if (n !== 1) throw new Error(`google-genai patch: expected exactly 1 of "${find}", found ${n} — kosong layout changed, re-verify`)
    b = b.replace(find, repl)
  }
  // google's tool-CALL part ONLY — the openai/anthropic `function_call: { arguments` converters
  // (two other occurrences) must NOT be touched. Anchor on the unique functionCallPart assignment.
  const fcRe = /(functionCallPart = \{\s*)function_call:/
  if (!fcRe.test(b)) throw new Error("google-genai patch: functionCallPart anchor not found — kosong layout changed, re-verify")
  b = b.replace(fcRe, "$1functionCall:")
  // SMUGGLE Gemini's thoughtSignature through the toolCall ID. Even with the camelCase echo
  // above, agent-core DROPS the toolCall's `extras` field (which carries the signature) when it
  // records the assistant turn to history — verified: the parser stores extras (FLUSH), but the
  // echo reads null (the only toolCall fields that survive the round-trip are type/id/name/
  // arguments). So Gemini 3.x THINKING models still 400 on MULTI-TURN tool use. The ID survives,
  // so encode the signature into it at parse time (~~ts~~ delimiter; matching is unaffected — the
  // id is consistent across call+result and never enters the Gemini functionCall/Response body)
  // and extract it back at echo time. Verified live: gemini-3.1-flash-lite completes a multi-turn
  // Read→continue→verdict review with this.
  for (const [find, repl, label] of [
    [
      `            type: "function",\n            id: toolCallId,\n            name,`,
      `            type: "function",\n            id: thoughtSigB64 ? toolCallId + "~~ts~~" + thoughtSigB64 : toolCallId,\n            name,`,
      "parser id-smuggle",
    ],
    [
      `      functionCallPart["thoughtSignature"] = toolCall.extras["thought_signature_b64"];\n    }\n    parts.push(functionCallPart);`,
      `      functionCallPart["thoughtSignature"] = toolCall.extras["thought_signature_b64"];\n    }\n    if (functionCallPart["thoughtSignature"] === void 0) { const _ts = String(toolCall.id || ""); const _i = _ts.indexOf("~~ts~~"); if (_i >= 0) functionCallPart["thoughtSignature"] = _ts.slice(_i + 6); }\n    parts.push(functionCallPart);`,
      "echo id-extract",
    ],
  ]) {
    const n = b.split(find).length - 1
    if (n !== 1) throw new Error(`google-genai thoughtSignature ${label}: expected exactly 1, found ${n} — kosong layout changed, re-verify`)
    b = b.replace(find, repl)
  }
  // Post-conditions: no google snake marker survives (the 2 openai/anthropic function_call stay).
  for (const m of ["function_declarations:", "parameters_json_schema:", "function_response:"]) {
    if (b.includes(m)) throw new Error(`google-genai patch incomplete: "${m}" still present after patching`)
  }
  writeFileSync(BUNDLE, b)
  renameSync(BUNDLE, join(HERE, "bridge.bundle.mjs"))
  console.error("patched kosong google-genai adapter: snake_case → camelCase (5 fields, validated)")
}
console.error("bridge.bundle.mjs rebuilt from runner BRIDGE template")
} finally {
  await releaseBuildLock()
}
