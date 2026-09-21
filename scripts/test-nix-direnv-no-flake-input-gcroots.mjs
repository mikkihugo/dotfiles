import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { join, resolve } from "node:path";
import test from "node:test";

const root = resolve(process.env.DOTFILES_CONTRACT_ROOT ?? ".");
const read = (path) => readFile(join(root, path), "utf8");

test("nix-direnv overlay does not GC-root flake archive inputs", async () => {
  const patch = await read(
    "home/patches/nix-direnv-3.2.0-no-flake-input-gcroots.patch",
  );
  const shell = await read("home/modules/shell.nix");

  assert.match(
    shell,
    /nix-direnv-3\.2\.0-no-flake-input-gcroots\.patch/,
    "shell.nix must apply the no-flake-input-gcroots patch",
  );
  assert.match(patch, /Skip flake-input GC roots/);
  assert.match(patch, /-\s*_nix_add_gcroot "\$\{store_path\}" "\$\{flake_inputs\}\/\$\{store_path##\*\/\}"/);
  assert.doesNotMatch(
    patch,
    /^\+_nix_add_gcroot "\$\{store_path\}"/m,
    "patch must not re-add per-input gcroots",
  );
});

test("agent direnv cache rejects exports with deleted Nix store paths", async () => {
  const exporter = await read("shell/bash/direnv-export.sh");

  assert.match(
    exporter,
    /_direnv_store_paths_exist\(\)/,
    "the cached export needs a store-path validity predicate",
  );
  assert.match(
    exporter,
    /_direnv_store_paths_exist "\$_direnv_file" \|\| \{[\s\S]*rm -f -- "\$_direnv_file"/,
    "a missing cached store path must evict the dump before it is sourced",
  );
});
