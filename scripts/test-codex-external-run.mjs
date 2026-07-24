import assert from "node:assert/strict";
import { spawn, spawnSync } from "node:child_process";
import { constants as fsConstants } from "node:fs";
import {
  access,
  chmod,
  mkdir,
  mkdtemp,
  readFile,
  readdir,
  realpath,
  stat,
  utimes,
  writeFile,
} from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";

const LAUNCHER = "config/codex/bin/codex-external-run.mjs";
const SECRET_PROMPT = "SECRET-PROMPT-CONTENT-never-persisted";

const modeOf = async (path) => (await stat(path)).mode & 0o777;

const makeHarness = async () => {
  const root = await mkdtemp(join(tmpdir(), "codex-external-run-test-"));
  const state = join(root, "xdg-state");
  const bin = join(root, "bin");
  const workspace = await realpath(await mkdir(join(root, "workspace"), { recursive: true }).then(() => join(root, "workspace")));
  await mkdir(bin, { recursive: true });
  const fakeChild = `#!/bin/sh
capture="\${FAKE_CHILD_CAPTURE:-}"
if [ -n "$capture" ]; then
  {
    echo "ROOT_TASK_ID=$CODEX_EXTERNAL_RUN_ROOT_TASK_ID"
    echo "PARENT_TASK_ID=$CODEX_EXTERNAL_RUN_PARENT_TASK_ID"
    echo "TASK_ID=$CODEX_EXTERNAL_RUN_TASK_ID"
    echo "RUN_ID=$CODEX_EXTERNAL_RUN_RUN_ID"
    echo "COORDINATOR=$CODEX_EXTERNAL_RUN_COORDINATOR"
    echo "AGENT_BUDGET=$CODEX_EXTERNAL_RUN_AGENT_BUDGET"
    echo "WORKSPACE=$CODEX_EXTERNAL_RUN_WORKSPACE"
    echo "RECORD_PATH=$CODEX_EXTERNAL_RUN_RECORD_PATH"
  } > "$capture"
fi
if [ -n "\${FAKE_CHILD_GRANDCHILD:-}" ]; then
  sleep 60 &
  echo $! > "$FAKE_CHILD_GRANDCHILD"
fi
if [ -n "\${FAKE_CHILD_SIGNAL:-}" ]; then
  kill -s "$FAKE_CHILD_SIGNAL" $$
fi
sleep "\${FAKE_CHILD_SLEEP:-0}"
exit "\${FAKE_CHILD_EXIT:-0}"
`;
  for (const name of ["kimi", "cursor-agent"]) {
    await writeFile(join(bin, name), fakeChild);
    await chmod(join(bin, name), 0o755);
  }
  return { root, state, bin, workspace };
};

const runLauncher = (harness, args, extraEnv = {}) =>
  new Promise((resolveRun) => {
    const child = spawn(process.execPath, [LAUNCHER, ...args], {
      env: {
        ...process.env,
        XDG_STATE_HOME: harness.state,
        PATH: `${harness.bin}:${process.env.PATH}`,
        ...extraEnv,
      },
      stdio: ["ignore", "pipe", "pipe"],
    });
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (chunk) => (stdout += chunk));
    child.stderr.on("data", (chunk) => (stderr += chunk));
    child.on("exit", (code, signal) => resolveRun({ code, signal, stdout, stderr }));
  });

const baseArgs = (harness, overrides = {}) => {
  const args = [
    "--harness", "kimi",
    "--root-task-id", "root-1",
    "--parent-task-id", "root-1",
    "--task-id", "task-1",
    "--coordinator", "codex-root",
    "--workspace", harness.workspace,
    "--model", "kimi-code/k3",
    "--agent-budget", "2",
    "--",
    "kimi", "--model", "kimi-code/k3", "--output-format", "stream-json", "--prompt", SECRET_PROMPT,
  ];
  for (const [flag, value] of Object.entries(overrides)) {
    const index = args.indexOf(flag);
    if (index === -1) throw new Error(`unknown override flag ${flag}`);
    args[index + 1] = value;
  }
  return args;
};

const recordsDir = (harness) => join(harness.state, "codex", "external-runs");

