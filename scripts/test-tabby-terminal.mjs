import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const home = await readFile("home/home.nix", "utf8");

test("Home Manager imports the Tabby terminal module without replacing WezTerm", () => {
  assert.match(home, /\.\/modules\/tabby\.nix/);
  assert.match(home, /\.\/modules\/wezterm\.nix/);
});

test("Tabby is installed with the supported xterm-256color environment contract", async () => {
  const module = await readFile("home/modules/tabby.nix", "utf8");
  const config = await readFile("config/tabby/config.yaml", "utf8");

  assert.match(module, /pkgs\.tabby/);
  assert.match(module, /\.config\/tabby\/config\.yaml/);
  assert.match(config, /terminal:\s*\n(?:[^\n]*\n)*?\s+environment:\s*\n(?:[^\n]*\n)*?\s+TERM:\s*xterm-256color/m);
});
