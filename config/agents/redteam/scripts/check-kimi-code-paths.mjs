#!/usr/bin/env node
import { execFileSync } from "node:child_process"

let out = ""
try {
  out = execFileSync("rg", [
    "-n",
    "--pcre2",
    String.raw`(^|[^-\w])\.kimi(/|\\)|/\.kimi(/|\\)|/home/[^ "'\n]*/\.kimi(/|\\)`,
    ".",
    "--glob",
    "!node_modules",
    "--glob",
    "!package-lock.json",
    "--glob",
    "!scripts/bridge.bundle.mjs",
  ], { encoding: "utf8" }).trim()
} catch (err) {
  if (err?.status !== 1) throw err
}

if (out) {
  process.stderr.write("Legacy .kimi path references are forbidden; use .kimi-code only.\n")
  process.stderr.write(out + "\n")
  process.exit(1)
}