const listRecords = async (harness) => {
  try {
    return (await readdir(recordsDir(harness))).filter((name) => name.endsWith(".json"));
  } catch {
    return [];
  }
};

const readOnlyRecord = async (harness) => {
  const names = await listRecords(harness);
  assert.equal(names.length, 1, `expected exactly one run record, got ${names.join(",")}`);
  const raw = await readFile(join(recordsDir(harness), names[0]), "utf8");
  return { name: names[0], raw, record: JSON.parse(raw) };
};

const livePid = () => {
  const child = spawn("sleep", ["30"], { stdio: "ignore" });
  return child;
};

const deadPid = async () => {
  const child = spawn("sleep", ["30"], { stdio: "ignore" });
  child.kill("SIGKILL");
  await new Promise((resolveDone) => child.on("exit", resolveDone));
  return child.pid;
};

const seedRecord = async (harness, record) => {
  await mkdir(recordsDir(harness), { recursive: true, mode: 0o700 });
  await writeFile(
    join(recordsDir(harness), `${record.run_id}.json`),
    JSON.stringify(record),
    { mode: 0o600 },
  );
};

const seededActiveRecord = (overrides = {}) => ({
  schema_version: "external-run-record/v1",
  run_id: `seeded-${Math.random().toString(16).slice(2)}`,
  root_task_id: "root-seed",
  parent_task_id: "root-seed",
  task_id: "task-seed",
  coordinator: "codex-root",
  harness: "kimi",
  model: "kimi-code/k3",
  workspace: "/some/other/workspace",
  agent_budget: 10,
  launcher_pid: 1,
  child_pid: 1,
  started_at: new Date().toISOString(),
  ended_at: null,
  status: "running",
  exit_code: null,
  signal: null,
  ...overrides,
});

test("requires explicit root/parent/task identity; no anonymous default", async () => {
  const harness = await makeHarness();
  for (const missing of ["--root-task-id", "--parent-task-id", "--task-id"]) {
    const args = baseArgs(harness).filter((value, index, all) => {
      const flagIndex = all.indexOf(missing);
      return index !== flagIndex && index !== flagIndex + 1;
    });
    const result = await runLauncher(harness, args);
    assert.notEqual(result.code, 0, `launch without ${missing} must fail`);
    assert.match(result.stderr, new RegExp(missing.replaceAll("-", "-")), "stderr names the missing flag");
  }
  assert.deepEqual(await listRecords(harness), [], "no record may be written on identity failure");
});

test("rejects Kimi agent budget above the per-coordinator ceiling of 10", async () => {
  const harness = await makeHarness();
  for (const bad of ["11", "0", "-1", "two"]) {
    const result = await runLauncher(harness, baseArgs(harness, { "--agent-budget": bad }));
    assert.notEqual(result.code, 0, `budget ${bad} must be rejected`);
    assert.match(result.stderr, /budget/i);
  }
  assert.deepEqual(await listRecords(harness), [], "no record may be written on budget failure");
});

