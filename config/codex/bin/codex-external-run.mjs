#!@node@
// codex-external-run — Codex-only external-harness launcher with run provenance.
//
// Purpose: anchor every delegated external worker launch (Kimi CLI or Cursor)
// to a crash-recoverable, machine-readable provenance record and enforce the
// operator's Kimi agent-budget ceilings (at most 10 total agents per Kimi
// coordinator/swarm including the lead; at most 30 Kimi agents globally).
// Consumer: Codex root coordinator sessions following the
// external-harness-orchestration skill. Workers receive ancestry/budget via
// CODEX_EXTERNAL_RUN_* environment variables; the task prompt is passed only
// to the child process and is never persisted.
// Test contract: scripts/test-codex-external-run.mjs proves required record
// fields, no prompt/argv leakage, restrictive modes, budget/per-coordinator/
// global-ceiling and duplicate-run-id rejection, fail-closed handling of
// corrupt or schema-invalid records, stale reconciliation, workspace
// exclusivity, signal forwarding to the child process group (grandchildren
// included), exit/signal recording, concurrent reservation serialization, and
// owner-aware stale reservation-lock recovery.
import { spawn } from "node:child_process";
import { randomBytes } from "node:crypto";
import {
  chmodSync,
  closeSync,
  mkdirSync,
  openSync,
  readFileSync,
  readdirSync,
  realpathSync,
  renameSync,
  rmdirSync,
  statSync,
  unlinkSync,
  writeSync,
} from "node:fs";
import { homedir } from "node:os";
import { basename, join } from "node:path";

const SCHEMA_VERSION = "external-run-record/v1";
// Operator hard ceilings (Mikael, 2026-07-23): at most 10 total Kimi agents
// per Kimi coordinator/swarm including the lead, at most 30 Kimi agents
// globally. Ceilings, not targets — resource/provider/independent-lane limits
// still select a lower live count.
const KIMI_PER_COORDINATOR_CEILING = 10;
const KIMI_GLOBAL_CEILING = 30;
const LOCK_RETRY_DELAY_MS = 50;
const LOCK_MAX_ATTEMPTS = 200; // 10s of lock contention budget, then fail closed.

const fail = (message) => {
  process.stderr.write(`codex-external-run: ${message}\n`);
  process.exit(2);
};

// Test-only/configurable lock retry budget: these overrides shorten only how
// long acquisition waits before failing closed. Without explicit overrides
// the fail-closed defaults above apply unchanged (10s of contention, then
// exit 2). Stale-lock classification does not use them (see lockLegacyStaleMs).
const lockBudgetInt = (name, fallback) => {
  const raw = process.env[name];
  if (raw === undefined) return fallback;
  if (!/^[0-9]+$/.test(raw)) fail(`${name} must be a non-negative integer, got ${raw}`);
  return Number.parseInt(raw, 10);
};
const lockRetryDelayMs = lockBudgetInt("CODEX_EXTERNAL_RUN_LOCK_RETRY_DELAY_MS", LOCK_RETRY_DELAY_MS);
const lockMaxAttempts = lockBudgetInt("CODEX_EXTERNAL_RUN_LOCK_MAX_ATTEMPTS", LOCK_MAX_ATTEMPTS);
// Bounded contention window for stale classification: a legacy/missing/
// corrupt-owner lock younger than this may be a fresh acquirer between mkdir
// and owner write, so it must not be reclaimed yet. Fixed at the compiled
// default contention budget (LOCK_MAX_ATTEMPTS * LOCK_RETRY_DELAY_MS = 10s)
// on purpose: the env overrides above are test-only knobs for how long
// acquisition waits before failing closed, and must never shrink the
// recovery age — otherwise an override could collapse the window to zero and
// make a fresh lock instantly stealable.
const lockLegacyStaleMs = LOCK_MAX_ATTEMPTS * LOCK_RETRY_DELAY_MS;

// A record that cannot be parsed or fails schema validation makes active
// reservation proof impossible; the launcher must fail closed, never skip it.
class CorruptRecordError extends Error {}

// Non-spinning synchronous wait: Atomics.wait blocks the thread without
// burning CPU. Portable across Node 24 platforms, no dependencies. The shared
// slot is never signalled, so every wait simply times out after `ms`.
const lockWaitSlot = new Int32Array(new SharedArrayBuffer(4));
const sleepSync = (ms) => Atomics.wait(lockWaitSlot, 0, 0, ms);

