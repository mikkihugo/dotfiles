#!/usr/bin/env bash
# PreToolUse(Bash) gate: refuse a skill-governed action until its skill is loaded.
#
# WHY THIS EXISTS, and why it is a DENY rather than more injected text.
#
# skills-gate-session-start.sh injects the router gate at SessionStart. That was
# already a step up from prose in CLAUDE.md, but it is still delivered ONCE, at
# turn zero. Measured in a single long session on 2026-09-08: with that gate
# active and in context -- <EXTREMELY_IMPORTANT>, a pseudo-code gate, a Red Flags
# list naming the agent's own rationalizations -- the agent made ~3000 tool calls
# and loaded a skill 9 times. Every one of those 9 was triggered by a human
# asking about skills; the first came 121 user-turns in. ZERO were gate-initiated
# at the start of a task.
#
# What DID redirect the agent in that same session, every time, was a refusal at
# the moment of the action: block-raw-git-in-jj-repos.sh denying a heredoc, the
# background-isolation guard denying an edit, the drift gate refusing a publish.
# Three for three. The one piece of prose that worked was the Workflow tool's own
# description ("load the workflow-authoring skill"), which is read at the moment
# the tool is invoked -- same position, minus the teeth.
#
# The difference is POSITION, not emphasis. So this hook puts the requirement
# where the action is, and makes it blocking.
#
# Deliberately NARROW. A gate that fires on everything is a gate that gets
# rationalized away, which is the failure mode it exists to fix. Add a rule only
# when there is a measured incident behind it.
set -uo pipefail

input="$(cat)"
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // ""')"
cwd="$(printf '%s' "$input" | jq -r '.cwd // ""')"
sid="$(printf '%s' "$input" | jq -r '.session_id // ""')"

[ -z "$cmd" ] && exit 0

marker_dir="${XDG_CACHE_HOME:-$HOME/.cache}/claude-skills-gate/${sid:-nosession}"

# A skill counts as loaded for this session once skills-gate-mark-loaded.sh has
# seen a load_skill call for it. Aliases resolve to the canonical name there.
skill_loaded() { [ -n "$sid" ] && [ -e "$marker_dir/$1" ]; }

# ---- resolve the effective directory (cd <dir> beats cwd) -------------------
target="$cwd"
cdpath="$(printf '%s' "$cmd" | grep -oE '(^|[;&|][[:space:]]*)cd[[:space:]]+[^[:space:]&|;]+' | head -1 | sed -E 's/.*cd[[:space:]]+//')" || true
[ -n "${cdpath:-}" ] && target="$cdpath"
case "$target" in
/*) ;;
"") target="$cwd" ;;
*) target="${cwd%/}/$target" ;;
esac

# ---- rule 1: hand-opening a protected canonical primary ---------------------
# Structural, like block-raw-git-in-jj-repos.sh: a remount whose target path is
# a repository ROOT (contains .jj or .git) is an attempt to open a protected
# checkout by hand. Measured 2026-09-05..09-08 on this host: ~100 hand openings
# of one protected primary against ~57 restores -- roughly 2:1, i.e. the
# protected state was routinely left open. Whatever caused that (not traced),
# the facade -- not a human -- must own the window.
if printf '%s' "$cmd" | grep -Eq 'mount[[:space:]]+(-[^[:space:]]+[[:space:]]+)*-o[[:space:]]+[^[:space:]]*remount'; then
	for word in $cmd; do
		case "$word" in
		/*)
			if [ -d "$word/.jj" ] || [ -d "$word/.git" ]; then
				if ! skill_loaded version-control-facade; then
					reason="BLOCKED: this remounts the protected canonical primary at ${word} by hand. That is a facade bypass of the same class as raw git or raw jj: the facade owns the write window under its declared lock, and a hand-opened window is routinely left open (measured on this host: ~100 openings against ~57 restores, 2026-09-05..09-08). Load the skill first: load_skill({ name: \"version-control-facade\" }) -- see its 'Protected-primary write window' section -- then use the repository's repo vcs route. If no such route exists, that is the bug to fix; do not open the window by hand."
					jq -nc --arg r "$reason" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
					exit 0
				fi
			fi
			;;
		esac
	done
fi

# ---- rule 2: publication transitions ----------------------------------------
# land/promote/publish are the hard-to-reverse, single-writer transitions where
# this session repeatedly recorded success that had not happened (a publish
# exiting non-zero AFTER its push succeeded; a workspace-close exiting clean
# while the lane stayed live). The skill carries the read-back-the-artifact rule.
if printf '%s' "$cmd" | grep -Eq '(^|[[:space:];&|(])(repo|just)[[:space:]]+vcs[[:space:]]+(land|promote|publish)([[:space:]]|$)'; then
	if ! skill_loaded version-control-facade; then
		reason="BLOCKED: publication transition (land/promote/publish) without version-control-facade loaded. This is the single-writer, hard-to-reverse transition, and on this host these commands have exited zero while changing nothing AND exited non-zero after already succeeding -- so the exit code is not the result. Load it first: load_skill({ name: \"version-control-facade\" }), then verify by artifact: read back the state the command claims to have changed."
		jq -nc --arg r "$reason" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
		exit 0
	fi
fi

exit 0
