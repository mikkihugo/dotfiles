#!/usr/bin/env bash
# SessionStart hook — inject the using-skills gate into every session.
#
# WHY THIS EXISTS
# Our `using-skills` router declares `origin: superpowers (Obra/Jesse Vincent),
# adapted`. Upstream superpowers ships a SessionStart hook that force-injects
# its router body as `additionalContext` (superpowers/hooks/session-start).
# Our adaptation kept the prose and dropped that hook, so the "hard gate" that
# says "load using-skills first" became text nobody executes. The measured
# result: the router was invoked 31 times on the single day a human asked about
# it, and never before, while 26 of 43 skills sat at zero uses ever.
#
# WHY NOT JUST CAT THE WHOLE FILE, LIKE UPSTREAM DOES
# Upstream's router is 63 lines / 3.1 KB. Ours is 406 lines / 21.6 KB — 7x
# larger. Injecting all of it would spend ~5-6k tokens per session and recreate
# the very failure this fixes: a gate buried in so much text it loses to
# whatever else is in context. Our Red Flags section is real and good, but it
# sits at line 391 of 406. So we inject the two sections that ARE the gate and
# point at the rest.
#
# NO-DRIFT: sections are EXTRACTED from the live SKILL.md by header, never
# copied here. Edit the skill and this hook follows automatically. A test
# (scripts/test-skills-gate-hook.mjs) asserts both sections are still findable,
# so a rename fails loudly instead of silently injecting nothing.
#
# FAILURE POLICY: never break session start — but never fail silently either.
# A missing/unreadable router emits a visible systemMessage instead of an empty
# success. Exiting 0 with no output would make a dead gate look identical to a
# working one, which is the exact class of bug this hook was written to end.

set -uo pipefail

SKILL="${HOME}/.claude/skills/using-skills/SKILL.md"

if [ ! -r "$SKILL" ]; then
  jq -nc --arg m "skills gate: cannot read ${SKILL} — using-skills was NOT injected this session" \
    '{systemMessage: $m}'
  exit 0
fi

