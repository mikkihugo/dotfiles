#!/usr/bin/env bash
# Purpose: Sole agent-facing VCS facade for dotfiles.
# Contract: Validates the repository root, disables persistent SSH masters,
# verifies before publication, reads back the remote revision, and removes only
# clean registered non-current worktrees.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
remote_ssh="${DOTFILES_GIT_SSH_COMMAND:-ssh -o ControlMaster=no -o ControlPath=none -o ControlPersist=no}"
forgejo_https_url="https://git.centralcloud.net/mhugo/dotfiles.git"
github_url="git@github.com:mikkihugo/dotfiles.git"
push_timeout="${DOTFILES_GIT_PUSH_TIMEOUT:-300}"
git_bin="${SE_GIT_BIN:-}"

if [[ -z "$git_bin" ]]; then
	git_bin="$(command -v git || true)"
fi
[[ "$git_bin" == /* && -x "$git_bin" && ! -d "$git_bin" ]] || {
	printf 'dotfiles-vcs: missing executable Git; set SE_GIT_BIN to the pinned Nix Git path\n' >&2
	exit 1
}

# Keep native Git private to this repository facade. Agent-facing PATH may
# intentionally resolve `git` to a refusal shim; every backend call uses the
# pinned executable selected above instead.
git() { "$git_bin" "$@"; }

[[ "$push_timeout" =~ ^[1-9][0-9]*$ ]] || {
	printf 'dotfiles-vcs: DOTFILES_GIT_PUSH_TIMEOUT must be a positive integer\n' >&2
	exit 1
}

die() {
	printf 'dotfiles-vcs: %s\n' "$*" >&2
	exit 1
}
run_remote() { GIT_SSH_COMMAND="$remote_ssh" "$@"; }
run_forgejo_https() {
	# Use a per-invocation credential.helper rather than GIT_ASKPASS.
	# GIT_ASKPASS is silently ignored by git >= 2.46 when GIT_TERMINAL_PROMPT=0,
	# because git then refuses to consult any askpass mechanism and demands a
	# tty (see mhugo/dotfiles#14). `git -c credential.helper=<expr>` sets the
	# helper for this single invocation only; no .git/config mutation, no
	# cleanup needed.
	#
	# Token source precedence:
	#   1. OpenBao at kv/forgejo/cli-mhugo:token (canonical; preferred)
	#   2. ~/.config/tea/config.yml (legacy fallback; matches mhugo/dotfiles#14
	#      pre-fix behavior so older agents keep working without bao access)
	local helper result=0 token
	if token="$(BAO_ADDR="''${BAO_ADDR:-http://vault-active.vault.svc.cluster.local:8200}" command -v bao >/dev/null 2>&1 && bao kv get -field=token kv/forgejo/cli-mhugo 2>/dev/null)"; then
		:
	elif token="$(awk '/^[[:space:]]+token:/ {print $2; exit}' "$HOME/.config/tea/config.yml" 2>/dev/null)"; then
		:
	fi
	[[ -n "$token" ]] || die 'run_forgejo_https: no token found in bao kv/forgejo/cli-mhugo:token nor in ~/.config/tea/config.yml'
	helper=$(printf '!printf "username=mhugo\\npassword=%%q\\n\\n" "%s"' "$token")
	# Inject the credential helper right after the git binary so that
	# callers can write either `run_forgejo_https git -C root fetch ...`
	# or `run_forgejo_https timeout ... git_bin -C root fetch ...`.
	# Everything before the first non-flag, non-option argument is left
	# untouched; the helper is inserted right after the binary that ends
	# in `git` (with optional `.exe`/version suffix).
	# Find the git binary (first arg matching *git) and insert
	# -c credential.helper=<helper> immediately after it. Skip the
	# original binary path; we will invoke $git_bin directly so the
	# caller does not have to worry about whether they wrote the
	# literal keyword `git` or a full path to the binary.
	# Split $@ into the prefix (e.g. `timeout 300`) that runs *before*
	# git, and the suffix (e.g. `-C root fetch ...`) that runs after.
	# The git binary itself is dropped because we call $git_bin directly
	# with -c credential.helper=<helper> injected as its first arg.
	local prefix=() suffix=() saw_git=0 i
	for i in "$@"; do
		if [[ "$saw_git" -eq 0 && "$i" == *git && "$i" != -* ]]; then
			saw_git=1
			continue
		fi
		if [[ "$saw_git" -eq 0 ]]; then
			prefix+=("$i")
		else
			suffix+=("$i")
		fi
	done
	[[ "$saw_git" -eq 1 ]] || die "run_forgejo_https: no git binary in args: $*"
	# An inherited helper can answer first and silently shadow this token. Clear
	# the configured helper chain, then install exactly this invocation's helper.
	"${prefix[@]}" "$git_bin" -c credential.helper= -c "credential.helper=$helper" "${suffix[@]}" || result=$?
	return "$result"
}
# Contract for the forgejo-https credential helper: this expression must
# print exactly two lines (username, password) on git's credential prompt,
# and the password line must match the token stored in bao (preferred) or
# ~/.config/tea/config.yml (fallback). See mhugo/dotfiles#14. Run via
# `repo vcs test` or as part of `repo check`. Git invokes
# `credential.helper` as `sh -c '<expr>'` with the credential prompt on
# stdin; replicate that exactly here.
forgejo_https_credential_helper_check() {
	# Build the same credential.helper expression that run_forgejo_https
	# uses, then exercise it via `git credential fill`, the same machinery
	# git uses for https transports. The helper should emit username and
	# password; we extract the password line and compare with the expected.
	local expected actual helper token
	if command -v bao >/dev/null 2>&1; then
		token="$(bao kv get -format=json kv/forgejo/cli-mhugo 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); data=d.get('data',{}); print((data.get('data') or data).get('token',''))" 2>/dev/null || true)"
	fi
	if [[ -z "$token" ]] && [[ -f "$HOME/.config/tea/config.yml" ]]; then
		token="$(awk '/^[[:space:]]+token:[[:space:]]/ {print $2; exit}' "$HOME/.config/tea/config.yml" 2>/dev/null || true)"
	fi
	[[ -n "$token" ]] || die 'forgejo-https credential helper: no token found in bao or tea config'
	helper=$(printf '!printf "username=mhugo\\npassword=%%q\\n\\n" "%s"' "$token")
	# Use git credential fill to exercise the helper exactly the way an
	# https transport would. The helper expression embeds the literal token
	# via %s at build time, so the child shell that git spawns does not
	# need to expand any variables.
	local fill_output
	fill_output="$(printf 'protocol=https\nhost=git.centralcloud.net\n\n' | git -c credential.helper= -c "credential.helper=$helper" credential fill 2>/dev/null || true)"
	actual="$(printf '%s' "$fill_output" | awk -F= '/^password=/{print $2; exit}')"
	expected="$(printf '%q' "$token")"
	[[ "$actual" == "$expected" ]] || die 'forgejo-https credential helper: helper password does not match the selected credential source'
	printf 'forgejo-https credential helper: ok\n'
}
fetch_forgejo_main() {
	run_forgejo_https git -C "$1" fetch "$forgejo_https_url" '+refs/heads/main:refs/remotes/origin/main'
}
fetch_forgejo_pruned() {
	run_forgejo_https git -C "$1" fetch --prune "$forgejo_https_url" '+refs/heads/*:refs/remotes/origin/*'
}
valid_name() { [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || die "invalid worktree name: $1"; }
# Leftover refs are namespaced (chore/*, fix/*, …). The slash keeps main and
# other checkout-local short names out of this retire surface.
valid_leftover_ref() {
	[[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*/[A-Za-z0-9][A-Za-z0-9._/-]*$ ]] || die "invalid leftover ref: $1"
	case "$1" in
	main | HEAD | origin/main) die 'branch-retire refuses main/HEAD' ;;
	esac
}
leftover_ref_checked_out() {
	local ref="$1"
	git -C "$root" worktree list --porcelain | awk -v want="refs/heads/$ref" '
		$1 == "branch" && $2 == want { found = 1 }
		END { exit !found }
	'
}

