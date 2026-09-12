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

/**
 * Run the hook with HOME=home and parse its stdout as JSON.
 * `extraEnv` overrides/clears harness-detection variables; a null value unsets.
 */
function run(home, extraEnv = {}) {
	const env = { ...process.env, HOME: home };
	// Always start from a clean detection surface so a variable leaking in from
	// the developer's own shell cannot silently decide the shape under test.
	for (const key of [
		"SKILLS_GATE_SHAPE",
		"COPILOT_CLI",
		"COPILOT_CLI_BINARY_VERSION",
		"COPILOT_CLI_DIST_DIR",
		"COPILOT_CLI_RESOLVED_DIST_DIR",
		"CURSOR_PLUGIN_ROOT",
		"CURSOR_TRACE_ID",
		"KIMI_API_KEY",
		"KIMI_CODE_EXPERIMENTAL_FLAG",
	]) {
		delete env[key];
	}
	for (const [key, value] of Object.entries(extraEnv)) {
		if (value === null) delete env[key];
		else env[key] = value;
	}
	const stdout = execFileSync("bash", [HOOK], { env, input: "{}", encoding: "utf8" });
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
		assert.match(
			out.systemMessage,
			/skill:\/\/purpose_tool\/host-hooks\/skills-gate-session-start\.sh/,
			"failure must name the replacement resource URI",
		);
		assert.match(
			out.systemMessage,
			/hash=[0-9a-f]{64}/,
			"failure must name the installed hook content hash so a mismatch can upgrade",
		);
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

	// A "## " line inside a fenced code block must NOT end the section.
	// Without fence awareness the extractor truncates there and still emits
	// valid JSON with exit 0 -- a silent partial gate, which the emptiness
	// guard cannot catch because a truncated section is still non-empty.
	// This is not hypothetical: the live router carries a ```text fence inside
	// "## Rule", and fenced examples containing a literal "## Red Flags"
	// heading are an attested idiom in this skill corpus.
	const FENCED = [
		"# Using Skills",
		"",
		"## Rule",
		"1. Identify skills whose description might apply.",
		"```text",
		"## Fake Header inside a fence",
		"gate before_acting(task)",
		"```",
		"rule tail that must survive",
		"",
		"## Red Flags",
		'- "This is simple."',
		"flags tail that must survive",
		"",
		"## Priority",
		"trailing noise",
	].join("\n");

	it("does not truncate a section at a '## ' line inside a code fence", () => {
		const ctx = run(fakeHome(FENCED)).hookSpecificOutput.additionalContext;
		assert.match(ctx, /rule tail that must survive/);
		assert.match(ctx, /flags tail that must survive/);
		assert.match(ctx, /Fake Header inside a fence/);
		// and it still stops at the genuine next header
		assert.doesNotMatch(ctx, /trailing noise/);
	});

	it("never emits an unbalanced code fence", () => {
		// The cheap general guard: any mid-fence truncation, from any future
		// cause, leaves an odd number of ``` markers, which makes everything
		// after it read as sample text instead of instruction.
		for (const body of [FULL, FENCED]) {
			const ctx = run(fakeHome(body)).hookSpecificOutput.additionalContext;
			const fences = (ctx.match(/```/g) ?? []).length;
			assert.equal(fences % 2, 0, `odd fence count (${fences}) in injected context`);
		}
	});
});

/**
 * Harness shape selection.
 *
 * These exist because the shape paths were originally UNTESTED, and that gap
 * hid two real bugs of the same kind: a variable name copied from upstream
 * without measuring what the process actually exports. First CLAUDE_PLUGIN_ROOT
 * (set only for plugin hooks, never for user hooks), then COPILOT_CLI (never
 * set at all -- Copilot exports COPILOT_CLI_DIST_DIR and friends). Both sent a
 * client to the wrong shape, which fails SILENTLY: the hook still prints valid
 * JSON, the client just ignores a field it does not know.
 */
describe("skills gate harness shape selection", () => {
	const home = () => fakeHome(FULL);

	it("defaults to the Claude shape when no harness is detected", () => {
		// Claude Code sets NEITHER CLAUDE_PLUGIN_ROOT nor CLAUDE_PROJECT_DIR for
		// user hooks (measured), so "no signal" must mean Claude, not SDK.
		const out = run(home());
		assert.equal(out.hookSpecificOutput?.hookEventName, "SessionStart");
		assert.ok(out.hookSpecificOutput?.additionalContext);
	});

	for (const [label, env] of [
		["COPILOT_CLI_DIST_DIR", { COPILOT_CLI_DIST_DIR: "/opt/copilot/dist" }],
		["COPILOT_CLI_BINARY_VERSION", { COPILOT_CLI_BINARY_VERSION: "1.0.11" }],
		["COPILOT_CLI_RESOLVED_DIST_DIR", { COPILOT_CLI_RESOLVED_DIST_DIR: "/opt/copilot" }],
		["COPILOT_CLI", { COPILOT_CLI: "1" }],
	]) {
		it(`selects the SDK shape for Copilot via ${label}`, () => {
			// Regression: only the last of these was originally checked, and it is
			// the one Copilot never actually sets.
			const out = run(home(), env);
			assert.deepEqual(Object.keys(out), ["additionalContext"]);
			assert.match(out.additionalContext, /## Red Flags/);
		});
	}

	it("selects the Cursor shape via CURSOR_TRACE_ID", () => {
		const out = run(home(), { CURSOR_TRACE_ID: "abc123" });
		assert.deepEqual(Object.keys(out), ["additional_context"]);
		assert.match(out.additional_context, /## Rule/);
	});

	for (const [shape, key] of [
		["claude", "hookSpecificOutput"],
		["cursor", "additional_context"],
		["sdk", "additionalContext"],
	]) {
		it(`SKILLS_GATE_SHAPE=${shape} overrides auto-detection`, () => {
			// Every client registration pins this explicitly, so the override must
			// win even when a competing harness variable is present.
			const out = run(home(), { SKILLS_GATE_SHAPE: shape, COPILOT_CLI_DIST_DIR: "/opt/x" });
			assert.deepEqual(Object.keys(out), [key]);
		});
	}
});