test("writes crash-recoverable record with required provenance and no prompt/argv leakage", async () => {
  const harness = await makeHarness();
  const capture = join(harness.root, "capture.env");
  const result = await runLauncher(harness, baseArgs(harness), { FAKE_CHILD_CAPTURE: capture });
  assert.equal(result.code, 0, `happy path must exit 0: ${result.stderr}`);

  const { name, raw, record } = await readOnlyRecord(harness);
  assert.equal(record.schema_version, "external-run-record/v1");
  assert.equal(record.root_task_id, "root-1");
  assert.equal(record.parent_task_id, "root-1", "top-level child may set parent equal to root");
  assert.equal(record.task_id, "task-1");
  assert.match(record.run_id, /^run-[0-9T:-]+-[0-9a-f]{16}$/);
  assert.equal(name, `${record.run_id}.json`);
  assert.equal(record.coordinator, "codex-root");
  assert.equal(record.harness, "kimi");
  assert.equal(record.model, "kimi-code/k3");
  assert.equal(record.workspace, harness.workspace, "workspace is stored absolute");
  assert.ok(record.workspace.startsWith("/"), "workspace must be absolute");
  assert.equal(record.agent_budget, 2);
  assert.ok(Number.isInteger(record.launcher_pid) && record.launcher_pid > 0);
  assert.ok(Number.isInteger(record.child_pid) && record.child_pid > 0);
  assert.match(record.started_at, /^\d{4}-\d{2}-\d{2}T/);
  assert.match(record.ended_at, /^\d{4}-\d{2}-\d{2}T/);
  assert.equal(record.status, "completed");
  assert.equal(record.exit_code, 0);
  assert.equal(record.signal, null);

  assert.ok(!raw.includes(SECRET_PROMPT), "record must never persist prompt content");
  assert.ok(!raw.includes("stream-json"), "record must never persist command arguments");

  const captured = await readFile(capture, "utf8");
  assert.match(captured, /ROOT_TASK_ID=root-1/);
  assert.match(captured, /PARENT_TASK_ID=root-1/);
  assert.match(captured, /TASK_ID=task-1/);
  assert.match(captured, new RegExp(`RUN_ID=${record.run_id}`));
  assert.match(captured, /COORDINATOR=codex-root/);
  assert.match(captured, /AGENT_BUDGET=2/);
  assert.match(captured, new RegExp(`WORKSPACE=${harness.workspace.replaceAll("/", "\\/")}`));

  assert.equal(await modeOf(join(harness.state, "codex")), 0o700, "state dir mode 0700");
  assert.equal(await modeOf(recordsDir(harness)), 0o700, "external-runs dir mode 0700");
  assert.equal(await modeOf(join(recordsDir(harness), name)), 0o600, "record mode 0600");
});

test("falls back to ~/.local/state/codex when XDG_STATE_HOME is unset", async () => {
  const harness = await makeHarness();
  const fakeHome = join(harness.root, "home");
  await mkdir(fakeHome, { recursive: true });
  const env = { ...process.env, HOME: fakeHome, PATH: `${harness.bin}:${process.env.PATH}` };
  delete env.XDG_STATE_HOME;
  const result = await new Promise((resolveRun) => {
    const child = spawn(process.execPath, [LAUNCHER, ...baseArgs(harness)], {
      env,
      stdio: ["ignore", "pipe", "pipe"],
    });
    let stderr = "";
    child.stderr.on("data", (chunk) => (stderr += chunk));
    child.on("exit", (code) => resolveRun({ code, stderr }));
  });
  assert.equal(result.code, 0, `fallback launch must succeed: ${result.stderr}`);
  const fallbackDir = join(fakeHome, ".local", "state", "codex", "external-runs");
  const names = await readdir(fallbackDir);
  assert.equal(names.filter((name) => name.endsWith(".json")).length, 1);
});

test("records child exit code and failed status; launcher forwards exit code", async () => {
  const harness = await makeHarness();
  const result = await runLauncher(harness, baseArgs(harness), { FAKE_CHILD_EXIT: "3" });
  assert.equal(result.code, 3, "launcher forwards the child exit code");
  const { record } = await readOnlyRecord(harness);
  assert.equal(record.status, "failed");
  assert.equal(record.exit_code, 3);
  assert.equal(record.signal, null);
  assert.match(record.ended_at, /^\d{4}-\d{2}-\d{2}T/);
});

test("records signal termination and maps launcher exit to 128+signo", async () => {
  const harness = await makeHarness();
  const result = await runLauncher(harness, baseArgs(harness), { FAKE_CHILD_SIGNAL: "TERM" });
  assert.equal(result.code, 143, "launcher exit is 128+SIGTERM");
  const { record } = await readOnlyRecord(harness);
  assert.equal(record.status, "signaled");
  assert.equal(record.signal, "SIGTERM");
  assert.equal(record.exit_code, null);
});

