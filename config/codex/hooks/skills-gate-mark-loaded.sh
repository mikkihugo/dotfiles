#!/usr/bin/env bash
# PostToolUse(load_skill) : record that a skill was loaded in THIS session.
#
# The companion to skills-gate-pretooluse.sh. Without this the gate could only
# nag; with it the gate is satisfiable, so it denies exactly once per session
# per skill and then gets out of the way.
#
# Loading is a real read here: load_skill returns the SKILL.md body into the
# agent's context. That is why this gate does not have the rubber-stamp failure
# mode of a checkbox an agent can tick without looking.
set -uo pipefail

input="$(cat)"
sid="$(printf '%s' "$input" | jq -r '.session_id // ""')"
name="$(printf '%s' "$input" | jq -r '.tool_input.name // .tool_input.arguments.name // ""')"

[ -z "$sid" ] && exit 0
[ -z "$name" ] && exit 0

# Aliases resolve to the canonical skill name, matching the Purpose skill index,
# so a gate requiring `version-control-facade` is satisfied by loading
# `using-repo-vcs`. Keep in sync with the aliases in each SKILL.md frontmatter.
case "$name" in
using-repo-vcs) name="version-control-facade" ;;
using-git-worktrees) name="branch-lifecycle-worktree" ;;
writing-skills) name="instruction-authoring-skills" ;;
esac

dir="${XDG_CACHE_HOME:-$HOME/.cache}/claude-skills-gate/${sid}"
mkdir -p "$dir" 2>/dev/null || exit 0
: >"$dir/$name" 2>/dev/null || exit 0
exit 0