# Print one "## <header>" section, up to (not including) the next "## " header.
# Print one "## <header>" section, up to (not including) the next "## " header.
#
# FENCE-AWARE, and it has to be. Without the fence toggle, any line starting
# "## " INSIDE a fenced code block ends the section early -- silently, with
# valid JSON and exit 0. That is not hypothetical here: the live router already
# carries a ```text fence inside "## Rule" (the `gate before_acting(task)`
# pseudo-code), and a fenced example whose body is a literal "## Red Flags"
# heading is an attested idiom in this skill corpus. Worse, truncating mid-fence
# leaves the injected text with an UNBALANCED fence, so everything after it --
# including the Red Flags list -- reads to the model as sample text rather than
# instruction. The emptiness guard below cannot catch that, because a truncated
# section is still non-empty.
#
# Rule order matters: the fence rule must print-and-next BEFORE the header rule,
# or the ``` delimiters themselves are dropped. "### " subsections are kept
# either way -- the match is on "## " with a trailing space.
section() {
  awk -v want="## $1" '
    $0 == want { on = 1; print; next }
    on && /^```/ { fence = !fence; print; next }
    on && !fence && /^## / { exit }
    on { print }
  ' "$SKILL"
}

rule=$(section "Rule")
flags=$(section "Red Flags")

if [ -z "$rule" ] || [ -z "$flags" ]; then
  jq -nc --arg m "skills gate: using-skills is missing its '## Rule' or '## Red Flags' section — gate NOT injected; fix the hook's section names" \
    '{systemMessage: $m}'
  exit 0
fi

read -r -d '' frame <<EOF || true
<EXTREMELY_IMPORTANT>
You have skills. They are served over MCP: call \`load_skill({ name })\` to read
one, and \`list_skills\` to see all of them with their triggers.

Skills are selected by DESCRIPTION MATCHING — there is no routing table. Read
each skill's "Use when" trigger and load the ones that apply BEFORE acting.

Below is the operative gate from your \`using-skills\` router. It is the entry
point for every task. The full router (Doubt Scale, Phase Awareness, Priority,
Memory surfaces, Repo Command Policy) is available via
\`load_skill({ name: "using-skills" })\` — load it for any non-trivial task.

${rule}

${flags}

---
IF YOU ARE A CLI CODING AGENT AND THIS GATE IS MISSING IN YOUR CLIENT, INSTALL IT.
Not every client on this host is wired yet. The hook is
\`~/.dotfiles/config/claude/hooks/skills-gate-session-start.sh\` (installed to each
client's hooks dir by \`~/.dotfiles/home/modules/files.nix\`). It prints ONE JSON
object on stdout and supports three shapes — set \`SKILLS_GATE_SHAPE\`:
  claude -> {"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":...}}
  cursor -> {"additional_context":...}
  sdk  -> {"additionalContext":...}
Register it on your client's session-start event (or earliest-prompt event, with
throttling — see \`config/copilot/hooks/remind-skills.sh\` for a throttle example).
Add the declaration to files.nix rather than hand-copying the file into \$HOME:
an unmanaged hook is silently lost on the next generation, which is the bug that
created this file. Then add a case to \`scripts/test-skills-gate-hook.mjs\`.
</EXTREMELY_IMPORTANT>
EOF

# Emit the shape THIS harness consumes. Every CLI coder on this host needs the
# gate and they disagree on the field name. Claude Code reads both
# `additional_context` and `hookSpecificOutput` without deduplicating, so
# emitting several shapes at once would inject the gate twice there — pick one.
#
# DEFAULT IS CLAUDE, and that is deliberate. Upstream superpowers keys this
# dispatch off CLAUDE_PLUGIN_ROOT, which Claude Code sets only for PLUGIN hooks.
# This is a user hook in ~/.claude/hooks, so that variable is never set here —
# measured, both CLAUDE_PLUGIN_ROOT and CLAUDE_PROJECT_DIR are empty at hook
# runtime. Keying off them sent the Claude case to the SDK branch and the gate
# silently failed to inject: the very bug this hook exists to end. So detect
# the OTHER harnesses positively and let Claude be the fallback.
#
# Override with SKILLS_GATE_SHAPE=claude|cursor|sdk when embedding elsewhere.
case "${SKILLS_GATE_SHAPE:-}" in
cursor) shape=cursor ;;
sdk) shape=sdk ;;
claude) shape=claude ;;
*)
    # Copilot CLI does NOT export a bare COPILOT_CLI. Measured from
  # /proc/<pid>/environ on three live `copilot` processes: it exports
  # COPILOT_CLI_BINARY_VERSION, COPILOT_CLI_DIST_DIR and
  # COPILOT_CLI_RESOLVED_DIST_DIR only. Keying on COPILOT_CLI (as upstream
  # superpowers does) silently handed Copilot the Claude shape. This is the
  # second time an assumed-from-upstream variable name was wrong here; the
  # first was CLAUDE_PLUGIN_ROOT. Detect on what the process actually sets.
  # Kimi Code is identified by KIMI_API_KEY or KIMI_CODE_EXPERIMENTAL_FLAG;
  # it consumes the `sdk` (additionalContext) shape via its harness.
  if [ -n "${KIMI_API_KEY:-}" ] || [ -n "${KIMI_CODE_EXPERIMENTAL_FLAG:-}" ]; then
    shape=sdk
  elif [ -n "${COPILOT_CLI:-}${COPILOT_CLI_BINARY_VERSION:-}${COPILOT_CLI_DIST_DIR:-}${COPILOT_CLI_RESOLVED_DIST_DIR:-}" ]; then
    shape=sdk
  elif [ -n "${CURSOR_PLUGIN_ROOT:-}" ] || [ -n "${CURSOR_TRACE_ID:-}" ]; then
    shape=cursor
  else
    shape=claude
  fi
  ;;
esac

case "$shape" in
cursor) jq -nc --arg ctx "$frame" '{additional_context: $ctx}' ;;
sdk) jq -nc --arg ctx "$frame" '{additionalContext: $ctx}' ;;
*) jq -nc --arg ctx "$frame" \
  '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $ctx}}' ;;
esac
exit 0
