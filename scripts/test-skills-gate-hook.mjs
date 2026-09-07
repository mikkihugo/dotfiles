/**
 * Contract test for config/claude/hooks/skills-gate-session-start.sh.
 *
 * Purpose: that hook is the ONLY thing that makes the using-skills router fire.
 * It exists because the previous mechanism — prose in CLAUDE.md asking the
 * agent to load the router — silently did nothing for months (26 of 43 skills
 * at zero uses; the router invoked only on the one day a human asked about it).
 * A hook that silently does nothing would be the same bug wearing a different
 * hat, so every assertion here is about the hook PRODUCING something, or
 * FAILING VISIBLY when it cannot.
 *
 * Hermetic: every case builds a synthetic HOME with its own SKILL.md fixture.
 * Nothing reads the real ~/.claude, so results cannot drift with host state.
 */

import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, describe, it } from "node:test";
import { fileURLToPath } from "node:url";

const HOOK = fileURLToPath(
	new URL("../config/claude/hooks/skills-gate-session-start.sh", import.meta.url),
);

const temps = [];
after(() => temps.forEach((dir) => rmSync(dir, { recursive: true, force: true })));

/** Build a synthetic HOME containing a using-skills SKILL.md with `body`. */
function fakeHome(body) {
	const home = mkdtempSync(join(tmpdir(), "skills-gate-"));
	temps.push(home);
	const dir = join(home, ".claude", "skills", "using-skills");
	mkdirSync(dir, { recursive: true });
	writeFileSync(join(dir, "SKILL.md"), body);
	return home;
}

/** Run the hook with HOME=home and parse its stdout as JSON. */
function run(home) {
	const stdout = execFileSync("bash", [HOOK], {
		env: { ...process.env, HOME: home },
		input: "{}",
		encoding: "utf8",
	});
	return JSON.parse(stdout);
}

const FULL = [
	"# Using Skills",
	"",
	"## Governing Purpose gate",
	"noise that must NOT be injected",
	"",
	"## Rule",
	"1. Identify skills whose description might apply.",
	"2. Load each relevant skill.",
	"",
	"## Doubt Scale",
	"more noise that must NOT be injected",
	"",
	"## Red Flags",
	'- "This is simple."',
	'- "I remember the workflow."',
	"",
	"## Priority",
	"trailing noise",
].join("\n");

describe("skills gate SessionStart hook", () => {
	it("injects the gate as SessionStart additionalContext", () => {
		const out = run(fakeHome(FULL));
		assert.equal(out.hookSpecificOutput?.hookEventName, "SessionStart");
		const ctx = out.hookSpecificOutput?.additionalContext ?? "";
		assert.match(ctx, /## Rule/);
		assert.match(ctx, /## Red Flags/);
		assert.match(ctx, /Identify skills whose description might apply/);
		assert.match(ctx, /I remember the workflow/);
	});

	it("injects ONLY the gate sections, not the whole router", () => {
		// Upstream superpowers cats its entire 63-line router. Ours is 406 lines;
		// injecting all of it would spend ~5-6k tokens per session and rebury the
		// gate. These assertions pin that we extract rather than dump.
		const ctx = run(fakeHome(FULL)).hookSpecificOutput.additionalContext;
		assert.doesNotMatch(ctx, /noise that must NOT be injected/);
		assert.doesNotMatch(ctx, /trailing noise/);
		assert.doesNotMatch(ctx, /## Doubt Scale/);
	});

	it("tells the agent how to reach the full router and the other skills", () => {
		// Injecting a fragment is only safe if the way back to the whole thing is
		// inside the fragment.
		const ctx = run(fakeHome(FULL)).hookSpecificOutput.additionalContext;
		assert.match(ctx, /load_skill/);
		assert.match(ctx, /list_skills/);
		assert.match(ctx, /using-skills/);
	});

	it("fails VISIBLY when the router is missing", () => {
		// A silent exit 0 would make a dead gate indistinguishable from a working
		// one — the exact failure this hook exists to end.
		const empty = mkdtempSync(join(tmpdir(), "skills-gate-empty-"));
		temps.push(empty);
		const out = run(empty);
		assert.ok(out.systemMessage, "expected a visible systemMessage");
		assert.match(out.systemMessage, /NOT injected/);
		assert.equal(out.hookSpecificOutput, undefined);
	});

	it("fails VISIBLY when the router loses a gate section", () => {
		// Guards the section names. If "## Red Flags" is renamed upstream, naive
		// extraction would inject an empty string and look healthy forever.
		const out = run(fakeHome("# Using Skills\n\n## Rule\nonly a rule\n"));
		assert.ok(out.systemMessage, "expected a visible systemMessage");
		assert.match(out.systemMessage, /Red Flags/);
		assert.equal(out.hookSpecificOutput, undefined);
	});

	it("emits parseable JSON even when the router contains JSON metacharacters", () => {
		// The router is human prose; quotes, backslashes and tabs are guaranteed.
		// Escaping is delegated to jq precisely so this holds.
		const nasty = [
			"## Rule",
			'He said "load the skill" \\ then left\ta tab',
			"",
			"## Red Flags",
			'- "This is simple." \\ really',
		].join("\n");
		const ctx = run(fakeHome(nasty)).hookSpecificOutput.additionalContext;
		assert.match(ctx, /He said "load the skill"/);
	});
});
