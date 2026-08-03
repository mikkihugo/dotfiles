#!/usr/bin/env node

import assert from "node:assert/strict";
import { mkdtemp, mkdir, readFile, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawnSync } from "node:child_process";
import test from "node:test";

test("stable shell preserves the caller PATH ahead of Home Manager defaults", async () => {
  const source = await readFile("home/modules/cursor-stable-shell.nix", "utf8");

  assert.equal(
    source.match(/_stable_shell_seen/g)?.length,
    15,
    "all three generated wrapper forms must deduplicate caller and Home Manager PATH entries",
  );
  assert.doesNotMatch(source, /export PATH="\$HOME\/\.local\/bin:\$PATH"/);
  assert.doesNotMatch(source, /export PATH="\$_stable_shell_caller_path:\$PATH"/);
});

test("SHELL points directly at an immutable store wrapper", async () => {
  const source = await readFile("home/modules/cursor-stable-shell.nix", "utf8");

  assert.match(source, /storeBash = pkgs\.writeTextFile/);
  assert.match(source, /sessionVariables\.SHELL = storeBash/);
  assert.match(source, /SHELL=\$\{storeBash\}/);
  assert.doesNotMatch(source, /sessionVariables\.SHELL = stableBash/);
});

test("ordinary non-interactive shells enter direnv once with a bounded wait", async () => {
  const runtime = await readFile("shell/bash/bashrc", "utf8");
  const loader = await readFile("shell/bash/direnv-export.sh", "utf8");
  const homeModule = await readFile("home/modules/shell.nix", "utf8");

  assert.match(runtime, /shell\/bash\/direnv-export\.sh/);
  assert.match(loader, /timeout 15s direnv export bash/);
  assert.doesNotMatch(loader, /else[\s\S]+direnv export bash/);
  assert.doesNotMatch(
    homeModule,
    /type _load_sops_secrets[^\n]+_load_sops_secrets/,
    "shellInit must not decrypt SOPS a second time after sourcing the runtime bashrc",
  );

  const base = await mkdtemp(join(tmpdir(), "direnv-enter-once-"));
  const repoA = join(base, "repo-a");
  const repoB = join(base, "repo-b");
  const bin = join(base, "bin");
  const log = join(base, "direnv.log");
  await Promise.all([mkdir(repoA), mkdir(repoB), mkdir(bin)]);
  await writeFile(
    join(bin, "direnv"),
    `#!/bin/sh\nprintf 'called\\n' >> "$DIRENV_TEST_LOG"\nprintf 'export DIRENV_TEST_LOADED=1\\n'\n`,
    { mode: 0o755 },
  );

  const run = (cwd) =>
    spawnSync("bash", ["-c", '. "$1"; printf "%s" "${DIRENV_TEST_LOADED:-0}"', "bash", join(process.cwd(), "shell/bash/direnv-export.sh")], {
      cwd,
      encoding: "utf8",
      env: {
        ...process.env,
        PATH: `${bin}:${process.env.PATH}`,
        DIRENV_TEST_LOG: log,
        DIRENV_DIR: `-${repoA}`,
        IN_NIX_SHELL: "impure",
      },
    });

  const sameRepo = run(repoA);
  assert.equal(sameRepo.status, 0);
  assert.equal(sameRepo.stdout, "0", "same-repo nested shell must reuse its environment");

  const otherRepo = run(repoB);
  assert.equal(otherRepo.status, 0);
  assert.equal(otherRepo.stdout, "1", "cross-repo shell must load the new environment");
  assert.equal(await readFile(log, "utf8"), "called\n");
});
