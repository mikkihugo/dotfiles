import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import {
  access,
  chmod,
  mkdir,
  mkdtemp,
  readFile,
  rm,
  writeFile,
} from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import test from "node:test";

const contractRoot = resolve(process.env.DOTFILES_CONTRACT_ROOT ?? ".");
const source = async (path) => readFile(join(contractRoot, path), "utf8");
const wrapperLogic = join(contractRoot, "home/modules/cargo-pgrx-wrapper.sh");

const createEngineRoot = async (root) => {
  const flakeDir = join(root, "fabrics/data");
  await mkdir(join(flakeDir, "nix/flake"), { recursive: true });
  await Promise.all([
    writeFile(join(root, "Cargo.toml"), "[workspace]\n"),
    writeFile(join(flakeDir, "Cargo.toml"), "[workspace]\n"),
    writeFile(join(flakeDir, "flake.nix"), "{}\n"),
    writeFile(join(flakeDir, "nix/flake/packages.nix"), "{}\n"),
  ]);
  return flakeDir;
};

const createFakeNix = async (root) => {
  const path = join(root, "fake-nix");
  await writeFile(
    path,
    `#!/usr/bin/env bash
set -euo pipefail
{
  printf '%s\\0' "$PWD"
  printf '%s\\0' "\${CARGO_PGRX_NIX_WRAPPER_ACTIVE:-}"
  printf '%s\\0' "$@"
} > "$CARGO_PGRX_TEST_LOG"
`,
  );
  await chmod(path, 0o755);
  return path;
};

const runWrapper = ({ cwd, fakeNix, fallbackRoot, log, args = [], env = {} }) =>
  spawnSync("bash", [wrapperLogic, fakeNix, fallbackRoot, ...args], {
    cwd,
    encoding: "utf8",
    env: { ...process.env, CARGO_PGRX_TEST_LOG: log, ...env },
  });

const readInvocation = async (path) => {
  const fields = (await readFile(path)).toString().split("\0");
  assert.equal(fields.pop(), "");
  return fields;
};

test("Home Manager owns the devbox-scoped exact wrapper logic", async () => {
  const home = await source("home/home.nix");
  assert.match(home, /\.\/modules\/cargo-pgrx\.nix/);

  const module = await source("home/modules/cargo-pgrx.nix");
  assert.match(module, /lib\.toLower hostname == "cc-se-sto-devbox-01"/);
  assert.match(module, /home\.file\."\.local\/bin\/cargo-pgrx"/);
  assert.match(module, /cargo-pgrx-wrapper\.sh/);
  assert.match(module, /executable\s*=\s*true/);
  assert.match(module, /force\s*=\s*true/);
  assert.doesNotMatch(module, /\.cargo\/bin\/cargo-pgrx/);
});

test("wrapper selects the nearest marked Engine root and preserves argv", async (t) => {
  const root = await mkdtemp(join(tmpdir(), "cargo-pgrx-nearest-"));
  t.after(() => rm(root, { recursive: true, force: true }));

  const engineRoot = join(root, "engine");
  const flakeDir = await createEngineRoot(engineRoot);
  const cwd = join(engineRoot, "work/nested");
  await mkdir(cwd, { recursive: true });
  const fakeNix = await createFakeNix(root);
  const log = join(root, "nix-invocation");
  const forwarded = ["pgrx", "test", "--features", "one two", "--", "exact name"];

  const result = runWrapper({
    cwd,
    fakeNix,
    fallbackRoot: join(root, "missing-fallback"),
    log,
    args: forwarded,
  });
  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual(await readInvocation(log), [
    flakeDir,
    "1",
    "develop",
    `path:${flakeDir}`,
    "--command",
    "cargo-pgrx",
    ...forwarded,
  ]);
});

test("wrapper rejects an unrelated ancestor flake and uses marked fallback", async (t) => {
  const root = await mkdtemp(join(tmpdir(), "cargo-pgrx-fallback-"));
  t.after(() => rm(root, { recursive: true, force: true }));

  const unrelatedRoot = join(root, "unrelated");
  const unrelatedFlake = join(unrelatedRoot, "fabrics/data");
  await mkdir(join(unrelatedFlake, "nested"), { recursive: true });
  await writeFile(join(unrelatedFlake, "flake.nix"), "{}\n");

  const fallbackRoot = join(root, "engine");
  const fallbackFlake = await createEngineRoot(fallbackRoot);
  const fakeNix = await createFakeNix(root);
  const log = join(root, "nix-invocation");

  const result = runWrapper({
    cwd: join(unrelatedFlake, "nested"),
    fakeNix,
    fallbackRoot,
    log,
    args: ["pgrx", "--help"],
  });
  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual(await readInvocation(log), [
    fallbackFlake,
    "1",
    "develop",
    `path:${fallbackFlake}`,
    "--command",
    "cargo-pgrx",
    "pgrx",
    "--help",
  ]);
});

test("wrapper recursion fails closed before invoking Nix", async (t) => {
  const root = await mkdtemp(join(tmpdir(), "cargo-pgrx-recursion-"));
  t.after(() => rm(root, { recursive: true, force: true }));

  const engineRoot = join(root, "engine");
  await createEngineRoot(engineRoot);
  const cwd = join(engineRoot, "nested");
  await mkdir(cwd, { recursive: true });
  const fakeNix = await createFakeNix(root);
  const log = join(root, "must-not-exist");

  const result = runWrapper({
    cwd,
    fakeNix,
    fallbackRoot: engineRoot,
    log,
    args: ["pgrx", "--help"],
    env: { CARGO_PGRX_NIX_WRAPPER_ACTIVE: "1" },
  });
  assert.equal(result.status, 126);
  assert.match(result.stderr, /resolved the wrapper recursively/);
  await assert.rejects(access(log));
});

test("the canonical repository check runs the cargo-pgrx wrapper contract", async () => {
  const check = await source("scripts/repo-check.sh");
  assert.match(check, /scripts\/test-cargo-pgrx-wrapper\.mjs/);
});
