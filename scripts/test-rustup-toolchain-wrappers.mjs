import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { access, chmod, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import test from "node:test";

const root = resolve(process.env.DOTFILES_CONTRACT_ROOT ?? ".");
const wrapper = join(root, "home/modules/rustup-toolchain-wrapper.sh");

const makeProxy = async (directory, tool) => {
  const proxy = join(directory, tool);
  await writeFile(
    proxy,
    `#!/usr/bin/env bash\nprintf '%s\\n' "${tool}:\${RUSTUP_TOOLCHAIN:-unset}"\n`,
  );
  await chmod(proxy, 0o755);
  return proxy;
};

test("managed host Rust wrappers override a stale inherited Rustup toolchain", async (t) => {
  const temp = await mkdtemp(join(tmpdir(), "rustup-toolchain-wrapper-"));
  t.after(() => rm(temp, { recursive: true, force: true }));

  const cargoHome = join(temp, "cargo");
  await (await import("node:fs/promises")).mkdir(join(cargoHome, "bin"), { recursive: true });
  for (const tool of ["cargo", "rustc", "rustfmt"]) {
    await makeProxy(join(cargoHome, "bin"), tool);
    const result = spawnSync("bash", [wrapper, tool], {
      encoding: "utf8",
      env: {
        ...process.env,
        CARGO_HOME: cargoHome,
        RUSTUP_TOOLCHAIN: "1.98.1",
      },
    });
    assert.equal(result.status, 0, result.stderr);
    assert.equal(result.stdout, `${tool}:1.95.0\n`);
  }
});

test("wrapper fails clearly when its Rustup proxy is unavailable", async (t) => {
  const temp = await mkdtemp(join(tmpdir(), "rustup-toolchain-wrapper-missing-"));
  t.after(() => rm(temp, { recursive: true, force: true }));

  const result = spawnSync("bash", [wrapper, "cargo"], {
    encoding: "utf8",
    env: { ...process.env, CARGO_HOME: temp, RUSTUP_TOOLCHAIN: "1.98.1" },
  });
  assert.equal(result.status, 127);
  assert.match(result.stderr, /Rustup proxy missing/);
});

test("Home Manager owns devbox-scoped cargo, rustc, and rustfmt entrypoints", async () => {
  const home = await readFile(join(root, "home/home.nix"), "utf8");
  assert.match(home, /\.\/modules\/rustup-toolchain-wrappers\.nix/);
  const module = await readFile(join(root, "home/modules/rustup-toolchain-wrappers.nix"), "utf8");
  assert.match(module, /lib\.toLower hostname == "cc-se-sto-devbox-01"/);
  for (const tool of ["cargo", "rustc", "rustfmt"]) {
    assert.match(module, new RegExp(`"\\.local/bin/${tool}"`));
  }
  assert.match(module, /force\s*=\s*true/);
  await access(wrapper);
});
