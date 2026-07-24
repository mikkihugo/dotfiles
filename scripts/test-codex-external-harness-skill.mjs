import assert from "node:assert/strict";
import { access, readFile } from "node:fs/promises";
import { constants as fsConstants } from "node:fs";
import test from "node:test";

const AGENTS = "config/codex/AGENTS.md";
const FILES_NIX = "home/modules/files.nix";
const SKILL_DIR = "config/codex/skills/external-harness-orchestration";
const SKILL_MD = `${SKILL_DIR}/SKILL.md`;
const OPENAI_YAML = `${SKILL_DIR}/agents/openai.yaml`;
const REMOVED_CODEX_RUNBOOK =
  "config/codex/runbooks/codex-external-harness-orchestration.md";
const LEGACY_DOCS_RUNBOOK =
  "docs/runbooks/codex-external-harness-orchestration.md";

const readUtf8 = async (path) => readFile(path, "utf8");

const parseFrontmatter = (text) => {
  const match = text.match(/^---\r?\n([\s\S]*?)\r?\n---/);
  assert.ok(match, "SKILL.md must start with YAML frontmatter");
  const block = match[1];
  const name = block.match(/^name:\s*(.+)$/m)?.[1]?.trim();
  const descriptionLine = block.match(/^description:\s*(.+)$/m)?.[1]?.trim();
  assert.ok(name, "frontmatter name required");
  assert.ok(descriptionLine, "frontmatter description required");
  return { name, description: descriptionLine, body: text.slice(match[0].length) };
};

const requireBehavior = (text, patterns, label) => {
  for (const pattern of patterns) {
    assert.match(text, pattern, `${label}: missing ${pattern}`);
  }
};

const descriptionMatches = (description, terms) =>
  terms.every((term) => {
    if (term instanceof RegExp) return term.test(description);
    return description.toLowerCase().includes(String(term).toLowerCase());
  });

const splitDescriptionHalves = (description) => {
  const match = description.match(
    /^Use when\b([\s\S]+?)\.\s*Not for\b([\s\S]+)$/i,
  );
  assert.ok(
    match,
    "description must be `Use when ... . Not for ...` so trigger halves are separable",
  );
  return { useWhen: match[1].trim(), notFor: match[2].trim() };
};

test("skill frontmatter and openai.yaml exist with Use when / Not for description", async () => {
  await access(SKILL_MD, fsConstants.R_OK);
  await access(OPENAI_YAML, fsConstants.R_OK);
  const skill = await readUtf8(SKILL_MD);
  const { name, description } = parseFrontmatter(skill);
  assert.equal(name, "external-harness-orchestration");
  assert.match(description, /^Use when\b/);
  assert.match(description, /\bNot for\b/i);
  assert.ok(description.length <= 1024, "description must stay under 1024 chars");

  const openai = await readUtf8(OPENAI_YAML);
  requireBehavior(
    openai,
    [/display_name:/, /short_description:/, /default_prompt:/],
    "openai.yaml interface",
  );
  assert.match(openai, /\$external-harness-orchestration/);
});

test("main-agent-only SUBAGENT-STOP tells bounded subagent to stop and return to root", async () => {
  const body = parseFrontmatter(await readUtf8(SKILL_MD)).body;
  assert.match(body, /<SUBAGENT-STOP>/);
  assert.match(body, /<\/SUBAGENT-STOP>/);
  const stopBlock = body.match(/<SUBAGENT-STOP>([\s\S]*?)<\/SUBAGENT-STOP>/)?.[1] ?? "";
  requireBehavior(
    stopBlock,
    [
      /bounded subagent|dispatched as a (?:bounded )?subagent/i,
      /stop/i,
      /return to (?:Codex )?root/i,
    ],
    "SUBAGENT-STOP guard",
  );
});

test("trigger: delegated external work loads skill; Codex remains sole publisher", async () => {
  const skill = await readUtf8(SKILL_MD);
  const { description, body } = parseFrontmatter(skill);
  const surface = `${description}\n${body}`;

  assert.ok(
    descriptionMatches(description, [
      /delegat/i,
      /external/i,
      /Kimi|Cursor/i,
    ]),
    "description should trigger on delegated external Kimi/Cursor work",
  );

  requireBehavior(
    surface,
    [
      /coordinator, verifier, and sole publisher/i,
      /MUST NOT use Codex subagents for delegated work/i,
      /fresh portable prompts/i,
      /bounded owned paths/i,
      /no VCS\/publication authority/i,
      /machine-readable evidence/i,
      /independently verif/i,
      /repo-memory/i,
    ],
    "trigger policy",
  );
});

