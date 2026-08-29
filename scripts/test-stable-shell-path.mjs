#!/usr/bin/env node

import assert from "node:assert/strict";
import { mkdtemp, mkdir, readdir, readFile, symlink, writeFile } from "node:fs/promises";
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

test("stable-shell delegates non-interactive direnv loading to BASH_ENV", async () => {
  const source = await readFile("home/modules/stable-shell.nix", "utf8");
  assert.equal(source.match(/export BASH_ENV=/g)?.length, 3);
  assert.doesNotMatch(source, /&& \. "\$HOME\/\.dotfiles\/shell\/bash\/direnv-export\.sh"/);
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
  assert.match(loader, /flock -w 20/);
  assert.match(loader, /_DIRENV_MAX_PARALLEL=10/);
  assert.match(loader, /_direnv_diff_snapshot="\${DIRENV_DIFF:-}"/);
  assert.match(loader, /\${#_direnv_diff_snapshot}" -gt 65536/);
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
  await Promise.all([
    writeFile(join(repoA, ".envrc"), "export REPO=A\n"),
    writeFile(join(repoB, ".envrc"), "export REPO=B\n"),
  ]);
  await writeFile(
    join(bin, "direnv"),
    `#!/bin/sh\nprintf '%s\\n' "$*" >> "$DIRENV_TEST_LOG"\nif [ "$1" = export ]; then printf 'export DIRENV_TEST_LOADED=1\\n'; fi\n`,
    { mode: 0o755 },
  );

  const xdgRuntime = join(base, "runtime");
  await mkdir(xdgRuntime);
  const env = {
    ...process.env,
    PATH: `${bin}:/run/current-system/sw/bin:${process.env.PATH}`,
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

test("Home Manager uses direnv-instant for interactive shells", async () => {
  const shellModule = await readFile("home/modules/shell.nix", "utf8");
  const flake = await readFile("flake.nix", "utf8");
  const plainTerminalPatch = await readFile(
    "patches/direnv-instant-async-without-multiplexer.patch",
    "utf8",
  );
  const bootstrap = await readFile("nix/bootstrap.sh", "utf8");
  const swarmHook = await readFile("config/codex/hooks/swarm-messages.mjs", "utf8");

  assert.match(flake, /direnv-instant\.homeModules\.direnv-instant/);
  assert.match(flake, /inherit sops-nix ace-coder llm-agents direnv-instant inference-fabric/);
  assert.match(shellModule, /direnv-instant = \{/);
  assert.match(shellModule, /package = direnv-instant\.packages\.\$\{pkgs\.stdenv\.hostPlatform\.system\}\.default\.overrideAttrs/);
  assert.match(shellModule, /direnv-instant-async-without-multiplexer\.patch/);
  assert.match(plainTerminalPatch, /If not in a multiplexer, just run direnv synchronously/);
  assert.match(plainTerminalPatch, /^\+\s+if Multiplexer::detect\(\)\.is_none\(\) && shell == Shell::Fish/m);
  assert.match(plainTerminalPatch, /start_is_async_in_non_mux_mode/);
  assert.match(shellModule, /enableFishIntegration = true/);
  assert.match(
    shellModule,
    /nixosOwnsInteractiveDirenv = lib\.toLower hostname == "cc-se-sto-devbox-01"/,
  );
  assert.match(shellModule, /enableBashIntegration = !nixosOwnsInteractiveDirenv/);
  assert.match(shellModule, /enableZshIntegration = !nixosOwnsInteractiveDirenv/);
  assert.match(bootstrap, /SHELL_CONFIG="\$HOME\/\.bashrc"/);
  assert.match(bootstrap, /direnv-instant hook zsh/);
  assert.match(bootstrap, /direnv-instant hook fish \| source/);
  assert.match(bootstrap, /fish_add_path --prepend "\$HOME\/\.nix-profile\/bin"/);
  assert.match(bootstrap, /fish_add_path --prepend "\$HOME\/\.local\/bin"/);
  assert.match(bootstrap, /if ! grep -q "direnv-instant hook"/);
  assert.doesNotMatch(bootstrap, /grep -Eq "direnv\(-instant\)\? hook"/);
  assert.match(swarmHook, /delete lockHelperEnv\.BASH_ENV/);
});

test("the NixOS devbox is the sole interactive direnv hook authority", {
  skip: process.env.RUN_NIX_EVAL_TESTS !== "1",
}, async () => {
  const homeModule = await readFile("home/modules/shell.nix", "utf8");

  assert.match(
    homeModule,
    /nixosOwnsInteractiveDirenv = lib\.toLower hostname == "cc-se-sto-devbox-01"/,
  );
  assert.match(homeModule, /enableBashIntegration = !nixosOwnsInteractiveDirenv/);
  assert.match(homeModule, /enableZshIntegration = !nixosOwnsInteractiveDirenv/);

  for (const [profile, expected] of [
    ["cc-se-sto-devbox-01", false],
    // direnv-instant disables programs.direnv bash/zsh hooks on every profile
    // so it can own the interactive path. The generic mhugo fallback is not
    // a second hook authority.
    ["mhugo", false],
  ]) {
    for (const integration of ["enableBashIntegration", "enableZshIntegration"]) {
      const evaluated = spawnSync(
        "nix",
        [
          "eval",
          "--json",
          `.#homeConfigurations.${profile}.config.programs.direnv.${integration}`,
        ],
        { encoding: "utf8" },
      );
      assert.equal(evaluated.status, 0, evaluated.stderr);
      assert.equal(JSON.parse(evaluated.stdout), expected, `${profile} ${integration}`);
    }
  }
});

test("Home Manager exports BASH_ENV for login and systemd user sessions", async () => {
  const home = await readFile("home/home.nix", "utf8");
  assert.match(
    home,
    /BASH_ENV = "\$HOME\/\.dotfiles\/shell\/bash\/noninteractive-path\.sh"/,
  );
  assert.match(home, /sessionVariables\s*=\s*localeEnvironment\s*\/\/\s*\{/);
  assert.match(home, /systemd\.user\.sessionVariables\s*=\s*localeEnvironment\s*\/\/\s*\{/);
  assert.doesNotMatch(home, /CURSOR_BASH_ENV|cursor-only/i);
});

test("BASH_ENV path hook enters direnv once for Claude/Codex bash -c", async () => {
  const base = await mkdtemp(join(tmpdir(), "direnv-bash-env-"));
  const repo = join(base, "repo");
  const bin = join(base, "bin");
  const home = join(base, "home");
  const log = join(base, "direnv.log");
  await Promise.all([mkdir(repo), mkdir(bin), mkdir(home)]);
  await writeFile(join(repo, ".envrc"), "export DIRENV_TEST_REPO=1\n");
  await symlink(process.cwd(), join(home, ".dotfiles"));
  await writeFile(
    join(bin, "direnv"),
    `#!/bin/sh\nprintf '%s\\n' "$*" >> "$DIRENV_TEST_LOG"\nif [ "$1" = export ]; then printf 'export IN_NIX_SHELL=impure\\nexport DIRENV_DIR=-${repo}\\n'; fi\n`,
    { mode: 0o755 },
  );

  const runtime = join(base, "runtime");
  await mkdir(runtime);
  const env = {
    ...process.env,
    HOME: home,
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

test("enter-once sentinel is scoped to the repository root", async () => {
  const base = await mkdtemp(join(tmpdir(), "direnv-tried-sentinel-"));
  const repo = join(base, "repo-a");
  const otherRepo = join(base, "repo-b");
  const bin = join(base, "bin");
  const runtime = join(base, "runtime");
  const log = join(base, "direnv.log");
  await Promise.all([mkdir(repo), mkdir(otherRepo), mkdir(bin), mkdir(runtime)]);
  await Promise.all([
    writeFile(join(repo, ".envrc"), "export REPO=A\n"),
    writeFile(join(otherRepo, ".envrc"), "export REPO=B\n"),
  ]);
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
    AGENT_DIRENV_EXPORT_TRIED_ROOT: repo,
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

  const crossRoot = spawnSync(
    "bash",
    ["-c", '. "$1"; printf ok', "bash", join(process.cwd(), "shell/bash/direnv-export.sh")],
    { cwd: otherRepo, encoding: "utf8", env },
  );
  assert.equal(crossRoot.status, 0, crossRoot.stderr);
  assert.match(await readFile(log, "utf8"), /export bash/, "a different repository must load its own environment");
});

test("directories without an envrc skip direnv entirely", async () => {
  const base = await mkdtemp(join(tmpdir(), "direnv-no-envrc-"));
  const bin = join(base, "bin");
  const log = join(base, "direnv.log");
  await mkdir(bin);
  await writeFile(
    join(bin, "direnv"),
    `#!/bin/sh\nprintf '%s\n' "$*" >> "$DIRENV_TEST_LOG"\n`,
    { mode: 0o755 },
  );
  const env = {
    ...process.env,
    PATH: `${bin}:/run/current-system/sw/bin:${process.env.PATH}`,
    DIRENV_TEST_LOG: log,
  };
  for (const key of ["BASH_ENV", "ENV", "IN_NIX_SHELL", "DIRENV_DIR", "AGENT_DIRENV_EXPORT_TRIED", "AGENT_DIRENV_EXPORT_TRIED_ROOT"]) {
    delete env[key];
  }
  const result = spawnSync(
    "bash",
    ["-c", '. "$1"; printf ok', "bash", join(process.cwd(), "shell/bash/direnv-export.sh")],
    { cwd: base, encoding: "utf8", env },
  );
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stdout, "ok");
  assert.equal(await readFile(log, "utf8").catch(() => ""), "");
});

test("dump fill strips one-line DIRENV_DIFF and DIRENV_WATCHES", async () => {
  const base = await mkdtemp(join(tmpdir(), "direnv-dump-strip-"));
  const repo = join(base, "repo");
  const bin = join(base, "bin");
  const runtime = join(base, "runtime");
  const log = join(base, "direnv.log");
  await Promise.all([mkdir(repo), mkdir(bin), mkdir(runtime)]);
  await writeFile(join(repo, ".envrc"), "export KEEP_ME=1\n");
  await writeFile(
    join(bin, "direnv"),
    `#!/bin/sh
printf '%s\\n' "$*" >> "$DIRENV_TEST_LOG"
if [ "$1" = export ]; then
  printf "export KEEP_ME=1;unset SCCACHE_CACHE_SIZE;export DIRENV_DIFF=$'eJzpoison';export DIRENV_WATCHES=$'eJzwatch';export IN_NIX_SHELL=impure;export DIRENV_DIR=-%s;" "$PWD"
fi
`,
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
  delete env.DIRENV_DIFF;
  delete env.DIRENV_WATCHES;
  delete env.NIX_DIRENV_DID_FALLBACK;
  delete env.AGENT_DIRENV_EXPORT_TRIED;

  const loader = join(process.cwd(), "shell/bash/direnv-export.sh");
  const probe =
    '. "$1"; printf "keep=%s diff=%s watch=%s nix=%s" "${KEEP_ME:-}" "${DIRENV_DIFF:-}" "${DIRENV_WATCHES:-}" "${IN_NIX_SHELL:-}"';
  const miss = spawnSync("bash", ["-c", probe, "bash", loader], {
    cwd: repo,
    encoding: "utf8",
    env,
  });
  assert.equal(miss.status, 0, miss.stderr);
  assert.equal(miss.stdout, "keep=1 diff= watch= nix=impure");

  const cacheDir = join(runtime, "agent-direnv");
  const cached = (await readdir(cacheDir)).filter((name) => name.endsWith(".bash"));
  assert.equal(cached.length, 1, "miss must write one dump cache file");
  const dump = await readFile(join(cacheDir, cached[0]), "utf8");
  assert.doesNotMatch(dump, /DIRENV_DIFF=/);
  assert.doesNotMatch(dump, /DIRENV_WATCHES=/);
  assert.match(dump, /KEEP_ME=1/);
  assert.match(dump, /unset SCCACHE_CACHE_SIZE;/);
  assert.match(dump, /^# agent-direnv-(envrc-)?root:/m);

  const hit = spawnSync("bash", ["-c", probe, "bash", loader], {
    cwd: repo,
    encoding: "utf8",
    env,
  });
  assert.equal(hit.status, 0, hit.stderr);
  assert.equal(hit.stdout, "keep=1 diff= watch= nix=impure");
  assert.equal(
    await readFile(log, "utf8"),
    "allow .\nexport bash\n",
    "hit must not run direnv allow or export",
  );
});

test("dump whose recorded root no longer has envrc is not reused", async () => {
  const base = await mkdtemp(join(tmpdir(), "direnv-dead-root-"));
  const repo = join(base, "repo");
  const bin = join(base, "bin");
  const runtime = join(base, "runtime");
  const log = join(base, "direnv.log");
  await Promise.all([mkdir(repo), mkdir(bin), mkdir(runtime)]);
  await writeFile(join(repo, ".envrc"), "export KEEP_ME=1\n");
  await writeFile(
    join(bin, "direnv"),
    `#!/bin/sh
printf '%s\\n' "$*" >> "$DIRENV_TEST_LOG"
if [ "$1" = export ]; then
  printf "export KEEP_ME=1;export IN_NIX_SHELL=impure;export DIRENV_DIR=-%s;" "$PWD"
fi
`,
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
  const first = spawnSync(
    "bash",
    ["-c", '. "$1"; printf "%s" "${KEEP_ME:-}"', "bash", loader],
    { cwd: repo, encoding: "utf8", env },
  );
  assert.equal(first.status, 0, first.stderr);
  assert.equal(first.stdout, "1");

  const cacheDir = join(runtime, "agent-direnv");
  const cached = (await readdir(cacheDir)).filter((name) => name.endsWith(".bash"));
  assert.equal(cached.length, 1);
  const dumpPath = join(cacheDir, cached[0]);
  const dump = await readFile(dumpPath, "utf8");
  const poisoned = dump.replace(
    /^# agent-direnv-(?:envrc-)?root:.*$/m,
    "# agent-direnv-envrc-root:/no/such/direnv-root",
  );
  assert.notEqual(poisoned, dump, "fill must record an envrc root header");
  await writeFile(dumpPath, poisoned);

  const second = spawnSync(
    "bash",
    ["-c", '. "$1"; printf "%s" "${KEEP_ME:-}"', "bash", loader],
    { cwd: repo, encoding: "utf8", env },
  );
  assert.equal(second.status, 0, second.stderr);
  assert.equal(
    await readFile(log, "utf8"),
    "allow .\nexport bash\nallow .\nexport bash\n",
    "dead recorded root must miss and refill",
  );
});

test("dump miss drops leftover flock locks without a matching dump", async () => {
  const base = await mkdtemp(join(tmpdir(), "direnv-orphan-lock-"));
  const repo = join(base, "repo");
  const bin = join(base, "bin");
  const runtime = join(base, "runtime");
  const cacheDir = join(runtime, "agent-direnv");
  const log = join(base, "direnv.log");
  await Promise.all([mkdir(repo), mkdir(bin), mkdir(runtime)]);
  await mkdir(cacheDir);
  await writeFile(join(repo, ".envrc"), "export KEEP_ME=1\n");
  await writeFile(join(cacheDir, "orphan.lock"), "");
  await writeFile(
    join(bin, "direnv"),
    `#!/bin/sh
printf '%s\\n' "$*" >> "$DIRENV_TEST_LOG"
if [ "$1" = export ]; then
  printf "export KEEP_ME=1;export IN_NIX_SHELL=impure;export DIRENV_DIR=-%s;" "$PWD"
fi
`,
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

  const miss = spawnSync(
    "bash",
    ["-c", '. "$1"; printf ok', "bash", join(process.cwd(), "shell/bash/direnv-export.sh")],
    { cwd: repo, encoding: "utf8", env },
  );
  assert.equal(miss.status, 0, miss.stderr);
  assert.equal(miss.stdout, "ok");
  const names = await readdir(cacheDir);
  assert.equal(names.includes("orphan.lock"), false, "orphan flock lock must be removed on miss");
});

test("a dump that froze a truncated PATH cannot strip the caller's tool dirs", async () => {
  // `direnv export` emits an absolute PATH snapshot of whichever shell filled
  // the dump, and the dump cache key has no PATH component -- so a filler that
  // never sourced hm-session-vars.sh used to overwrite healthy shells and make
  // `codex` (~/.npm-global/bin) and `direnv-instant` (~/.nix-profile/bin) stop
  // resolving mid-session. The applied environment may add entries; it must
  // never remove one the caller had.
  const base = await mkdtemp(join(tmpdir(), "direnv-path-restore-"));
  const repo = join(base, "repo");
  const bin = join(base, "bin");
  const caller = join(base, "caller-only");
  const runtime = join(base, "runtime");
  await Promise.all([mkdir(repo), mkdir(bin), mkdir(caller), mkdir(runtime)]);
  await writeFile(join(repo, ".envrc"), "# test\n");

  // Stand-in direnv: its export replaces PATH wholesale and drops `caller`.
  await writeFile(
    join(bin, "direnv"),
    `#!/bin/sh\nif [ "$1" = export ]; then printf "export PATH='%s'\\n" "${bin}:/usr/bin"; fi\n`,
    { mode: 0o755 },
  );

  const env = {
    ...process.env,
    HOME: process.env.HOME,
    PATH: `${caller}:${bin}:${process.env.PATH}`,
    XDG_RUNTIME_DIR: runtime,
  };
  delete env.BASH_ENV;
  delete env.ENV;
  delete env.IN_NIX_SHELL;
  delete env.DIRENV_DIR;
  delete env.AGENT_DIRENV_EXPORT_TRIED;
  delete env.AGENT_DIRENV_EXPORT_TRIED_ROOT;

  const run = spawnSync(
    "bash",
    ["-c", '. "$1"; printf "%s" "$PATH"', "bash", join(process.cwd(), "shell/bash/direnv-export.sh")],
    { cwd: repo, encoding: "utf8", env },
  );
  assert.equal(run.status, 0);
  assert.ok(
    run.stdout.split(":").includes(caller),
    `caller PATH entry was dropped by the applied environment: ${run.stdout}`,
  );
});

test("an interactive direnv-instant apply cannot strip the caller's tool dirs", async () => {
  const guard = join(process.cwd(), "shell/bash/direnv-instant-guard.sh");
  const base = await mkdtemp(join(tmpdir(), "direnv-instant-guard-"));
  const bin = join(base, "bin");
  const caller = join(base, "caller-only");
  const repoBin = join(base, "repo-bin");
  await Promise.all([mkdir(bin), mkdir(caller), mkdir(repoBin)]);

  const envFile = join(base, "env");
  await writeFile(envFile, `export GUARD_TEST_APPLIED=1;export PATH=$'${repoBin}:/usr/bin';\n`);

  const hook = spawnSync("direnv-instant", ["hook", "bash"], { encoding: "utf8" });
  assert.equal(hook.status, 0, "direnv-instant must resolve for this test");
  await writeFile(join(bin, "direnv-instant"),
    '#!/bin/sh\nif [ "$1" = hook ]; then cat "$0.hook"; fi\nexit 0\n', { mode: 0o755 });
  await writeFile(join(bin, "direnv-instant.hook"), hook.stdout);

  const startup = (apply) => [
    'eval "$(direnv-instant hook bash)"',
    `. "${guard}"`,
    'eval "$(direnv-instant hook bash)"',
    `. "${guard}"`,
    '__DIRENV_INSTANT_ENV_FILE="$GUARD_TEST_ENV_FILE"',
    apply,
    'printf "%s\\n" "$PATH"',
    'printf "applied=%s\\n" "${GUARD_TEST_APPLIED:-0}"',
  ].join("\n");

  const run = (apply) => spawnSync("bash", ["--norc", "--noprofile", "-i", "-c", startup(apply)], {
    encoding: "utf8",
    env: { HOME: process.env.HOME, TERM: "dumb",
           PATH: `${bin}:${caller}:${process.env.PATH}`, GUARD_TEST_ENV_FILE: envFile },
  });

  for (const [label, apply] of [
    ["SIGUSR1", "kill -USR1 $$"],
    ["prompt-time", "DIRENV_INSTANT_USE_CACHE=1 _direnv_instant_guard_hook"],
  ]) {
    const out = run(apply).stdout.trim().split("\n");
    assert.equal(out.at(-1), "applied=1", `${label}: the repository environment must still be applied`);
    assert.ok(out.at(-2).split(":").includes(caller),
      `${label} apply dropped a caller PATH entry: ${out.at(-2)}`);
  }
});

test("the interactive and non-interactive PATH restores stay one rule", async () => {
  const guard = await readFile("shell/bash/direnv-instant-guard.sh", "utf8");
  const loader = await readFile("shell/bash/direnv-export.sh", "utf8");
  assert.match(guard, /PATH="\$\{PATH:\+\$PATH:\}\$entry"/);
  assert.match(loader, /PATH="\$\{PATH:\+\$PATH:\}\$_direnv_restore_entry"/);
  assert.doesNotMatch(guard, /__HM_SESS_VARS_SOURCED/);
});

