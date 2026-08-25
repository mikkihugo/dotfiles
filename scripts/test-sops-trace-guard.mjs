#!/usr/bin/env node
//
// A caller's `set -x` must never print secret material from the shell startup
// path. xtrace expands arguments before printing, so an untraced-guard function
// leaks: _load_sops_secrets pipes the WHOLE decrypted api-keys.yaml through
// `echo "$decrypted"` once per lookup, _cc_otel_env_load expands a Bao password
// into a base64 Authorization header, and _direnv_do_enter evals a DIRENV_DIFF
// blob that decodes to the previous environment. A real debugging session leaked
// roughly 20 API keys and 33 private-key blocks this way.
//
// Two halves, because either alone can pass vacuously:
//   1. the three real functions still carry the prologue, immediately after the
//      opening brace, so it cannot drift away or be reordered behind an early
//      return;
//   2. the prologue actually suppresses the leak, in bash AND zsh, proven with a
//      fake marker and a positive control.

import assert from "node:assert/strict";
import { mkdtemp, writeFile } from "node:fs/promises";
import { readFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawnSync } from "node:child_process";
import test from "node:test";

const MARKER = "TRACEGUARD-CANARY-VALUE";

const which = (name) => {
  const r = spawnSync("command", ["-v", name], { encoding: "utf8", shell: true });
  return r.status === 0 ? r.stdout.trim() : null;
};

// Absolute interpreters and a real coreutils PATH. Resolving by PATH order alone
// made an earlier version of this harness pass vacuously: under `env -i` the
// stub shell found no `cat`, the function returned early having exported
// nothing, and a leak count of zero looked like a pass.
const BASH = which("bash");
const ZSH = which("zsh");

const PROLOGUE = [
  '\t[ -n "${BASH_VERSION:-}" ] && local -',
  '\t[ -n "${ZSH_VERSION:-}" ] && setopt localoptions',
  "\tset +x",
].join("\n");

test("the shell startup secret loaders are untraceable", async () => {
  // Anchored at the opening brace: a prologue that drifted below an early return
  // would still be "present" to a plain substring search but would not protect
  // the lines above it.
  for (const [file, opener] of [
    ["shell/bash/bashrc", "_load_sops_secrets() {"],
    ["shell/bash/otel-env.sh", "_cc_otel_env_load() {"],
    ["shell/bash/direnv-export.sh", "_direnv_do_enter() {"],
  ]) {
    const src = await readFile(file, "utf8");
    const at = src.indexOf(`\n${opener}\n`);
    assert.ok(at !== -1, `${file}: ${opener} not found`);
    const body = src.slice(at + opener.length + 2);
    const firstCode = body
      .split("\n")
      .filter((l) => l.trim() !== "" && !l.trim().startsWith("#"))
      .slice(0, 3)
      .join("\n");
    assert.equal(
      firstCode,
      PROLOGUE,
      `${file}: ${opener} must open with the untraceable prologue, before any other command`,
    );
  }

  // zsh's `local -` is `typeset -` with no names: it dumps EVERY parameter with
  // its value. Writing this fix is what proved that -- it leaked live keys. Both
  // files are sourced from programs.zsh.initContent, so the guard is structural.
  const bashrc = await readFile("shell/bash/bashrc", "utf8");
  assert.doesNotMatch(
    bashrc,
    /^\t*local -$/m,
    "an unguarded `local -` dumps every parameter with its value under zsh",
  );
});

test("the untraceable prologue actually suppresses a traced leak", async (t) => {
  const base = await mkdtemp(join(tmpdir(), "sops-trace-guard-"));

  const body = [
    `\tsecret="${MARKER}"`,
    '\tprintf "%s" "$secret" >/dev/null',
    "\tTRACEGUARD_RAN=yes",
    "\texport TRACEGUARD_RAN",
  ].join("\n");

  const script = (guarded) =>
    [
      "loader() {",
      guarded ? PROLOGUE : "",
      body,
      "}",
      "set -x",
      "loader",
      "set +x",
      'printf "ran=%s\\n" "${TRACEGUARD_RAN:-no}"',
      "",
    ]
      .filter((l) => l !== "")
      .join("\n");

  for (const [shellName, shell] of [
    ["bash", BASH],
    ["zsh", ZSH],
  ]) {
    if (!shell) {
      t.diagnostic(`${shellName} not on PATH; skipping its leg`);
      continue;
    }
    for (const guarded of [false, true]) {
      const path = join(base, `${shellName}-${guarded ? "guarded" : "plain"}.sh`);
      await writeFile(path, script(guarded));
      const run = spawnSync(shell, [path], { encoding: "utf8", env: process.env });

      // Positive control: without it, a loader that never ran reports zero leaks
      // and the whole assertion below is vacuous.
      assert.match(
        run.stdout,
        /ran=yes/,
        `${shellName} ${guarded ? "guarded" : "plain"}: the loader body must have run`,
      );

      const leaks = (run.stderr.match(new RegExp(MARKER, "g")) ?? []).length;
      if (guarded) {
        assert.equal(leaks, 0, `${shellName}: guarded loader leaked its value into the trace`);
      } else {
        assert.ok(leaks > 0, `${shellName}: control must leak, otherwise the guarded leg proves nothing`);
      }
    }
  }
});