const parseArgs = (argv) => {
  const separator = argv.indexOf("--");
  if (separator === -1) fail("missing `--` before the child command");
  const flags = new Map();
  for (let index = 0; index < separator; index += 2) {
    const flag = argv[index];
    if (!flag.startsWith("--")) fail(`unexpected argument ${flag}`);
    if (index + 1 >= separator) fail(`missing value for ${flag}`);
    flags.set(flag, argv[index + 1]);
  }
  const command = argv.slice(separator + 1);
  if (command.length === 0) fail("missing child command after `--`");
  return { flags, command };
};

const requireFlag = (flags, name) => {
  const value = flags.get(name);
  if (!value) fail(`${name} is required (no silent anonymous default)`);
  return value;
};

const stateDir = () => {
  const base = process.env.XDG_STATE_HOME || join(homedir(), ".local", "state");
  return join(base, "codex", "external-runs");
};

const prepareStateDir = (dir) => {
  mkdirSync(dir, { recursive: true, mode: 0o700 });
  chmodSync(dir, 0o700);
  chmodSync(join(dir, ".."), 0o700);
};

// Advisory mkdir lock: atomic on POSIX, so check-and-reserve cannot lose an
// update to a concurrent launcher. Fails closed when the lock cannot be taken.
// Owner-aware crash recovery: a newly acquired lock records the owner PID plus
// a collision-resistant token in owner.json. Release removes only its own
// lock. A lock whose recorded owner PID is dead is recoverable; a
// legacy/missing/corrupt owner file is recoverable only once the lock is older
// than the fixed 10s bounded contention window (a fresh acquirer's
// owner-write gap is always younger, so it is never reclaimed). A live owner
// is never stolen.
// Recovery moves the lock aside with an atomic rename so exactly one waiter
// wins the reclaim and a lock freshly acquired afterwards is never touched.
const lockOwnerPath = (lockPath) => join(lockPath, "owner.json");

// Missing, unparsable, or wrong-shaped owner files are all "legacy": not
// attributable to any owner, recoverable only through the age window.
const readLockOwner = (lockPath) => {
  let parsed;
  try {
    parsed = JSON.parse(readFileSync(lockOwnerPath(lockPath), "utf8"));
  } catch {
    return null;
  }
  if (
    parsed === null ||
    typeof parsed !== "object" ||
    !Number.isInteger(parsed.pid) ||
    parsed.pid <= 0 ||
    typeof parsed.token !== "string" ||
    parsed.token.length === 0
  ) {
    return null;
  }
  return parsed;
};

// Move the stale lock aside atomically: only the rename winner reclaims, so
// concurrent waiters cannot double-claim, and the trash path is unique to this
// process so cleanup cannot touch anyone else's lock.
const reclaimLockDir = (lockPath) => {
  const trashPath = `${lockPath}.reclaim-${process.pid}-${randomBytes(6).toString("hex")}`;
  try {
    renameSync(lockPath, trashPath);
  } catch (error) {
    return error.code === "ENOENT"; // already reclaimed by another waiter
  }
  for (const name of readdirSync(trashPath)) unlinkSync(join(trashPath, name));
  rmdirSync(trashPath);
  return true;
};

// Returns true when a stale lock was reclaimed (or vanished) and acquisition
// should be retried immediately instead of sleeping.
const tryRecoverStaleLock = (lockPath, legacyStaleMs) => {
  const owner = readLockOwner(lockPath);
  if (owner) {
    if (pidAlive(owner.pid)) return false; // a live owner is never stolen
    // Dead owner: confirm the same lock instance before reclaiming, so a lock
    // reclaimed-and-reacquired between our reads is not stolen either.
    const confirm = readLockOwner(lockPath);
    if (!confirm || confirm.token !== owner.token) return false;
    return reclaimLockDir(lockPath);
  }
  let before;
  try {
    before = statSync(lockPath);
  } catch {
    return true; // already gone; retry acquisition
  }
  if (Date.now() - before.mtimeMs < legacyStaleMs) return false;
  let after;
  try {
    after = statSync(lockPath);
  } catch {
    return true;
  }
  // A re-created or newly-written lock changes the dir timestamps; leave it.
  if (after.mtimeMs !== before.mtimeMs || after.ctimeMs !== before.ctimeMs) return false;
  return reclaimLockDir(lockPath);
};

