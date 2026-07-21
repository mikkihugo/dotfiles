#!/usr/bin/env node

import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

test("stable shell preserves the caller PATH ahead of Home Manager defaults", async () => {
  const source = await readFile("home/modules/cursor-stable-shell.nix", "utf8");

  assert.equal(
    source.match(/_stable_shell_caller_path/g)?.length,
    9,
    "all three generated wrapper forms must capture, restore, and clear caller PATH",
  );
  assert.doesNotMatch(source, /export PATH="\$HOME\/\.local\/bin:\$PATH"/);
});