test("forwards SIGTERM to the child and records signal termination", async () => {
  const harness = await makeHarness();
  const launch = runLauncher(harness, baseArgs(harness), { FAKE_CHILD_SLEEP: "60" });
  let record = null;
  for (let attempt = 0; attempt < 100 && !record?.child_pid; attempt += 1) {
    await new Promise((resolveWait) => setTimeout(resolveWait, 50));
    const names = await listRecords(harness);
    if (names.length === 1) {
      record = JSON.parse(await readFile(join(recordsDir(harness), names[0]), "utf8"));
    }
  }
  assert.ok(record?.child_pid > 0, "run record with child pid must exist before signalling");
  const launcherPid = record.launcher_pid;
  process.kill(launcherPid, "SIGTERM");
  const result = await launch;
  assert.equal(result.code, 143, "launcher exit is 128+SIGTERM after forwarding");
  const { record: final } = await readOnlyRecord(harness);
  assert.equal(final.status, "signaled", "termination is recorded, not left running");
  assert.equal(final.signal, "SIGTERM");
  assert.match(final.ended_at, /^\d{4}-\d{2}-\d{2}T/);
  assert.throws(() => process.kill(record.child_pid, 0), /ESRCH/, "child must not be orphaned");
});

test("rejects a duplicate run id instead of overwriting an existing record", async () => {
  const harness = await makeHarness();
  const args = [...baseArgs(harness).slice(0, baseArgs(harness).indexOf("--")), "--run-id", "fixed-run-1", ...baseArgs(harness).slice(baseArgs(harness).indexOf("--"))];
  const first = await runLauncher(harness, args);
  assert.equal(first.code, 0, `first launch must succeed: ${first.stderr}`);
  const second = await runLauncher(harness, args);
  assert.notEqual(second.code, 0, "duplicate run id must be rejected");
  assert.match(second.stderr, /already exists|duplicate/i);
  assert.deepEqual(await listRecords(harness), ["fixed-run-1.json"]);
});

test("preserves nested root/parent ancestry (parent is the immediate lead task)", async () => {
  const harness = await makeHarness();
  const result = await runLauncher(
    harness,
    baseArgs(harness, { "--root-task-id": "root-9", "--parent-task-id": "task-8", "--task-id": "task-9" }),
  );
  assert.equal(result.code, 0, `nested launch must succeed: ${result.stderr}`);
  const { record } = await readOnlyRecord(harness);
  assert.equal(record.root_task_id, "root-9", "nested runs inherit the root");
  assert.equal(record.parent_task_id, "task-8", "nested runs name their immediate parent task");
  assert.equal(record.task_id, "task-9");
});

test("rejects Kimi prompt mode combined with --auto or --yolo", async () => {
  const harness = await makeHarness();
  for (const forbidden of ["--auto", "--yolo"]) {
    const result = await runLauncher(harness, [
      ...baseArgs(harness).slice(0, baseArgs(harness).indexOf("--") + 1),
      "kimi", "--prompt", "x", forbidden,
    ]);
    assert.notEqual(result.code, 0, `--prompt with ${forbidden} must be rejected`);
    assert.match(result.stderr, new RegExp(forbidden));
  }
  assert.deepEqual(await listRecords(harness), [], "no record may be written on flag-policy failure");
});

test("reconciles stale dead-pid records before summing reserved Kimi budget", async () => {
  const harness = await makeHarness();
  const dead = await deadPid();
  const liveA = livePid();
  const liveB = livePid();
  try {
    await seedRecord(harness, seededActiveRecord({ run_id: "seeded-dead", child_pid: dead, agent_budget: 10, coordinator: "codex-seed-dead" }));
    await seedRecord(harness, seededActiveRecord({ run_id: "seeded-live-a", child_pid: liveA.pid, agent_budget: 10, coordinator: "codex-seed-a" }));
    await seedRecord(harness, seededActiveRecord({ run_id: "seeded-live-b", child_pid: liveB.pid, agent_budget: 10, coordinator: "codex-seed-b" }));
    const result = await runLauncher(harness, baseArgs(harness, { "--agent-budget": "10" }));
    assert.equal(result.code, 0, `20 live + 10 new must fit under 30 after stale reconciliation: ${result.stderr}`);
    const stale = JSON.parse(await readFile(join(recordsDir(harness), "seeded-dead.json"), "utf8"));
    assert.equal(stale.status, "stale", "dead-pid record is marked stale");
  } finally {
    liveA.kill("SIGKILL");
    liveB.kill("SIGKILL");
  }
});