// Release removes only its own lock: on a token mismatch the lock was
// reclaimed/replaced underneath us and must be left alone.
const releaseLock = (lockPath, owner) => {
  const current = readLockOwner(lockPath);
  if (!current || current.token !== owner.token) return;
  try {
    unlinkSync(lockOwnerPath(lockPath));
    rmdirSync(lockPath);
  } catch {
    // The lock was reclaimed or replaced underneath us; nothing left to do.
  }
};

const acquireLock = (dir) => {
  const lockPath = join(dir, "reserve.lock");
  const owner = {
    pid: process.pid,
    token: randomBytes(16).toString("hex"),
    acquired_at: new Date().toISOString(),
  };
  for (let attempt = 0; attempt < lockMaxAttempts; attempt += 1) {
    try {
      mkdirSync(lockPath);
    } catch (error) {
      if (error.code !== "EEXIST") throw error;
      if (tryRecoverStaleLock(lockPath, lockLegacyStaleMs)) continue;
      sleepSync(lockRetryDelayMs);
      continue;
    }
    // Record ownership immediately after the atomic mkdir. If a concurrent
    // reclaimer moved the dir aside in this tiny window the write fails with
    // ENOENT and acquisition simply retries.
    try {
      const fd = openSync(lockOwnerPath(lockPath), "wx", 0o600);
      try {
        writeSync(fd, JSON.stringify(owner));
      } finally {
        closeSync(fd);
      }
    } catch (error) {
      if (error.code === "ENOENT") continue;
      throw error;
    }
    return () => releaseLock(lockPath, owner);
  }
  fail("could not acquire the reservation lock; failing closed");
};

const pidAlive = (pid) => {
  if (!Number.isInteger(pid) || pid <= 0) return false;
  try {
    process.kill(pid, 0);
    return true;
  } catch (error) {
    return error.code === "EPERM";
  }
};

const RECORD_STATUSES = new Set(["running", "stale", "completed", "failed", "signaled", "launch_failed"]);

// Every record in the state dir is evidence for active reservation proof; a
// record that cannot be proven valid and inactive must fail the launch closed.
const validateRecord = (name, record) => {
  const invalid = (reason) => {
    throw new CorruptRecordError(`run record ${name} is schema-invalid (${reason}); failing closed`);
  };
  if (record === null || typeof record !== "object" || Array.isArray(record)) invalid("not an object");
  if (record.schema_version !== SCHEMA_VERSION) invalid("unknown schema_version");
  if (typeof record.run_id !== "string" || record.run_id.length === 0) invalid("run_id missing");
  if (record.harness !== "kimi" && record.harness !== "cursor") invalid("unknown harness");
  if (typeof record.coordinator !== "string" || record.coordinator.length === 0) invalid("coordinator missing");
  if (!RECORD_STATUSES.has(record.status)) invalid("unknown status");
  if (record.status !== "running") return;
  if (record.child_pid !== null && !Number.isInteger(record.child_pid)) invalid("child_pid not an integer");
  if (record.harness === "kimi" && (!Number.isInteger(record.agent_budget) || record.agent_budget < 1)) {
    invalid("active Kimi record without a positive integer agent_budget");
  }
};

const readRecords = (dir) => {
  const records = [];
  for (const name of readdirSync(dir)) {
    if (!name.endsWith(".json") || name.endsWith(".tmp")) continue;
    let record;
    try {
      record = JSON.parse(readFileSync(join(dir, name), "utf8"));
    } catch (error) {
      throw new CorruptRecordError(
        `run record ${name} is unparsable (${error.message}); failing closed because active reservation proof is impossible`,
      );
    }
    validateRecord(name, record);
    records.push({ name, record });
  }
  return records;
};

const writeRecordAtomic = (path, record) => {
  const tmpPath = `${path}.tmp`;
  const fd = openSync(tmpPath, "w", 0o600);
  try {
    writeSync(fd, `${JSON.stringify(record, null, 2)}\n`);
  } finally {
    closeSync(fd);
  }
  chmodSync(tmpPath, 0o600);
  renameSync(tmpPath, path);
};

const isActive = (record) => record.status === "running";

// Reconcile crash-orphaned records: a "running" record whose child PID is dead
// is marked stale and stops reserving budget. Good enough for this Linux host;
// PID reuse can theoretically misclassify, so coordinators still verify live
// state before fan-out.
const reconcile = (dir) => {
  const active = [];
  for (const entry of readRecords(dir)) {
    if (isActive(entry.record) && !pidAlive(entry.record.child_pid)) {
      entry.record.status = "stale";
      entry.record.reconciled_at = new Date().toISOString();
      writeRecordAtomic(join(dir, entry.name), entry.record);
    }
    if (isActive(entry.record)) active.push(entry);
  }
  return active;
};