test("near-miss: Default/Plan or v1/v2 wording alone cannot satisfy frontmatter trigger", async () => {
  const skill = await readUtf8(SKILL_MD);
  const { description, body } = parseFrontmatter(skill);
  const { useWhen, notFor } = splitDescriptionHalves(description);

  // Positive half requires external delegation; UI/lifecycle words alone are insufficient.
  requireBehavior(
    useWhen,
    [/delegat/i, /external/i, /Kimi|Cursor/i],
    "Use when positive trigger",
  );
  assert.doesNotMatch(
    useWhen,
    /Default\/Plan|multi-agent v1\/v2|lifecycle\/UI/i,
    "Use when must not treat Default/Plan or v1/v2 as the load trigger",
  );

  // Exclusion half must name the near-miss modes so UI-only prompts cannot satisfy the contract.
  requireBehavior(
    notFor,
    [/Default\/Plan/i, /multi-agent v1\/v2/i, /\balone\b/i],
    "Not for near-miss exclusion",
  );

  const nearMissPrompts = [
    "Switch Codex to Default/Plan mode",
    "Explain multi-agent v1/v2 lifecycle",
    "Use Default/Plan and multi-agent v1/v2 alone",
  ];
  for (const prompt of nearMissPrompts) {
    const mentionsUiMode = /Default\/Plan|multi-agent v1\/v2/i.test(prompt);
    const mentionsDelegation = /delegat|external worker|Kimi CLI|Cursor worker/i.test(
      prompt,
    );
    assert.ok(mentionsUiMode && !mentionsDelegation, `near-miss fixture: ${prompt}`);

    // Frontmatter trigger contract is satisfied only when positive Use-when terms match
    // AND the prompt is outside the Not-for exclusion. UI-only wording fails that gate.
    const positiveMatch = [/delegat/i, /external/i, /Kimi|Cursor/i].every((re) =>
      re.test(prompt),
    );
    const excludedByNotFor =
      (/Default\/Plan/i.test(prompt) && /Default\/Plan/i.test(notFor)) ||
      (/v1\/v2/i.test(prompt) && /v1\/v2/i.test(notFor));
    assert.equal(
      positiveMatch,
      false,
      `UI-only prompt must not match Use-when positive terms: ${prompt}`,
    );
    assert.equal(
      excludedByNotFor,
      true,
      `UI-only prompt must be covered by Not for: ${prompt}`,
    );
  }

  requireBehavior(
    body,
    [
      /Default\/Plan/i,
      /multi-agent v1\/v2/i,
      /lifecycle\/UI modes/i,
      /not protocol fixes/i,
    ],
    "near-miss body clarification",
  );
  assert.doesNotMatch(
    body,
    /Default\/Plan[\s\S]{0,120}fixes encrypted_content/i,
    "near miss must not treat Default/Plan as an encrypted_content protocol fix",
  );
});

test("alternate phrasing: encrypted_content fails closed or starts fresh portable session", async () => {
  const skill = await readUtf8(SKILL_MD);
  const { description, body } = parseFrontmatter(skill);
  const surface = `${description}\n${body}`;

  assert.ok(
    descriptionMatches(description, [/delegat|external|worker|harness/i]),
    "rephrased external-worker prompts should still match description",
  );

  requireBehavior(
    surface,
    [
      /encrypted_content/i,
      /not assumed portable/i,
      /compatible same[- ]upstream/i,
      /opaque replay/i,
      /MUST NOT be translated to\s+chat\/Anthropic\/external models/i,
      /silently stripped/i,
      /fail closed/i,
      /fresh portable (prompts|session)/i,
      /transferable instructions\/transcript/i,
    ],
    "alternate phrasing",
  );
});

test("Kimi prompt-mode command uses exact model/flags and forbids --prompt with --auto/--yolo", async () => {
  const body = parseFrontmatter(await readUtf8(SKILL_MD)).body;
  requireBehavior(
    body,
    [
      /kimi --model kimi-code\/k3 --output-format stream-json --prompt <task>/,
      /MUST NOT combine `--prompt` with `--auto` or `--yolo`/,
    ],
    "kimi flags",
  );
});

test("Cursor preferred subscription models are non-fast only", async () => {
  const body = parseFrontmatter(await readUtf8(SKILL_MD)).body;
  requireBehavior(
    body,
    [
      /cursor-grok-4\.5-high/,
      /composer-2\.5/,
      /MUST NOT select `\*-fast`/,
    ],
    "cursor non-fast",
  );
  assert.doesNotMatch(
    body,
    /prefer[\s\S]{0,80}composer-2\.5-fast/i,
    "must not prefer composer-2.5-fast",
  );
});

