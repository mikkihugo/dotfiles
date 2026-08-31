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