test("rejects a launch that would exceed the global 30 Kimi agent ceiling", async () => {
  const harness = await makeHarness();
  const lives = [livePid(), livePid(), livePid()];
  try {
    for (const [index, live] of lives.entries()) {
      await seedRecord(harness, seededActiveRecord({ run_id: `seeded-live-${index}`, child_pid: live.pid, agent_budget: 10, coordinator: `codex-seed-${index}` }));
    }
    const result = await runLauncher(harness, baseArgs(harness, { "--agent-budget": "1" }));
    assert.notEqual(result.code, 0, "30 active + 1 must be rejected");
    assert.match(result.stderr, /30|global/i);
  } finally {
    for (const live of lives) live.kill("SIGKILL");
  }
});

test("enforces one writer per workspace lane", async () => {
  const harness = await makeHarness();
  const live = livePid();
  try {
    await seedRecord(harness, seededActiveRecord({ run_id: "seeded-owner", child_pid: live.pid, workspace: harness.workspace }));
    const result = await runLauncher(harness, baseArgs(harness));
    assert.notEqual(result.code, 0, "second writer on the same workspace must be rejected");
    assert.match(result.stderr, /workspace/i);
  } finally {
    live.kill("SIGKILL");
  }
});

test("serializes concurrent reservations without exceeding the global ceiling", async () => {
  const harness = await makeHarness();
  const launches = [];
  for (let index = 0; index < 4; index += 1) {
    const laneWorkspace = join(harness.root, `workspace-${index}`);
    await mkdir(laneWorkspace, { recursive: true });
    launches.push(
      runLauncher(
        harness,
        baseArgs(harness, {
          "--agent-budget": "8",
          "--task-id": `task-${index}`,
          "--coordinator": `codex-lane-${index}`,
          "--workspace": laneWorkspace,
        }),
        { FAKE_CHILD_SLEEP: "1.5" },
      ),
    );
  }
  const results = await Promise.all(launches);
  const succeeded = results.filter((result) => result.code === 0);
  const rejected = results.filter((result) => result.code !== 0);
  assert.equal(succeeded.length, 3, "3x8=24 fits under 30; the 4th concurrent reservation must fail closed");
  assert.equal(rejected.length, 1);
  assert.match(rejected[0].stderr, /30|global/i);
});

test("rejects when one coordinator's aggregated active Kimi reservations would exceed 10", async () => {
  const harness = await makeHarness();
  const liveA = livePid();
  const liveB = livePid();
  try {
    await seedRecord(harness, seededActiveRecord({ run_id: "seeded-coord-a", child_pid: liveA.pid, agent_budget: 6 }));
    await seedRecord(harness, seededActiveRecord({ run_id: "seeded-coord-b", child_pid: liveB.pid, agent_budget: 4, workspace: "/another/workspace" }));
    const result = await runLauncher(harness, baseArgs(harness, { "--agent-budget": "1" }));
    assert.notEqual(result.code, 0, "6+4 active for codex-root + 1 new must be rejected");
    assert.match(result.stderr, /coordinator/i);
    assert.match(result.stderr, /10/);
  } finally {
    liveA.kill("SIGKILL");
    liveB.kill("SIGKILL");
  }
});

test("other coordinators' reservations do not count toward the per-coordinator ceiling", async () => {
  const harness = await makeHarness();
  const live = livePid();
  try {
    await seedRecord(harness, seededActiveRecord({ run_id: "seeded-other-coord", child_pid: live.pid, agent_budget: 10, coordinator: "codex-other" }));
    const result = await runLauncher(harness, baseArgs(harness, { "--agent-budget": "10" }));
    assert.equal(result.code, 0, `codex-root has no active reservations; 10 for another coordinator must not block: ${result.stderr}`);
  } finally {
    live.kill("SIGKILL");
  }
});

test("fails closed on an unparsable run record instead of ignoring it", async () => {
  const harness = await makeHarness();
  await mkdir(recordsDir(harness), { recursive: true, mode: 0o700 });
  await writeFile(join(recordsDir(harness), "broken.json"), "{not valid json", { mode: 0o600 });
  const result = await runLauncher(harness, baseArgs(harness));
  assert.notEqual(result.code, 0, "a corrupt record must fail the launch closed");
  assert.match(result.stderr, /corrupt|unparsable|fail/i);
  assert.deepEqual(await listRecords(harness), ["broken.json"], "no new record may be written when corruption is detected");
});