test("concurrency enforces operator hard ceilings plus resource-based lower limits", async () => {
  const body = parseFrontmatter(await readUtf8(SKILL_MD)).body;
  requireBehavior(
    body,
    [
      /resource-budgeted|resource budget/i,
      /provider-aware|provider capacity/i,
      /host RAM|host memory|memory budget|RAM\/headroom/i,
      /independent ownership lanes/i,
      /at least two independent/i,
      /smaller of|lower of|minimum of/i,
      /at most 10 total (Kimi )?agents per Kimi coordinator\/swarm including the lead/i,
      /at most 30 Kimi agents globally/i,
      /hard ceilings, not targets/i,
      /reserve[s]? an agent budget including the lead/i,
    ],
    "operator hard ceilings",
  );
  assert.doesNotMatch(
    body,
    /encode a permanent numeric ceiling/i,
    "obsolete no-numeric-ceiling rule must be replaced by the operator hard ceilings",
  );
});

test("run provenance launcher contract is documented and fail-closed", async () => {
  const body = parseFrontmatter(await readUtf8(SKILL_MD)).body;
  requireBehavior(
    body,
    [
      /codex-external-run/,
      /~\/\.codex\/bin\/codex-external-run/,
      /XDG_STATE_HOME\/codex/,
      /~\/\.local\/state\/codex/,
      /0700/,
      /0600/,
      /schema version/,
      /root_task_id/,
      /parent_task_id/,
      /run_id/,
      /coordinator/,
      /harness/,
      /absolute workspace/,
      /agent budget/,
      /launcher PID/,
      /child PID/,
      /start\/end timestamps|started\/ended timestamps|start and end timestamps/,
      /lifecycle status/,
      /exit\/signal/,
      /never persist[s]? prompt content, command arguments, environment, credentials, or tool output/i,
      /explicit root\/parent\/task identity/i,
      /no silent anonymous default/i,
      /collision-resistant generated run IDs/i,
      /reject[s]? an existing run record/i,
      /advisory lock/,
      /fail[s]? closed/i,
      /parentAgentId/,
      /anchors the lead session to root\/parent\/task/,
      /repo-memory stores durable outcomes\/decisions/i,
      /not the primary transient PID\/run registry/i,
    ],
    "run provenance launcher",
  );
});

test("Home Manager installs the launcher only under ~/.codex", async () => {
  const filesNix = await readUtf8(FILES_NIX);
  requireBehavior(
    filesNix,
    [
      /"\.codex\/bin\/codex-external-run"\s*=\s*\{/,
      /replaceVars\s+\.\.\/\.\.\/config\/codex\/bin\/codex-external-run\.mjs/,
      /executable\s*=\s*true/,
    ],
    "launcher home manager mapping",
  );
  assert.doesNotMatch(
    filesNix,
    /"\.agents\/bin\/codex-external-run"\s*=/,
    "launcher must not install under ~/.agents",
  );
});

test("Home Manager maps only this user skill; no singularity-engine-forward mapping", async () => {
  const filesNix = await readUtf8(FILES_NIX);
  requireBehavior(
    filesNix,
    [
      /"\.codex\/skills\/external-harness-orchestration"\s*=\s*\{/,
      /source\s*=\s*\.\.\/\.\.\/config\/codex\/skills\/external-harness-orchestration/,
      /recursive\s*=\s*true/,
    ],
    "home manager exact mapping",
  );
  assert.doesNotMatch(
    filesNix,
    /"\.codex\/skills\/singularity-engine-forward"\s*=/,
    "must not map singularity-engine-forward",
  );
  assert.doesNotMatch(
    filesNix,
    /"\.agents\/skills[^"]*"\s*=/,
    "must not mirror .agents/skills",
  );
  assert.doesNotMatch(
    filesNix,
    /"\.codex\/skills\/\.system[^"]*"\s*=/,
    "must not mirror .system skill tree",
  );
});

test("AGENTS handwritten section is a minimal load-skill trigger only", async () => {
  const agents = await readUtf8(AGENTS);
  const managedStart = agents.indexOf("<!-- BEGIN purpose-tool skills");
  assert.ok(managedStart > 0, "managed Purpose block marker required");
  const handwritten = agents.slice(0, managedStart);

  requireBehavior(
    handwritten,
    [
      /external-harness-orchestration/,
      /load|read|follow/i,
      /delegat/i,
    ],
    "AGENTS skill trigger",
  );
  assert.doesNotMatch(
    handwritten,
    /kimi --model kimi-code\/k3 --output-format stream-json --prompt <task>/,
    "AGENTS must not inline the full Kimi command",
  );
  assert.doesNotMatch(
    handwritten,
    /config\/codex\/runbooks\/codex-external-harness-orchestration\.md/,
    "AGENTS must not point at the removed runbook",
  );
});

