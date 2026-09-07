#!/usr/bin/env bash
# PreToolUse(Bash) guard: FORBID raw git mutation anywhere inside a jj repository.
#
# Supersedes block-destructive-git-singularity-engine.sh, which only covered
# /home/mhugo/code/singularity-engine and missed:
#   - /srv/infra, where the failure is SILENT: lefthook's jj import resets the
#     index mid-commit, so `git add` + `git commit` commit NOTHING while git,
#     push and Flux all report success.
#   - every worktree under /home/mhugo/code/worktrees/jj/<repo>/<name>, which
#     are checkouts of the same repos and share the same jj store.
#
# Detection is structural, not a path list: walk up from the target directory
# looking for `.jj/`. That covers all current jj repos and any future ones.
#
# Read-only git stays allowed (status, log, diff, show, fetch, for-each-ref,
# rev-parse, describe, ls-files, cat-file, blame).
set -euo pipefail

input="$(cat)"
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // ""')"
cwd="$(printf '%s' "$input" | jq -r '.cwd // ""')"

# jj's OWN git subcommands are the sanctioned publish/sync path out of a jj repo.
# Neutralize exactly those spans before matching, so the deliberately-unanchored
# patterns below cannot mistake `jj git push` for raw `git push`. Only jj's real
# `git` subcommands are neutralized, so `sudo -u jj git commit` still matches.
scan="$(printf '%s' "$cmd" | sed -E 's#(^|[[:space:]]|[;&|`(])([^[:space:];&|]*/)?jj(([[:space:]]+--?[^[:space:]]+)([[:space:]]+[^-[:space:]][^[:space:]]*)?)*[[:space:]]+git[[:space:]]+(clone|colocation|export|fetch|import|init|push|remote|root)([[:space:]]|$)#\1JJSUB_\6 #g')"

# ---- 1. Is this a mutating git command? -------------------------------------
# Destructive history/worktree operations.
destructive='git([[:space:]]+-C[[:space:]]+[^[:space:]]+)?[[:space:]]+(reset|checkout|restore|clean|push|cherry-pick|rebase|merge|switch|gc|prune|apply|am)([[:space:]]|$)'
destructive+='|git[[:space:]]+branch[[:space:]]+-[dDmM]'
destructive+='|git[[:space:]]+stash([[:space:]]+(drop|pop|clear|push|save))?([[:space:]]|$)'
destructive+='|git[[:space:]]+commit[[:space:]][^&|;]*--amend'
destructive+='|git[[:space:]]+reflog[[:space:]]+expire'
destructive+='|git[[:space:]]+update-ref'
destructive+='|git[[:space:]]+worktree[[:space:]]+(add|remove|prune)'
destructive+='|git[[:space:]]+tag[[:space:]]+-d'
destructive+='|git[[:space:]]+remote[[:space:]]+(add|remove|set-url)'
# Index/commit writes. In a jj repo these are wrong even when they appear to
# work — jj owns the working copy, and in /srv/infra they silently no-op.
writes='git([[:space:]]+-C[[:space:]]+[^[:space:]]+)?[[:space:]]+(add|commit|rm|mv)([[:space:]]|$)'

kind=""
if printf '%s' "$scan" | grep -Eiq "$destructive"; then
	kind="destructive"
elif printf '%s' "$scan" | grep -Eiq "$writes"; then
	kind="write"
else
	exit 0
fi

# ---- 2. Resolve the effective target directory ------------------------------
# Precedence: an explicit `git -C <dir>` beats a `cd <dir>` beats the cwd.
target="$cwd"
cdpath="$(printf '%s' "$cmd" | grep -oE '(^|[;&|][[:space:]]*)cd[[:space:]]+[^[:space:]&|;]+' | head -1 | sed -E 's/.*cd[[:space:]]+//')" || true
[ -n "${cdpath:-}" ] && target="$cdpath"
cpath="$(printf '%s' "$cmd" | grep -oE 'git[[:space:]]+-C[[:space:]]+[^[:space:]]+' | head -1 | sed -E 's/git[[:space:]]+-C[[:space:]]+//')" || true
[ -n "${cpath:-}" ] && target="$cpath"

# Relative targets resolve against cwd.
case "$target" in
/*) ;;
"") target="$cwd" ;;
*) target="${cwd%/}/$target" ;;
esac

# ---- 3. Is the target inside a jj repository? -------------------------------
# EXEMPT: /home/mhugo/vendors/* are donor clones of upstream projects. Raw git
# is correct there — shallow clone, fetching a specific tag to check behaviour
# at a deployed version, checking out to compare revisions. Never jj.
case "$target" in
/home/mhugo/vendors | /home/mhugo/vendors/*) exit 0 ;;
esac
if printf '%s' "$cmd" | grep -q '/home/mhugo/vendors/'; then exit 0; fi

# Walk up looking for .jj/. Verified to work on jj workspaces too — they carry
# their own .jj pointing at the shared store, so every worktree under
# /home/mhugo/code/worktrees/jj/<repo>/<name> is covered.
# Note: /home/mhugo/code is 100% jj (59 repos, 0 git-only as of 2026-07-18), so
# in practice anything mutating git under ~/code is a mistake.
jj_root=""
probe="$target"
for _ in 1 2 3 4 5 6 7 8 9 10 11 12; do
	[ -z "$probe" ] && break
	if [ -d "$probe/.jj" ]; then
		jj_root="$probe"
		break
	fi
	[ "$probe" = "/" ] && break
	probe="$(dirname "$probe")"
done

if [ -z "$jj_root" ]; then
	for known in /srv/infra /home/mhugo/code/singularity-engine; do
		if printf '%s' "$cmd" | grep -q "$known"; then
			jj_root="$known"
			break
		fi
	done
fi

[ -z "$jj_root" ] && exit 0

# ---- 4. Name the correct facade for this repo -------------------------------
case "$jj_root" in
/srv/infra* | */worktrees/jj/infra/*)
	facade='just vcs <describe|bookmark-set|push|restore|workspace-create>'
	;;
*/singularity-engine*)
	facade='nix develop path:. --command repo vcs <describe|land|push|workspace-create>'
	;;
*)
	facade="this repo's declared VCS facade (check its AGENTS.md / justfile)"
	;;
esac

if [ "$kind" = "write" ]; then
	reason="BLOCKED: raw 'git add/commit/rm/mv' inside the jj repo at ${jj_root}. jj owns the working copy, so this is wrong even when it appears to succeed. In /srv/infra it is worse than wrong: lefthook's jj import resets the index mid-commit, so the commit contains NOTHING while git, push and Flux all report success. Use: ${facade}"
else
	reason="BLOCKED: destructive raw git inside the jj repo at ${jj_root}. It corrupts jj state and can destroy uncommitted work in this and every sibling workspace sharing the store. Use: ${facade}. Read-only git (status, log, diff, show, fetch, rev-parse, for-each-ref) is allowed."
fi

jq -nc --arg r "$reason" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
exit 0
