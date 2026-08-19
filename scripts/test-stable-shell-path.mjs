#!/usr/bin/env node

import assert from "node:assert/strict";
import { mkdtemp, mkdir, readdir, readFile, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawnSync } from "node:child_process";
import test from "node:test";

test("stable shell preserves the caller PATH ahead of Home Manager defaults", async () => {
  const source = await readFile("home/modules/stable-shell.nix", "utf8");

  assert.equal(
    source.match(/_stable_shell_seen/g)?.length,
    15,
    "all three generated wrapper forms must deduplicate caller and Home Manager PATH entries",
  );
  assert.doesNotMatch(source, /export PATH="\$HOME\/\.local\/bin:\$PATH"/);
  assert.doesNotMatch(source, /export PATH="\$_stable_shell_caller_path:\$PATH"/);
});

test("SHELL points directly at an immutable store wrapper", async () => {
  const source = await readFile("home/modules/stable-shell.nix", "utf8");

  assert.match(source, /storeBash = pkgs\.writeTextFile/);
  assert.match(source, /sessionVariables\.SHELL = storeBash/);
  assert.match(source, /SHELL=\$\{storeBash\}/);
  assert.doesNotMatch(source, /sessionVariables\.SHELL = stableBash/);
});

test("stable-shell sources the shared direnv-export loader", async () => {
  const source = await readFile("home/modules/stable-shell.nix", "utf8");
  assert.match(source, /shell\/bash\/direnv-export\.sh/);
  assert.match(source, /IN_NIX_SHELL/);
  assert.match(source, /name = "agent-shell"/);
  assert.doesNotMatch(source, /cursor-agent-shell/);
});

test("ordinary non-interactive shells enter direnv once with a bounded wait", async () => {
  const runtime = await readFile("shell/bash/bashrc", "utf8");
  const loader = await readFile("shell/bash/direnv-export.sh", "utf8");
  const homeModule = await readFile("home/modules/shell.nix", "utf8");
  const bashEnv = await readFile("shell/bash/noninteractive-path.sh", "utf8");

  assert.match(runtime, /shell\/bash\/direnv-export\.sh/);
  assert.match(homeModule, /envExtra/);
  assert.match(homeModule, /shell\/bash\/direnv-export\.sh/);
  assert.match(bashEnv, /shell\/bash\/direnv-export\.sh/);
  assert.match(loader, /direnv allow \./);
  assert.match(loader, /timeout 15s direnv export bash/);
  assert.match(loader, /flock -w 90/);
  assert.match(loader, /agent-direnv/);
  assert.doesNotMatch(loader, /timeout 90s direnv export/);
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
    `#!/bin/sh\nprintf '%s\\n' "$*" >> "$DIRENV_TEST_LOG"\nif [ "$1" = export ]; then printf 'export DIRENV_TEST_LOADED=1\\n'; fi\n`,
    { mode: 0o755 },
  );

  const xdgRuntime = join(base, "runtime");
  await mkdir(xdgRuntime);
  const env = {
    ...process.env,
    PATH: `${bin}:${process.env.PATH}`,
    DIRENV_TEST_LOG: log,
    DIRENV_DIR: `-${repoA}`,
    IN_NIX_SHELL: "impure",
    XDG_RUNTIME_DIR: xdgRuntime,
  };
  delete env.BASH_ENV;
  delete env.ENV;
  delete env.AGENT_DIRENV_EXPORT_TRIED;

  const run = (cwd) =>
    spawnSync("bash", ["-c", '. "$1"; printf "%s" "${DIRENV_TEST_LOADED:-0}"', "bash", join(process.cwd(), "shell/bash/direnv-export.sh")], {
      cwd,
      encoding: "utf8",
      env,
    });

  const sameRepo = run(repoA);
  assert.equal(sameRepo.status, 0);
  assert.equal(sameRepo.stdout, "0", "same-repo nested shell must reuse its environment");

  const otherRepo = run(repoB);
  assert.equal(otherRepo.status, 0);
  assert.equal(otherRepo.stdout, "1", "cross-repo shell must load the new environment");
  assert.equal(await readFile(log, "utf8"), "allow .\nexport bash\n");
});

