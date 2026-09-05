import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { access, chmod, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import test from "node:test";

const root = resolve(process.env.DOTFILES_CONTRACT_ROOT ?? ".");
const wrapper = join(root, "home/modules/rustup-toolchain-wrapper.sh");

const makeRustup = async (directory) => {
  const proxy = join(directory, "rustup");
  await writeFile(
    proxy,
    "#!/usr/bin/env bash\nset -euo pipefail\n" +
      "[[ $1 == run ]]\n" +
      "printf '%s:%s:%s\\n' \"$3\" \"${RUSTUP_TOOLCHAIN:-unset}\" \"$2\"\n",
  );
  await chmod(proxy, 0o755);
  return proxy;
};

test("managed host Rust wrappers override a stale inherited Rustup toolchain", async (t) => {
  const temp = await mkdtemp(join(tmpdir(), "rustup-toolchain-wrapper-"));
  t.after(() => rm(temp, { recursive: true, force: true }));

  const rustup = await makeRustup(temp);
  for (const tool of ["cargo", "rustc", "rustfmt"]) {
    const result = spawnSync("bash", [wrapper, tool, rustup], {
      encoding: "utf8",
      env: {
        ...process.env,
        RUSTUP_TOOLCHAIN: "1.98.1",
      },
    });
    assert.equal(result.status, 0, result.stderr);
    assert.equal(result.stdout, `${tool}:1.95.0:1.95.0\n`);
  }
});

test("wrapper preserves Rustup's explicit one-command toolchain selector", async (t) => {
  const temp = await mkdtemp(join(tmpdir(), "rustup-toolchain-wrapper-explicit-"));
  t.after(() => rm(temp, { recursive: true, force: true }));

  const rustup = await makeRustup(temp);
  const result = spawnSync("bash", [wrapper, "cargo", rustup, "+1.96.0", "--version"], {
    encoding: "utf8",
    env: { ...process.env, RUSTUP_TOOLCHAIN: "1.98.1" },
  });
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stdout, "cargo:1.96.0:1.96.0\n");
});

test("wrapper fails clearly when its Rustup proxy is unavailable", async (t) => {
  const temp = await mkdtemp(join(tmpdir(), "rustup-toolchain-wrapper-missing-"));
  t.after(() => rm(temp, { recursive: true, force: true }));

  const result = spawnSync("bash", [wrapper, "cargo", join(temp, "missing-rustup")], {
    encoding: "utf8",
    env: { ...process.env, RUSTUP_TOOLCHAIN: "1.98.1" },
  });
  assert.equal(result.status, 127);
  assert.match(result.stderr, /Rustup executable missing/);
});

test("Home Manager owns devbox-scoped cargo, rustc, and rustfmt entrypoints", async () => {
  const home = await readFile(join(root, "home/home.nix"), "utf8");
  assert.match(home, /\.\/modules\/rustup-toolchain-wrappers\.nix/);
  const module = await readFile(join(root, "home/modules/rustup-toolchain-wrappers.nix"), "utf8");
  assert.match(module, /lib\.toLower hostname == "cc-se-sto-devbox-01"/);
  for (const tool of ["cargo", "rustc", "rustfmt"]) {
    assert.match(module, new RegExp(`"\\.local/bin/${tool}"`));
    assert.match(module, new RegExp(`"\\.cargo/bin/${tool}"`));
  }
  assert.match(module, /force\s*=\s*true/);
  await access(wrapper);
});