command_name="${1:-}"
shift || true
# Resolve a worktree's branch, tolerating the current worktree/ prefix and the
# legacy codex/ one. The prefix was agent-specific until 2026-08-12: every agent
# using this facade was forced onto a codex/* branch whichever agent it was.
task_branch_for() {
	local name="$1"
	local path="$HOME/.dotfiles-worktrees/$name"
	local live_branch=""
	if git -C "$root" show-ref --verify --quiet "refs/heads/worktree/$name"; then
		printf 'worktree/%s' "$name"
		return
	fi
	if git -C "$root" show-ref --verify --quiet "refs/heads/codex/$name"; then
		printf 'codex/%s' "$name"
		return
	fi
	if [[ -d "$path" ]]; then
		live_branch="$(git -C "$path" symbolic-ref --quiet --short HEAD || true)"
	fi
	[[ -n "$live_branch" ]] || die "no task branch for worktree: $name (looked for worktree/$name, codex/$name, and $path HEAD)"
	printf '%s' "$live_branch"
}

case "$command_name" in
status) git -C "$root" status "$@" ;;
diff) git -C "$root" diff "$@" ;;
log) git -C "$root" log "$@" ;;
show)
	[[ $# -eq 1 ]] || die 'show requires one revision'
	git -C "$root" show "$1"
	;;
worktree-list) git -C "$root" worktree list --porcelain ;;
fetch)
	[[ $# -eq 0 ]] || die 'fetch takes no arguments'
	fetch_forgejo_pruned "$root"
	;;
rebase)
	if [[ "${1:-}" == '--continue' ]]; then
		[[ $# -ge 2 ]] || die 'rebase --continue requires at least one resolved path'
		rebase_dir="$(git -C "$root" rev-parse --git-path rebase-merge)"
		[[ -d "$rebase_dir" ]] || die 'no rebase is in progress'
		shift
		for resolved_path in "$@"; do
			case "$resolved_path" in
			/* | *'..'*) die 'rebase --continue requires repository-relative paths' ;;
			esac
			[[ -f "$root/$resolved_path" ]] || die "resolved path is not a file: $resolved_path"
			if grep -Eq '^(<<<<<<<|=======|>>>>>>>|\|\|\|\|\|\|\|)' "$root/$resolved_path"; then
				die "conflict markers remain in: $resolved_path"
			fi
		done
		git -C "$root" add -- "$@"
		[[ -z "$(git -C "$root" diff --name-only --diff-filter=U)" ]] || die 'other unresolved rebase conflicts remain'
		GIT_EDITOR=true git -C "$root" rebase --continue
		exit 0
	fi
	[[ $# -eq 1 ]] || die 'rebase requires one revision'
	branch="$(git -C "$root" symbolic-ref --quiet --short HEAD)" || die 'detached HEAD cannot be rebased'
	case "$branch" in
	worktree/* | codex/*) ;;
	*) die 'rebase requires a worktree/* branch (codex/* still accepted for branches created before the rename)' ;;
	esac
	[[ -z "$(git -C "$root" status --porcelain)" ]] || die 'working tree is not clean'
	git -C "$root" rebase "$1"
	;;
sync-main)
	# mhugo/dotfiles#13: when several agents share the primary checkout
	# concurrently, primary main may accumulate local commits authored by a
	# sibling session. The cherry-pick-equivalence guard is correct (we must
	# not silently reset away a sibling's commits) but the previous error
	# message gave no recovery path. Print a divergence report naming each
	# offending commit and pointing at three concrete resolutions so the
	# operator can act without reading the script.
	divergence_only=0
	while (($#)); do
		case "$1" in
		--divergence-only)
			divergence_only=1
			shift
			;;
		*) die "sync-main: unknown argument: $1 (supported: --divergence-only)" ;;
		esac
	done
	primary="$HOME/.dotfiles"
	[[ -d "$primary" ]] || die "primary checkout is missing: $primary"
	branch="$(git -C "$primary" symbolic-ref --quiet --short HEAD)" || die 'primary checkout is detached'
	[[ "$branch" == main ]] || die 'primary checkout is not on main'
	[[ -z "$(git -C "$primary" status --porcelain)" ]] || die 'primary checkout is not clean'
	fetch_forgejo_main "$primary"
	if [[ "$(git -C "$primary" rev-parse main)" == "$(git -C "$primary" rev-parse origin/main)" ]]; then
		printf 'synced=main revision=%s already_current=true\n' "$(git -C "$primary" rev-parse main)"
		exit 0
	fi
	# Local main is behind or ahead of origin/main. If local has zero
	# local-only commits relative to origin/main, a hard reset fast-forwards
	# cleanly. If local has local-only commits, list them and stop; the
	# operator picks one of three resolutions below.
	local_only="$(git -C "$primary" cherry origin/main main 2>/dev/null | awk '/^\+/ {print $2}')"
	count=0
	total="$(printf '%s\n' "$local_only" | wc -l | tr -d ' ')"
	author=
	subject=
	files=
	sha=
	if [[ -z "$local_only" ]]; then
		git -C "$primary" reset --hard origin/main
		printf 'synced=main revision=%s fast_forward=true\n' "$(git -C "$primary" rev-parse main)"
		exit 0
	fi
	# Divergence report. List every local-only commit's short sha + author
	# + subject so the operator can identify whose work it is. cap at 25
	# to keep the output bounded; cap can be revisited if it bites.
	printf 'sync-main: primary main has %s local commit(s) not patch-equivalent to upstream\n' "$total" >&2
	printf 'divergence=primary_main ahead_of_upstream commits=%s\n' "$total" >&2
	while IFS= read -r sha; do
		count=$((count + 1))
		[[ $count -gt 25 ]] && {
			printf '  ... %s more (truncated; inspect with: git log origin/main..main)\n' "$((total - 25))" >&2
			break
		}
		author="$(git -C "$primary" log -1 --format='%an <%ae>' "$sha" 2>/dev/null || echo '?')"
		subject="$(git -C "$primary" log -1 --format='%s' "$sha" 2>/dev/null || echo '?')"
		# Files touched (capped at 5 to keep the line bounded).
		files="$(git -C "$primary" show --name-only --format='' "$sha" 2>/dev/null | head -5 | paste -sd, -)"
		printf '  local_commit=%s author="%s" subject=%q files=%s\n' \
			"$(printf '%s' "$sha" | cut -c1-12)" "$author" "$subject" "$files" >&2
	done <<<"$local_only"
	if [[ "$divergence_only" -eq 1 ]]; then
		exit 2
	fi
	cat >&2 <<'DIV_HELP'
recovery:
  - if these commits are yours and not yet on a lane:
      repo vcs worktree-create <lane-name> main    # lifts your commits onto a worktree/* branch
      # then re-run sync-main from the canonical primary
  - if these commits are yours and you want them kept on main:
      repo vcs converge-main                       # rebases main onto origin/main keeping your commits
  - if these commits belong to a sibling agent:
      coordinate with them to push their commits to a lane first, then sync-main
      (raw git: git fetch origin main && git merge --no-ff origin/main)
DIV_HELP
	die 'sync-main refused: primary main has unpushed local commits (see recovery above)'
	;;
converge-main)
	# A diverged main -- local commits AND remote commits -- has no other route
	# here: `rebase` refuses anything but a worktree/* branch, and `sync-main`
	# is a hard reset that deliberately dies rather than discard local work.
	# This rebases main onto origin/main, keeping the local commits.
	[[ $# -eq 0 ]] || die 'converge-main takes no arguments'
	branch="$(git -C "$root" symbolic-ref --quiet --short HEAD)" || die 'detached HEAD cannot be converged'
	[[ "$branch" == main ]] || die "converge-main requires the main branch (on: $branch)"
	[[ -z "$(git -C "$root" status --porcelain)" ]] || die "working tree is not clean; commit first: repo vcs describe '<message>'"
	fetch_forgejo_main "$root"
	before="$(git -C "$root" rev-parse main)"
	if [[ "$before" == "$(git -C "$root" rev-parse origin/main)" ]]; then
		printf 'converged=main revision=%s already_current=true\n' "$before"
		exit 0
	fi
	if ! git -C "$root" cherry origin/main main | grep -q '^+'; then
		die 'main has no local-only commits; fast-forward instead: repo vcs sync-main'
	fi
	if ! git -C "$root" rebase origin/main; then
		die "rebase stopped on conflicts; resolve each file then: repo vcs rebase --continue <paths>  (abandon with: git -C $root rebase --abort, recover tip with: git -C $root reset --hard $before)"
	fi
	printf 'converged=main before=%s after=%s onto=%s\n' "$before" "$(git -C "$root" rev-parse main)" "$(git -C "$root" rev-parse origin/main)"
	;;
describe)
	if [[ "${1:-}" == '--help' ]]; then
		[[ $# -eq 1 ]] || die 'describe --help takes no arguments'
		printf 'usage: repo vcs describe <message>\n'
		exit 0
	fi
	[[ $# -eq 1 ]] || die 'describe requires one message'
	git -C "$root" add --all
	git -C "$root" diff --cached --quiet && die 'no changes to describe'
	git -C "$root" commit -m "$1"
	;;
amend)
	[[ $# -eq 1 ]] || die 'amend requires one message'
	branch="$(git -C "$root" symbolic-ref --quiet --short HEAD)" || die 'detached HEAD cannot be amended'
	case "$branch" in
	worktree/* | codex/*) ;;
	*) die 'amend requires a worktree/* branch (codex/* still accepted for branches created before the rename)' ;;
	esac
	fetch_forgejo_pruned "$root"
	published_refs="$(git -C "$root" for-each-ref --contains HEAD --format='%(refname)' refs/remotes/origin)"
	[[ -z "$published_refs" ]] || die "amend requires an unpushed task commit; present in $published_refs"
	# --only preserves both staged and unstaged work while correcting only the
	# unpushed HEAD message; it is intentionally not a content rewrite surface.
	git -C "$root" commit --amend --only -m "$1"
	;;
push)
	branch="${1:-main}"
	[[ "$branch" == main ]] || die 'publication owns only main'
	[[ -z "$(git -C "$root" status --porcelain)" ]] || die 'working tree is not clean'
	fetch_forgejo_main "$root"
	git -C "$root" merge-base --is-ancestor origin/main main || die 'main does not contain origin/main'
	(cd "$root" && just check)
	# Forgejo synchronously mirrors this repository to GitHub. Publish GitHub
	# first so Forgejo's post-receive mirror is already converged and cannot
	# hold the client until the publication timeout.
	GIT_SSH_COMMAND="$remote_ssh" timeout "$push_timeout" "$git_bin" -C "$root" push "$github_url" main
	run_forgejo_https timeout "$push_timeout" "$git_bin" -C "$root" push "$forgejo_https_url" main
	local_revision="$(git -C "$root" rev-parse main)"
	forgejo_revision="$(run_forgejo_https timeout 30 "$git_bin" -C "$root" ls-remote "$forgejo_https_url" refs/heads/main | cut -f1)"
	github_revision="$(GIT_SSH_COMMAND="$remote_ssh" timeout 30 "$git_bin" -C "$root" ls-remote "$github_url" refs/heads/main | cut -f1)"
	[[ "$local_revision" == "$forgejo_revision" ]] || die "Forgejo remote readback mismatch"
	[[ "$local_revision" == "$github_revision" ]] || die "GitHub remote readback mismatch"
	printf 'published=main revision=%s forgejo_readback=true github_readback=true\n' "$local_revision"
	;;
push-github)
	branch="${1:-main}"
	[[ "$branch" == main ]] || die 'publication owns only main'
	[[ -z "$(git -C "$root" status --porcelain)" ]] || die 'working tree is not clean'
	(cd "$root" && just check)
	GIT_SSH_COMMAND="$remote_ssh" timeout "$push_timeout" "$git_bin" -C "$root" push "$github_url" main
	local_revision="$(git -C "$root" rev-parse main)"
	github_revision="$(GIT_SSH_COMMAND="$remote_ssh" timeout 30 "$git_bin" -C "$root" ls-remote "$github_url" refs/heads/main | cut -f1)"
	[[ "$local_revision" == "$github_revision" ]] || die "GitHub remote readback mismatch"
	printf 'published=main revision=%s github_readback=true forgejo_pending=true\n' "$local_revision"
	;;
land)
	[[ $# -eq 0 ]] || die 'land takes no arguments'
	[[ -z "$(git -C "$root" status --porcelain)" ]] || die 'working tree is not clean'
	branch="$(git -C "$root" symbolic-ref --quiet --short HEAD)" || die 'detached HEAD cannot be landed'
	case "$branch" in
	worktree/* | codex/*) ;;
	*) die 'land requires a worktree/* branch (codex/* still accepted for branches created before the rename)' ;;
	esac
	fetch_forgejo_main "$root"
	git -C "$root" merge-base --is-ancestor origin/main HEAD || die 'task branch does not contain origin/main'
	"$root/scripts/repo-check.sh"
	# Keep the server-side Forgejo mirror a no-op during its post-receive hook.
	GIT_SSH_COMMAND="$remote_ssh" timeout "$push_timeout" "$git_bin" -C "$root" push "$github_url" HEAD:main
	run_forgejo_https timeout "$push_timeout" "$git_bin" -C "$root" push "$forgejo_https_url" HEAD:main
	local_revision="$(git -C "$root" rev-parse HEAD)"
	forgejo_revision="$(run_forgejo_https timeout 30 "$git_bin" -C "$root" ls-remote "$forgejo_https_url" refs/heads/main | cut -f1)"
	github_revision="$(GIT_SSH_COMMAND="$remote_ssh" timeout 30 "$git_bin" -C "$root" ls-remote "$github_url" refs/heads/main | cut -f1)"
	[[ "$local_revision" == "$forgejo_revision" ]] || die 'Forgejo remote readback mismatch'
	[[ "$local_revision" == "$github_revision" ]] || die 'GitHub remote readback mismatch'
	fetch_forgejo_main "$root"
	printf 'landed=main revision=%s forgejo_readback=true github_readback=true source=%s\n' "$local_revision" "$branch"
	;;
worktree-create)
	[[ $# -eq 2 ]] || die 'worktree-create requires name and revision'
	name="$1"
	revision="$2"
	valid_name "$name"
	path="$HOME/.dotfiles-worktrees/$name"
	[[ ! -e "$path" ]] || die "worktree path exists: $path"
	git -C "$root" worktree add -b "worktree/$name" "$path" "$revision"
	;;
worktree-drop)
	[[ $# -eq 1 ]] || die 'worktree-drop requires name'
	name="$1"
	valid_name "$name"
	path="$HOME/.dotfiles-worktrees/$name"
	[[ "$(realpath "$root")" != "$(realpath "$path")" ]] || die 'cannot drop current worktree'
	git -C "$root" worktree list --porcelain | awk '/^worktree / {print substr($0,10)}' | grep -Fxq "$path" || die 'worktree is not registered'
	[[ -z "$(git -C "$path" status --porcelain)" ]] || die 'worktree is dirty'
	if ! git -C "$root" merge-base --is-ancestor "$(task_branch_for "$name")" main; then
		fetch_forgejo_main "$root"
		git -C "$root" merge-base --is-ancestor "$(task_branch_for "$name")" origin/main || die 'worktree branch is not integrated into main'
	fi
	git -C "$root" worktree remove "$path"
	# The primary checkout may intentionally lag origin/main. Integration was
	# proven above, so delete the local task ref without re-checking stale main.
	git -C "$root" branch -D "$(task_branch_for "$name")"
	;;
worktree-abandon)
	[[ $# -eq 2 ]] || die 'worktree-abandon requires name and discard-unintegrated'
	name="$1"
	confirmation="$2"
	valid_name "$name"
	[[ "$confirmation" == discard-unintegrated ]] || die 'worktree-abandon requires exact discard-unintegrated confirmation'
	path="$HOME/.dotfiles-worktrees/$name"
	[[ "$(realpath "$root")" != "$(realpath -m "$path")" ]] || die 'cannot abandon current worktree'
	git -C "$root" worktree list --porcelain | awk '/^worktree / {print substr($0,10)}' | grep -Fxq "$path" || die 'worktree is not registered'
	if [[ ! -e "$path" ]]; then
		git -C "$root" worktree prune
		revision="$(git -C "$root" rev-parse "$(task_branch_for "$name")")"
		git -C "$root" branch -D "$(task_branch_for "$name")"
		printf 'abandoned=%s revision=%s clean=true live_process=false missing_path=true\n' "$name" "$revision"
		exit 0
	fi
	[[ -z "$(git -C "$path" status --porcelain)" ]] || die 'worktree is dirty'
	for process_cwd in /proc/[0-9]*/cwd; do
		resolved_cwd="$(readlink "$process_cwd" 2>/dev/null || true)"
		case "$resolved_cwd" in
		"$path" | "$path"/*) die "worktree is owned by a live process: $process_cwd -> $resolved_cwd" ;;
		esac
	done
	revision="$(git -C "$root" rev-parse "$(task_branch_for "$name")")"
	git -C "$root" worktree remove "$path"
	git -C "$root" branch -D "$(task_branch_for "$name")"
	printf 'abandoned=%s revision=%s clean=true live_process=false\n' "$name" "$revision"
	;;
branch-retire)
	[[ $# -ge 1 && $# -le 2 ]] || die 'branch-retire requires a leftover ref and optional --apply'
	ref="$1"
	apply="${2:-}"
	valid_leftover_ref "$ref"
	[[ -z "$apply" || "$apply" == --apply ]] || die 'branch-retire accepts only --apply after the leftover ref'
	local_present=false
	if git -C "$root" show-ref --verify --quiet "refs/heads/$ref"; then
		local_present=true
	fi
	remote_tracking=false
	if git -C "$root" show-ref --verify --quiet "refs/remotes/origin/$ref"; then
		remote_tracking=true
	fi
	[[ "$local_present" == true || "$remote_tracking" == true ]] || die "no leftover ref: $ref"
	leftover_ref_checked_out "$ref" && die "leftover ref is checked out: $ref"
	if [[ "$local_present" == true ]]; then
		revision="$(git -C "$root" rev-parse "refs/heads/$ref")"
	else
		revision="$(git -C "$root" rev-parse "refs/remotes/origin/$ref")"
	fi
	if [[ "$apply" != --apply ]]; then
		printf 'dry-run leftover=%s revision=%s local=%s remote_tracking=%s apply=false\n' "$ref" "$revision" "$local_present" "$remote_tracking"
		exit 0
	fi
	# Pruned Forgejo fetch is the live remote proof. A failed ls-remote must
	# not look like "absent" when origin/ still names the leftover.
	fetch_forgejo_pruned "$root"
	forgejo_present=false
	if git -C "$root" show-ref --verify --quiet "refs/remotes/origin/$ref"; then
		forgejo_present=true
	fi
	github_present=false
	github_probe="$(GIT_SSH_COMMAND="$remote_ssh" timeout 30 "$git_bin" -C "$root" ls-remote "$github_url" "refs/heads/$ref" || true)"
	if printf '%s\n' "$github_probe" | grep -Fq "refs/heads/$ref"; then
		github_present=true
	fi
	if [[ "$forgejo_present" == true ]]; then
		run_forgejo_https timeout "$push_timeout" "$git_bin" -C "$root" push "$forgejo_https_url" ":refs/heads/$ref"
	fi
	if [[ "$github_present" == true ]]; then
		GIT_SSH_COMMAND="$remote_ssh" timeout "$push_timeout" "$git_bin" -C "$root" push "$github_url" ":refs/heads/$ref"
	fi
	if [[ "$local_present" == true ]]; then
		git -C "$root" branch -D "$ref"
		git -C "$root" show-ref --verify --quiet "refs/heads/$ref" && die "local leftover ref still present: $ref"
	fi
	if [[ "$forgejo_present" == true ]]; then
		fetch_forgejo_pruned "$root"
		git -C "$root" show-ref --verify --quiet "refs/remotes/origin/$ref" && die "Forgejo leftover ref still present: $ref"
	fi
	printf 'retired leftover=%s revision=%s local=%s forgejo=%s github=%s\n' "$ref" "$revision" "$local_present" "$forgejo_present" "$github_present"
	;;
contract-test)
	[[ $# -eq 0 ]] || die 'contract-test takes no arguments'
	grep -q "mod vcs 'just/vcs.just'" "$root/justfile"
	grep -q 'ControlMaster=no.*ControlPath=none.*ControlPersist=no' "$root/scripts/repo-vcs.sh"
	cfg="$root/config/ssh_config"
	git_host_line="$(awk '/^Host / && /git\.centralcloud\.net/ { print NR; exit }' "$cfg")"
	github_host_line="$(awk '/^Host github\.com$/ { print NR; exit }' "$cfg")"
	star_line="$(awk '/^Host \*$/ { print NR; exit }' "$cfg")"
	[[ -n "$git_host_line" && -n "$star_line" && "$git_host_line" -lt "$star_line" ]] ||
		die 'Forgejo Host stanza must precede Host * so ControlPersist no wins'
	[[ -n "$github_host_line" && "$github_host_line" -lt "$star_line" ]] ||
		die 'github.com Host stanza must precede Host * so ControlPersist no wins'
	persist="$(ssh -G -F "$cfg" -p 2222 git@git.centralcloud.net | awk '/^controlpersist / { print $2; exit }')"
	[[ "$persist" == no ]] || die "expected Forgejo controlpersist no, got ${persist:-empty}"
	master="$(ssh -G -F "$cfg" -p 2222 git@git.centralcloud.net | awk '/^controlmaster / { print $2; exit }')"
	[[ "$master" == no || "$master" == false ]] || die "expected Forgejo controlmaster no, got ${master:-empty}"
	gh_persist="$(ssh -G -F "$cfg" github.com | awk '/^controlpersist / { print $2; exit }')"
	[[ "$gh_persist" == no ]] || die "expected github.com controlpersist no, got ${gh_persist:-empty}"
	other_persist="$(ssh -G -F "$cfg" storagebox | awk '/^controlpersist / { print $2; exit }')"
	[[ "$other_persist" == 600 ]] || die "expected Host * ControlPersist 10m for storagebox, got ${other_persist:-empty}"
	grep -Fq "worktree add -b \"worktree/\$name\"" "$root/scripts/repo-vcs.sh"
	[[ "$push_timeout" == "${DOTFILES_GIT_PUSH_TIMEOUT:-300}" ]] || die 'push timeout configuration mismatch'
	# mhugo/dotfiles#14: GIT_ASKPASS is silently ignored by git >= 2.46 when
	# GIT_TERMINAL_PROMPT=0. run_forgejo_https must use credential.helper
	# instead so the forgejo fetch/push paths work on modern git. The grep
	# below matches the env-var assignment (`GIT_ASKPASS=`) so the in-source
	# comments and the contract-test error message do not trip the check.
	if grep -qE '^\s*[^#]*GIT_ASKPASS=' "$root/scripts/repo-vcs.sh"; then
		die 'run_forgejo_https must not set GIT_ASKPASS; git >= 2.46 ignores it under GIT_TERMINAL_PROMPT=0 (mhugo/dotfiles#14)'
	fi
	if ! grep -q 'credential.helper=' "$root/scripts/repo-vcs.sh"; then
		die 'run_forgejo_https must register a credential.helper (mhugo/dotfiles#14)'
	fi
	# Live smoke: the helper expression must produce the same token tea
	# configured. If tea's token is missing or the awk pattern drifts, this
	# contract fires before any agent attempts a fetch.
	forgejo_https_credential_helper_check
	for recipe in status diff log show worktree-list fetch rebase sync-main describe amend push push-github land worktree-create worktree-drop worktree-abandon branch-retire test; do
		just --justfile "$root/justfile" --summary | tr ' ' '\n' | grep -qx "vcs::$recipe" || die "missing recipe: $recipe"
	done
	printf 'dotfiles VCS contract: ok\n'
	;;
config)
	[[ $# -eq 0 ]] || die 'config takes no arguments'
	printf 'push_timeout=%s\n' "$push_timeout"
	;;
*) die 'usage: repo-vcs.sh {status|diff|log|show|worktree-list|fetch|rebase|sync-main [--divergence-only]|converge-main|describe|amend|push|push-github|land|worktree-create|worktree-drop|worktree-abandon|branch-retire|contract-test|config}' ;;
esac
