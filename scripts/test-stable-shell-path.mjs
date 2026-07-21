#!/usr/bin/env node

import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
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