test("fails closed on a schema-invalid active record instead of treating missing budget as zero", async () => {
  const harness = await makeHarness();
  const live = livePid();
  try {
    await seedRecord(harness, seededActiveRecord({ run_id: "seeded-no-budget", child_pid: live.pid, agent_budget: null }));
    const result = await runLauncher(harness, baseArgs(harness));
    assert.notEqual(result.code, 0, "an active Kimi record without a valid budget must fail the launch closed");
    assert.match(result.stderr, /schema|invalid|budget|fail/i);
    assert.deepEqual(await listRecords(harness), ["seeded-no-budget.json"], "no new record may be written on schema-invalid input");
  } finally {
    live.kill("SIGKILL");
  }
});

test("signals the worker process group so grandchildren do not survive launcher termination", async (t) => {
  if (process.platform !== "linux") {
    t.skip("process-group signalling is Linux-scoped");
    return;
  }
  const harness = await makeHarness();
  const grandchildPidFile = join(harness.root, "grandchild.pid");
  const launch = runLauncher(harness, baseArgs(harness), {
    FAKE_CHILD_SLEEP: "60",
    FAKE_CHILD_GRANDCHILD: grandchildPidFile,
  });
  let record = null;
  let grandchildPid = null;
  for (let attempt = 0; attempt < 100 && !(record?.child_pid && grandchildPid); attempt += 1) {
    await new Promise((resolveWait) => setTimeout(resolveWait, 50));
    const names = await listRecords(harness);
    if (names.length === 1) {
      record = JSON.parse(await readFile(join(recordsDir(harness), names[0]), "utf8"));
    }
    try {
      grandchildPid = Number.parseInt((await readFile(grandchildPidFile, "utf8")).trim(), 10);
    } catch {
      // grandchild pid file not written yet
    }
  }
  assert.ok(record?.child_pid > 0, "run record with child pid must exist before signalling");
  assert.ok(grandchildPid > 0, "fake child must have spawned its grandchild");
  process.kill(record.launcher_pid, "SIGTERM");
  const result = await launch;
  assert.equal(result.code, 143, "launcher exit is 128+SIGTERM after forwarding");
  assert.throws(() => process.kill(record.child_pid, 0), /ESRCH/, "child must not be orphaned");
  let grandchildAlive = true;
  for (let attempt = 0; attempt < 100 && grandchildAlive; attempt += 1) {
    try {
      process.kill(grandchildPid, 0);
    } catch {
      grandchildAlive = false;
    }
    if (grandchildAlive) await new Promise((resolveWait) => setTimeout(resolveWait, 50));
  }
  assert.equal(grandchildAlive, false, "grandchild in the worker process group must not survive the forwarded signal");
});

test("cursor harness launches without Kimi budget accounting", async () => {
  const harness = await makeHarness();
  const args = [
    "--harness", "cursor",
    "--root-task-id", "root-2",
    "--parent-task-id", "root-2",
    "--task-id", "task-2",
    "--coordinator", "codex-root",
    "--workspace", harness.workspace,
    "--model", "cursor-grok-4.5-high",
    "--",
    "cursor-agent", "--print", "--force", "--sandbox", "enabled", "--output-format", "stream-json", "--model", "cursor-grok-4.5-high", SECRET_PROMPT,
  ];
  const result = await runLauncher(harness, args);
  assert.equal(result.code, 0, `cursor launch must succeed: ${result.stderr}`);
  const { raw, record } = await readOnlyRecord(harness);
  assert.equal(record.harness, "cursor");
  assert.equal(record.agent_budget, null, "cursor runs do not reserve a Kimi agent budget");
  assert.ok(!raw.includes(SECRET_PROMPT), "record must never persist prompt content");
});

// Seeds a reserve.lock dir directly: optionally with an owner.json, optionally
// backdated so it is older than the bounded contention window.
const seedLock = async (harness, { owner = undefined, ageMs = 0 } = {}) => {
  const lockPath = join(recordsDir(harness), "reserve.lock");
  await mkdir(lockPath, { recursive: true });
  if (owner !== undefined) {
    await writeFile(join(lockPath, "owner.json"), owner === null ? "{not valid json" : JSON.stringify(owner), { mode: 0o600 });
  }
  if (ageMs > 0) {
    const when = new Date(Date.now() - ageMs);
    await utimes(lockPath, when, when);
  }
  return lockPath;
};

