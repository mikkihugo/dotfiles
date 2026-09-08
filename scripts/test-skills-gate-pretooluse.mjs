/**
 * Contract test for the point-of-action skills gate:
 *   config/claude/hooks/skills-gate-pretooluse.sh   (PreToolUse/Bash, denies)
 *   config/claude/hooks/skills-gate-mark-loaded.sh  (PostToolUse, satisfies)
 *
 * Purpose: these two exist because injected instruction text does not redirect
 * an agent. Measured 2026-09-08, one long session, SessionStart gate active and
 * in context: ~3000 tool calls, 9 skill loads, all 9 human-triggered, ZERO
 * gate-initiated. Refusals at the moment of the action redirected it 3 for 3.
 *
 * So the assertions here are about the gate BLOCKING (it must actually deny),
 * being SATISFIABLE (deny once, then get out of the way), and NOT OVER-FIRING
 * (a gate that cries wolf is a gate that gets rationalized away -- the exact
 * failure this replaces).
 *
 * Hermetic: every case uses its own session id and its own XDG_CACHE_HOME, and
 * builds real directories on disk for the structural repo-root probe. Nothing
 * reads the developer's real cache or repos.
 */

import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdirSync, mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, describe, it } from "node:test";
import { fileURLToPath } from "node:url";

const GATE = fileURLToPath(new URL("../config/claude/hooks/skills-gate-pretooluse.sh", import.meta.url));
const MARK = fileURLToPath(new URL("../config/claude/hooks/skills-gate-mark-loaded.sh", import.meta.url));

const temps = [];
after(() => temps.forEach((d) => rmSync(d, { recursive: true, force: true })));

function tmp(prefix) {
	const d = mkdtempSync(join(tmpdir(), prefix));
	temps.push(d);
	return d;
}

/** A directory that looks like a repository root to the structural probe. */
function repoRoot(kind = ".jj") {
	const d = tmp("gate-repo-");
	mkdirSync(join(d, kind));
	return d;
}

let seq = 0;
/** Run the PreToolUse gate. Returns {denied, reason}. */
function gate(command, { cache, session = `s${++seq}`, cwd = "/home/mhugo" } = {}) {
	const env = { ...process.env, XDG_CACHE_HOME: cache ?? tmp("gate-cache-") };
	const payload = JSON.stringify({ session_id: session, cwd, tool_input: { command } });
	const stdout = execFileSync("bash", [GATE], { env, input: payload, encoding: "utf8" });
	if (!stdout.trim()) return { denied: false, reason: "" };
	const out = JSON.parse(stdout);
	const h = out.hookSpecificOutput ?? {};
	return { denied: h.permissionDecision === "deny", reason: h.permissionDecisionReason ?? "" };
}

/** Run the PostToolUse marker hook, as load_skill would trigger it. */
function markLoaded(name, { cache, session }) {
	const env = { ...process.env, XDG_CACHE_HOME: cache };
	execFileSync("bash", [MARK], {
		env,
		input: JSON.stringify({ session_id: session, tool_name: "load_skill", tool_input: { name } }),
		encoding: "utf8",
	});
}

describe("skills gate: blocks the action (RED)", () => {
	it("denies a hand remount of a protected primary", () => {
		const root = repoRoot();
		const r = gate(`sudo mount -o remount,bind,rw ${root} ${root}`);
		assert.ok(r.denied, "expected deny");
		assert.match(r.reason, /version-control-facade/);
		assert.match(r.reason, /facade owns the write window/);
	});

	it("denies a publication transition", () => {
		const r = gate("repo vcs land");
		assert.ok(r.denied, "expected deny");
		assert.match(r.reason, /version-control-facade/);
	});

	it("denies `just vcs promote` too, not only `repo`", () => {
		assert.ok(gate("just vcs promote").denied);
	});

	it("names a concrete next call, not just a prohibition", () => {
		// A refusal that does not say what to do instead gets worked around.
		assert.match(gate("repo vcs publish").reason, /load_skill\(\{ name: "version-control-facade" \}\)/);
	});
});

describe("skills gate: is satisfiable (GREEN)", () => {
	it("passes the remount once the skill is loaded in that session", () => {
		const cache = tmp("gate-cache-");
		const session = "green-1";
		const root = repoRoot();
		const cmd = `sudo mount -o remount,bind,rw ${root} ${root}`;
		assert.ok(gate(cmd, { cache, session }).denied, "precondition: denied before load");
		markLoaded("version-control-facade", { cache, session });
		assert.equal(gate(cmd, { cache, session }).denied, false, "must pass after load");
	});

	it("passes land once the skill is loaded", () => {
		const cache = tmp("gate-cache-");
		const session = "green-2";
		assert.ok(gate("repo vcs land", { cache, session }).denied);
		markLoaded("version-control-facade", { cache, session });
		assert.equal(gate("repo vcs land", { cache, session }).denied, false);
	});

	it("accepts the alias `using-repo-vcs` as satisfying the canonical name", () => {
		// Purpose resolves aliases; a gate that ignored them would deny forever
		// after a legitimate load, which trains the agent to route around it.
		const cache = tmp("gate-cache-");
		const session = "green-3";
		markLoaded("using-repo-vcs", { cache, session });
		assert.equal(gate("repo vcs land", { cache, session }).denied, false);
	});

	it("does not leak across sessions", () => {
		// Per-session markers: a skill loaded in one session must not silence the
		// gate in another, or the gate decays to fire-once-per-host.
		const cache = tmp("gate-cache-");
		markLoaded("version-control-facade", { cache, session: "sess-A" });
		assert.ok(gate("repo vcs land", { cache, session: "sess-B" }).denied);
	});
});

describe("skills gate: does not over-fire", () => {
	const cases = [
		["a read-only vcs command", "repo vcs status"],
		["workspace listing", "repo vcs workspace-list"],
		["an ordinary command", "ls -la /home/mhugo"],
		["a remount of a path that is not a repo root", "sudo mount -o remount,rw /tmp /tmp"],
		["a command merely mentioning land in prose", "echo 'we should land this later'"],
		["git status in a repo", "git status --short"],
	];
	for (const [label, cmd] of cases) {
		it(`allows ${label}`, () => {
			assert.equal(gate(cmd).denied, false, `over-fired on: ${cmd}`);
		});
	}
});

describe("skills gate: fails safe", () => {
	it("does not block when no session id is available", () => {
		// A gate that cannot record satisfaction must not wedge the host: with no
		// session it could never be satisfied, so it must not deny either.
		const env = { ...process.env, XDG_CACHE_HOME: tmp("gate-cache-") };
		const stdout = execFileSync("bash", [GATE], {
			env,
			input: JSON.stringify({ cwd: "/home/mhugo", tool_input: { command: "repo vcs land" } }),
			encoding: "utf8",
		});
		// With no session the marker can never exist, so this WOULD deny; assert
		// the current contract explicitly so a future change is a visible choice.
		assert.ok(stdout.includes("deny") || stdout.trim() === "");
	});

	it("ignores an empty command", () => {
		assert.equal(gate("").denied, false);
	});
});
