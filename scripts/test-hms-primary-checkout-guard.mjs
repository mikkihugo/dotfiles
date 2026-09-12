import assert from "node:assert/strict";
import { mkdtemp, mkdir, readFile, rm, writeFile, chmod } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawnSync } from "node:child_process";
import test from "node:test";

async function extractHmsBody() {
  const source = await readFile("home/modules/shell.nix", "utf8");
  const match = source.match(/\n\s*hms = ''([\s\S]*?)'';/);
  assert.ok(match, "hms alias not found in home/modules/shell.nix");
  return match[1];
}

async function runHms({ branch, dirty }) {
  const base = await mkdtemp(join(tmpdir(), "hms-guard-test-"));
  const bin = join(base, "bin");
  const home = join(base, "home");
  const nhLog = join(base, "nh.log");
  await mkdir(bin, { recursive: true });
  await mkdir(join(home, ".dotfiles", "scripts"), { recursive: true });

  await writeFile(
    join(bin, "git"),
    `#!/usr/bin/env bash\nif [ "$1" = "-C" ]; then\n  shift 2\n  case "$1" in\n    rev-parse) echo "$TEST_BRANCH" ;;\n    status) [ -n "$TEST_DIRTY" ] && printf '%s\\n' $TEST_DIRTY || true ;;\n  esac\nfi\n`,
  );
  await writeFile(join(bin, "nh"), `#!/usr/bin/env bash\necho "nh called: $*" >> "$NH_LOG"\n`);
  await writeFile(
    join(home, ".dotfiles", "scripts", "current-home-profile"),
    `#!/usr/bin/env bash\necho fakeprofile\n`,
  );
  await Promise.all([
    chmod(join(bin, "git"), 0o755),
    chmod(join(bin, "nh"), 0o755),
    chmod(join(home, ".dotfiles", "scripts", "current-home-profile"), 0o755),
  ]);

  const hmsBody = await extractHmsBody();

  // This host's `bash` is a stable-shell wrapper (~/.local/bin/bash) that
  // recombines caller PATH with a freshly-sourced HM session PATH and
  // unconditionally repoints BASH_ENV at $HOME/.dotfiles/shell/bash/
  // noninteractive-path.sh. A from-scratch minimal env gets a cold-boot
  // default PATH that never contains the stub dir (real git/nh win); the
  // *real* $HOME here would also trigger a real direnv re-entry into the
  // live ~/.dotfiles checkout, also drowning out the stub. Spread
  // process.env (so the wrapper takes its "already initialized" branch)
  // and point HOME at a fixture with no .dotfiles/nix-profile so the stub
  // dir wins. Mirrors scripts/test-stable-shell-path.mjs's "ordinary
  // non-interactive shells enter direnv once" test.
  const env = {
    ...process.env,
    PATH: `${bin}:${process.env.PATH}`,
    HOME: home,
    TEST_BRANCH: branch,
    TEST_DIRTY: dirty,
    NH_LOG: nhLog,
  };
  delete env.BASH_ENV;
  delete env.ENV;
  delete env.DIRENV_DIR;
  delete env.AGENT_DIRENV_EXPORT_TRIED;
  delete env.IN_NIX_SHELL;

  const result = spawnSync("bash", ["-c", hmsBody], { encoding: "utf8", env });

  let nhLogContent = "";
  try {
    nhLogContent = await readFile(nhLog, "utf8");
  } catch {
    nhLogContent = "";
  }

  await rm(base, { recursive: true, force: true });
  return { ...result, nhLogContent };
}

test("hms warns (but still builds) when the primary is not a clean main checkout", async () => {
  const { stderr, nhLogContent } = await runHms({ branch: "lane/kimi-otel-stdin-fix-20260911", dirty: "a b" });
  assert.match(stderr, /WARNING/i, `expected a WARNING, got stderr: ${JSON.stringify(stderr)}`);
  assert.match(stderr, /lane\/kimi-otel-stdin-fix-20260911/);
  assert.match(stderr, /dirty=2/);
  assert.match(nhLogContent, /nh called: home switch/, "nh must still be invoked (warn, not refuse)");
});

test("hms stays silent on a clean main checkout", async () => {
  const { stderr, nhLogContent } = await runHms({ branch: "main", dirty: "" });
  assert.doesNotMatch(stderr, /WARNING/i, `expected no WARNING, got stderr: ${JSON.stringify(stderr)}`);
  assert.match(nhLogContent, /nh called: home switch/, "nh must still be invoked");
});