// Small test-only retry budget so fail-closed paths take ~250ms, not 10s.
const FAST_LOCK_ENV = { CODEX_EXTERNAL_RUN_LOCK_MAX_ATTEMPTS: "5" };

test("recovers a reservation lock whose recorded owner PID is dead", async () => {
  const harness = await makeHarness();
  const dead = await deadPid();
  const lockPath = await seedLock(harness, {
    owner: { pid: dead, token: "dead-owner-token", acquired_at: new Date().toISOString() },
  });
  const result = await runLauncher(harness, baseArgs(harness), FAST_LOCK_ENV);
  assert.equal(result.code, 0, `dead-owner lock must be recovered without waiting out the budget: ${result.stderr}`);
  await assert.rejects(access(lockPath), "recovered lock is released after the launch");
  const { record } = await readOnlyRecord(harness);
  assert.equal(record.status, "completed");
});

test("recovers a legacy ownerless lock once it is older than the contention window", async () => {
  const harness = await makeHarness();
  const lockPath = await seedLock(harness, { ageMs: 60000 });
  const result = await runLauncher(harness, baseArgs(harness), FAST_LOCK_ENV);
  assert.equal(result.code, 0, `legacy lock older than the window must be recovered: ${result.stderr}`);
  await assert.rejects(access(lockPath), "recovered legacy lock is released after the launch");
});

test("recovers a corrupt owner lock once it is older than the contention window", async () => {
  const harness = await makeHarness();
  await seedLock(harness, { owner: null, ageMs: 60000 });
  const result = await runLauncher(harness, baseArgs(harness), FAST_LOCK_ENV);
  assert.equal(result.code, 0, `corrupt-owner lock older than the window must be recovered: ${result.stderr}`);
});

test("fails closed on a fresh ownerless lock inside the contention window without stealing it", async () => {
  const harness = await makeHarness();
  const lockPath = await seedLock(harness);
  // The stale-classification window is the fixed compiled 10s, so a fresh
  // lock is never old enough to reclaim; FAST_LOCK_ENV only shortens the
  // acquisition wait (~250ms) before failing closed.
  const result = await runLauncher(harness, baseArgs(harness), FAST_LOCK_ENV);
  assert.equal(result.code, 2, "fresh ownerless lock must fail closed, not be stolen");
  assert.match(result.stderr, /lock/i);
  await access(lockPath);
});

test("retry-budget overrides never shorten the stale classification window", async () => {
  const harness = await makeHarness();
  const lockPath = await seedLock(harness);
  // A zero retry delay would collapse an override-derived window to 0ms,
  // making even a fresh lock instantly "stale" and stealable. The window is
  // fixed at the compiled 10s default, so this must still fail closed fast
  // (5 attempts, 0ms sleeps) and leave the lock untouched.
  const result = await runLauncher(harness, baseArgs(harness), {
    CODEX_EXTERNAL_RUN_LOCK_MAX_ATTEMPTS: "5",
    CODEX_EXTERNAL_RUN_LOCK_RETRY_DELAY_MS: "0",
  });
  assert.equal(result.code, 2, "zero-delay override must not make a fresh lock reclaimable");
  assert.match(result.stderr, /lock/i);
  await access(lockPath);
});

test("never steals a lock whose recorded owner PID is alive", async () => {
  const harness = await makeHarness();
  const live = livePid();
  try {
    const lockPath = await seedLock(harness, {
      owner: { pid: live.pid, token: "live-owner-token", acquired_at: new Date().toISOString() },
    });
    const result = await runLauncher(harness, baseArgs(harness), FAST_LOCK_ENV);
    assert.equal(result.code, 2, "live-owner lock must fail closed after the bounded budget");
    assert.match(result.stderr, /lock/i);
    const owner = JSON.parse(await readFile(join(lockPath, "owner.json"), "utf8"));
    assert.equal(owner.token, "live-owner-token", "live owner's lock is left untouched");
  } finally {
    live.kill("SIGKILL");
  }
});