test("general orchestration runbook is absent", async () => {
  await assert.rejects(
    () => access(REMOVED_CODEX_RUNBOOK, fsConstants.F_OK),
    { code: "ENOENT" },
    "config/codex/runbooks copy must be removed",
  );
  await assert.rejects(
    () => access(LEGACY_DOCS_RUNBOOK, fsConstants.F_OK),
    { code: "ENOENT" },
    "docs/runbooks copy must remain absent",
  );
});

test("no-VCS rule is instruction policy, not a sandbox; worker state is untrusted", async () => {
  const body = parseFrontmatter(await readUtf8(SKILL_MD)).body;
  requireBehavior(
    body,
    [
      /instruction policy, not a sandbox/,
      /can technically mutate\/publish/,
      /strongest available least-privilege boundary/,
      /keep publication credentials\/commands unavailable where practical/,
      /treats worker state\/report as untrusted/,
      /verifies local repo VCS state\/diff\/tests before publication/,
    ],
    "policy-not-sandbox",
  );
});

test("Kimi 0.28.1 prompt-mode behavior is documented (auto permission, handlers, validateOptions)", async () => {
  const body = parseFrontmatter(await readUtf8(SKILL_MD)).body;
  requireBehavior(
    body,
    [
      /Kimi 0\.28\.1/,
      /`--prompt` is noninteractive/,
      /created\/resumed with `auto` permission/,
      /approval handler auto-approves/,
      /null question handler/,
      /`validateOptions` rejects combining `--prompt` with `--auto` or `--yolo`/,
    ],
    "kimi 0.28.1 behavior",
  );
});

test("fail-closed worker evidence minimum and independent coordinator rerun", async () => {
  const body = parseFrontmatter(await readUtf8(SKILL_MD)).body;
  requireBehavior(
    body,
    [
      /task\/lane id/,
      /owned paths touched/,
      /commands with exit status/,
      /test output summary/,
      /unresolved issues/,
      /advisory\/untrusted/,
      /no cryptographic signature is needed/,
      /Malformed, absent, or incomplete evidence: do not publish/,
      /inspect\/discard the worker output/,
      /independently reruns status\/diff\/tests before publication/,
    ],
    "evidence minimum",
  );
});

test("Cursor implementation and read-only commands are proven; boundary fails closed", async () => {
  const body = parseFrontmatter(await readUtf8(SKILL_MD)).body;
  requireBehavior(
    body,
    [
      /cursor-agent --print --force --sandbox enabled --output-format stream-json --model <model> <task>/,
      /cursor-agent --print --mode plan --output-format stream-json --model <model> <task>/,
      /proposed only and files are not modified/,
      /silently denies unapproved commands/,
      /strongest current runtime boundary/,
      /\.cursor\/cli\.json/,
      /deny takes precedence/,
      /do not prove exact per-path or VCS isolation/,
      /task-scoped permissions/,
      /verify them before launch/,
      /keep Cursor read-only/,
      /another bounded implementation harness/,
      /proven by installed `cursor-agent --help`/,
      /version-dependent/,
      /pin them in the ownership packet/,
      /do not launch if they cannot be proven/,
      /Do not invent flags/,
    ],
    "cursor proven commands and fail-closed boundary",
  );
});

test("skill activates only in Codex root; workers cannot load it; root never dispatches it to subagents", async () => {
  const body = parseFrontmatter(await readUtf8(SKILL_MD)).body;
  requireBehavior(
    body,
    [
      /activates only in Codex root/,
      /External workers cannot load it/,
      /MUST inline its ownership\/evidence boundaries/,
      /works only when the full skill is loaded/,
      /MUST NOT dispatch this skill itself to subagents/,
    ],
    "root-only activation",
  );
});

test("concurrency requires live memory check and stops before swap/memory pressure worsens", async () => {
  const body = parseFrontmatter(await readUtf8(SKILL_MD)).body;
  requireBehavior(
    body,
    [
      /live memory check/,
      /Stop launches before swap\/available-memory pressure worsens/,
    ],
    "live memory concurrency",
  );
});

test("skill cites the exact contract-test paths and commands", async () => {
  const body = parseFrontmatter(await readUtf8(SKILL_MD)).body;
  requireBehavior(
    body,
    [
      /node --test scripts\/test-codex-external-harness-skill\.mjs/,
      /node --test scripts\/test-codex-external-run\.mjs/,
    ],
    "contract-test citation",
  );
});