test("BASH_ENV path hook enters direnv once for Claude/Codex bash -c", async () => {
  const base = await mkdtemp(join(tmpdir(), "direnv-bash-env-"));
  const repo = join(base, "repo");
  const bin = join(base, "bin");
  const log = join(base, "direnv.log");
  await Promise.all([mkdir(repo), mkdir(bin)]);
  await writeFile(
    join(bin, "direnv"),
    `#!/bin/sh\nprintf '%s\\n' "$*" >> "$DIRENV_TEST_LOG"\nif [ "$1" = export ]; then printf 'export IN_NIX_SHELL=impure\\nexport DIRENV_DIR=-${repo}\\n'; fi\n`,
    { mode: 0o755 },
  );

  const runtime = join(base, "runtime");
  await mkdir(runtime);
  const env = {
    ...process.env,
    HOME: process.env.HOME,
    PATH: `${bin}:${process.env.PATH}`,
    DIRENV_TEST_LOG: log,
    BASH_ENV: join(process.cwd(), "shell/bash/noninteractive-path.sh"),
    XDG_RUNTIME_DIR: runtime,
  };
  delete env.IN_NIX_SHELL;
  delete env.DIRENV_DIR;
  delete env.AGENT_DIRENV_EXPORT_TRIED;

  const first = spawnSync("bash", ["-c", 'printf "%s" "${IN_NIX_SHELL:-}"'], {
    cwd: repo,
    encoding: "utf8",
    env,
  });
  assert.equal(first.status, 0);
  assert.equal(first.stdout, "impure");

  const nested = spawnSync("bash", ["-c", 'printf "%s" "${IN_NIX_SHELL:-}"'], {
    cwd: repo,
    encoding: "utf8",
    env: { ...env, IN_NIX_SHELL: "impure", DIRENV_DIR: `-${repo}` },
  });
  assert.equal(nested.status, 0);
  assert.equal(nested.stdout, "impure");
  assert.equal(await readFile(log, "utf8"), "allow .\nexport bash\n");
});

test("dump cache hit evals without direnv allow or export", async () => {
  const base = await mkdtemp(join(tmpdir(), "direnv-dump-cache-"));
  const repo = join(base, "repo");
  const bin = join(base, "bin");
  const runtime = join(base, "runtime");
  const log = join(base, "direnv.log");
  await Promise.all([mkdir(repo), mkdir(bin), mkdir(runtime)]);
  await writeFile(join(repo, ".envrc"), "export DIRENV_TEST_REPO=1\n");
  await writeFile(
    join(bin, "direnv"),
    `#!/bin/sh\nprintf '%s\\n' "$*" >> "$DIRENV_TEST_LOG"\nif [ "$1" = export ]; then printf 'export DIRENV_TEST_LOADED=1\\nexport IN_NIX_SHELL=impure\\n'; fi\n`,
    { mode: 0o755 },
  );

  const env = {
    ...process.env,
    PATH: `${bin}:${process.env.PATH}`,
    DIRENV_TEST_LOG: log,
    XDG_RUNTIME_DIR: runtime,
  };
  delete env.BASH_ENV;
  delete env.ENV;
  delete env.IN_NIX_SHELL;
  delete env.DIRENV_DIR;
  delete env.NIX_DIRENV_DID_FALLBACK;
  delete env.AGENT_DIRENV_EXPORT_TRIED;

  const loader = join(process.cwd(), "shell/bash/direnv-export.sh");
  const run = () =>
    spawnSync("bash", ["-c", '. "$1"; printf "%s" "${DIRENV_TEST_LOADED:-0}"', "bash", loader], {
      cwd: repo,
      encoding: "utf8",
      env,
    });

  const miss = run();
  assert.equal(miss.status, 0, miss.stderr);
  assert.equal(miss.stdout, "1");
  assert.equal(await readFile(log, "utf8"), "allow .\nexport bash\n");

  const cacheDir = join(runtime, "agent-direnv");
  const cached = (await readdir(cacheDir)).filter((name) => name.endsWith(".bash"));
  assert.equal(cached.length, 1, "miss must write one dump cache file");

  const hit = run();
  assert.equal(hit.status, 0, hit.stderr);
  assert.equal(hit.stdout, "1");
  assert.equal(
    await readFile(log, "utf8"),
    "allow .\nexport bash\n",
    "hit must not run direnv allow or export",
  );
});

test("nested export-tried sentinel does not start direnv", async () => {
  const base = await mkdtemp(join(tmpdir(), "direnv-tried-sentinel-"));
  const repo = join(base, "repo");
  const bin = join(base, "bin");
  const runtime = join(base, "runtime");
  const log = join(base, "direnv.log");
  await Promise.all([mkdir(repo), mkdir(bin), mkdir(runtime)]);
  await writeFile(
    join(bin, "direnv"),
    `#!/bin/sh\nprintf '%s\\n' "$*" >> "$DIRENV_TEST_LOG"\n`,
    { mode: 0o755 },
  );

  const env = {
    ...process.env,
    PATH: `${bin}:${process.env.PATH}`,
    DIRENV_TEST_LOG: log,
    XDG_RUNTIME_DIR: runtime,
    AGENT_DIRENV_EXPORT_TRIED: "1",
  };
  delete env.BASH_ENV;
  delete env.ENV;
  delete env.IN_NIX_SHELL;
  delete env.DIRENV_DIR;

  const nested = spawnSync(
    "bash",
    ["-c", '. "$1"; printf ok', "bash", join(process.cwd(), "shell/bash/direnv-export.sh")],
    { cwd: repo, encoding: "utf8", env },
  );
  assert.equal(nested.status, 0, nested.stderr);
  assert.equal(nested.stdout, "ok");
  assert.equal(await readFile(log, "utf8").catch(() => ""), "", "nested tried must not invoke direnv");
});