const generateRunId = () => {
  const stamp = new Date().toISOString().replace(/[-:TZ.]/g, "");
  return `run-${stamp}-${randomBytes(8).toString("hex")}`;
};

const main = () => {
  const { flags, command } = parseArgs(process.argv.slice(2));

  const harness = requireFlag(flags, "--harness");
  if (!["kimi", "cursor"].includes(harness)) fail(`unknown harness ${harness}`);
  const rootTaskId = requireFlag(flags, "--root-task-id");
  const parentTaskId = requireFlag(flags, "--parent-task-id");
  const taskId = requireFlag(flags, "--task-id");
  const coordinator = requireFlag(flags, "--coordinator");
  const model = requireFlag(flags, "--model");
  const workspaceArg = requireFlag(flags, "--workspace");
  if (!workspaceArg.startsWith("/")) fail("--workspace must be an absolute path");
  const workspace = realpathSync(workspaceArg);

  let agentBudget = null;
  if (harness === "kimi") {
    const raw = requireFlag(flags, "--agent-budget");
    if (!/^[0-9]+$/.test(raw)) fail(`--agent-budget must be a positive integer, got ${raw}`);
    agentBudget = Number.parseInt(raw, 10);
    if (agentBudget < 1) fail("--agent-budget must reserve at least the lead agent");
    if (agentBudget > KIMI_PER_COORDINATOR_CEILING) {
      fail(
        `--agent-budget ${agentBudget} exceeds the hard ceiling of at most ${KIMI_PER_COORDINATOR_CEILING} total Kimi agents per coordinator/swarm including the lead`,
      );
    }
  } else if (flags.has("--agent-budget")) {
    const raw = flags.get("--agent-budget");
    if (!/^[0-9]+$/.test(raw) || Number.parseInt(raw, 10) < 1) {
      fail(`--agent-budget must be a positive integer, got ${raw}`);
    }
    agentBudget = Number.parseInt(raw, 10);
  }

  // Narrow harness command policy: only the commands proven in the
  // external-harness-orchestration skill. Do not invent CLI flags.
  const childBinary = basename(command[0]);
  if (harness === "kimi") {
    if (childBinary !== "kimi") fail("kimi harness must execute the `kimi` binary");
    if (!command.includes("--prompt")) fail("kimi harness requires prompt mode (--prompt)");
    for (const forbidden of ["--auto", "--yolo"]) {
      if (command.includes(forbidden)) {
        fail(`kimi prompt mode must not combine --prompt with ${forbidden}`);
      }
    }
  } else if (childBinary !== "cursor-agent") {
    fail("cursor harness must execute the `cursor-agent` binary");
  }

  const runId = flags.get("--run-id") ?? generateRunId();
  if (!/^[A-Za-z0-9._-]+$/.test(runId)) fail(`invalid --run-id ${runId}`);

  const dir = stateDir();
  prepareStateDir(dir);
  const recordPath = join(dir, `${runId}.json`);

  // Inject declared ancestry/budget for the worker without logging the prompt.
  const childEnv = {
    ...process.env,
    CODEX_EXTERNAL_RUN_ROOT_TASK_ID: rootTaskId,
    CODEX_EXTERNAL_RUN_PARENT_TASK_ID: parentTaskId,
    CODEX_EXTERNAL_RUN_TASK_ID: taskId,
    CODEX_EXTERNAL_RUN_RUN_ID: runId,
    CODEX_EXTERNAL_RUN_COORDINATOR: coordinator,
    CODEX_EXTERNAL_RUN_AGENT_BUDGET: agentBudget === null ? "" : String(agentBudget),
    CODEX_EXTERNAL_RUN_WORKSPACE: workspace,
    CODEX_EXTERNAL_RUN_RECORD_PATH: recordPath,
  };

  const release = acquireLock(dir);
  let record = null;
  let child = null;
  let lockedError = null;
  try {
    const active = reconcile(dir);

    if (active.some((entry) => entry.record.workspace === workspace)) {
      lockedError = `workspace ${workspace} already has an active external run; one writer per workspace lane`;
    } else if (harness === "kimi") {
      const kimiActive = active.filter((entry) => entry.record.harness === "kimi");
      // Aggregate per coordinator: one coordinator's total across multiple
      // runs may never exceed 10, independent of the global ceiling.
      const coordinatorReserved = kimiActive
        .filter((entry) => entry.record.coordinator === coordinator)
        .reduce((sum, entry) => sum + entry.record.agent_budget, 0);
      if (coordinatorReserved + agentBudget > KIMI_PER_COORDINATOR_CEILING) {
        lockedError = `Kimi agent reservation for coordinator ${coordinator} would reach ${coordinatorReserved + agentBudget}, exceeding the hard ceiling of at most ${KIMI_PER_COORDINATOR_CEILING} total Kimi agents per coordinator/swarm including the lead`;
      } else {
        const reserved = kimiActive.reduce((sum, entry) => sum + entry.record.agent_budget, 0);
        if (reserved + agentBudget > KIMI_GLOBAL_CEILING) {
          lockedError = `global Kimi agent reservation would reach ${reserved + agentBudget}, exceeding the hard ceiling of at most ${KIMI_GLOBAL_CEILING} Kimi agents globally`;
        }
      }
    }

    if (!lockedError) {
      record = {
        schema_version: SCHEMA_VERSION,
        run_id: runId,
        root_task_id: rootTaskId,
        parent_task_id: parentTaskId,
        task_id: taskId,
        coordinator,
        harness,
        model,
        workspace,
        agent_budget: agentBudget,
        launcher_pid: process.pid,
        child_pid: null,
        started_at: new Date().toISOString(),
        ended_at: null,
        status: "running",
        exit_code: null,
        signal: null,
      };

      // O_EXCL create: an existing run record is rejected, never overwritten.
      try {
        const fd = openSync(recordPath, "wx", 0o600);
        try {
          writeSync(fd, `${JSON.stringify(record, null, 2)}\n`);
        } finally {
          closeSync(fd);
        }
        chmodSync(recordPath, 0o600);
      } catch (error) {
        if (error.code === "EEXIST") {
          lockedError = `run record ${recordPath} already exists; duplicate run id rejected`;
          record = null;
        } else {
          throw error;
        }
      }
    }

    // The reservation is only complete once the child PID is recorded, so the
    // spawn happens under the same lock: a concurrent reconciler must never
    // see a "running" record whose child PID is still unknown.
    if (record) {
      // On Linux the child becomes a process-group leader so termination
      // signals can reach the whole worker tree, not just the direct child.
      child = spawn(command[0], command.slice(1), {
        env: childEnv,
        stdio: "inherit",
        detached: process.platform === "linux",
      });
      record.child_pid = child.pid;
      writeRecordAtomic(recordPath, record);
    }
  } catch (error) {
    if (error instanceof CorruptRecordError) {
      lockedError = error.message;
    } else {
      throw error;
    }
  } finally {
    release();
  }
  if (lockedError) fail(lockedError);

  // Forward termination signals to the child: without this the child is
  // orphaned when the launcher is killed and the record stays "running" with a
  // live child PID, locking the workspace lane and reserving budget until the
  // child exits on its own. The exit handler below then records the signal and
  // maps the launcher exit to 128+signo. Bounded escalation: a child that
  // ignores the forwarded signal is killed so provenance and budget are not
  // orphaned behind a dead launcher. On Linux the signal goes to the child's
  // whole process group (negative PID) so grandchildren cannot survive.
  const signalChild = (signal) => {
    try {
      if (process.platform === "linux" && child.pid) {
        process.kill(-child.pid, signal);
      } else {
        child.kill(signal);
      }
    } catch {
      // Child (or its group) already gone; the exit handler reports the outcome.
    }
  };
  for (const signal of ["SIGINT", "SIGTERM"]) {
    process.on(signal, () => {
      signalChild(signal);
      setTimeout(() => signalChild("SIGKILL"), 5000).unref();
    });
  }

  child.on("error", (error) => {
    record.ended_at = new Date().toISOString();
    record.status = "launch_failed";
    record.error = error.code ?? "spawn_error";
    writeRecordAtomic(recordPath, record);
    process.stderr.write(`codex-external-run: child spawn failed: ${error.message}\n`);
    process.exit(1);
  });

  child.on("exit", (code, signal) => {
    record.ended_at = new Date().toISOString();
    record.exit_code = code;
    record.signal = signal;
    record.status = signal ? "signaled" : code === 0 ? "completed" : "failed";
    writeRecordAtomic(recordPath, record);
    if (signal) {
      const signo = { SIGTERM: 15, SIGKILL: 9, SIGINT: 2 }[signal] ?? 15;
      process.exit(128 + signo);
    }
    process.exit(code ?? 1);
  });
};

main();
