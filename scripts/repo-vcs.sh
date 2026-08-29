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
	local askpass result=0
	askpass="$(mktemp)"
	cat >"$askpass" <<'ASKPASS'
#!/usr/bin/env bash
case "$1" in
*Username*) printf '%s\n' mhugo ;;
*Password*) awk '/^[[:space:]]+token:/ { print $2; exit }' "$HOME/.config/tea/config.yml" ;;
*) exit 1 ;;
esac
ASKPASS
	chmod 700 "$askpass"
	GIT_ASKPASS="$askpass" GIT_TERMINAL_PROMPT=0 "$@" || result=$?
	rm -f -- "$askpass"
	return "$result"
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
	[[ $# -eq 0 ]] || die 'sync-main takes no arguments'
	primary="$HOME/.dotfiles"
	[[ -d "$primary" ]] || die "primary checkout is missing: $primary"
	branch="$(git -C "$primary" symbolic-ref --quiet --short HEAD)" || die 'primary checkout is detached'
	[[ "$branch" == main ]] || die 'primary checkout is not on main'
	[[ -z "$(git -C "$primary" status --porcelain)" ]] || die 'primary checkout is not clean'
	fetch_forgejo_main "$primary"
	if git -C "$primary" cherry origin/main main | grep -q '^+'; then
		die 'primary main has local commits that are not patch-equivalent upstream'
	fi
	git -C "$primary" reset --hard origin/main
	[[ "$(git -C "$primary" rev-parse main)" == "$(git -C "$primary" rev-parse origin/main)" ]] || die 'primary main did not converge'
	printf 'synced=main revision=%s patch_equivalent=true\n' "$(git -C "$primary" rev-parse main)"
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
	for recipe in status diff log show worktree-list fetch rebase sync-main describe amend push push-github land worktree-create worktree-drop worktree-abandon branch-retire test; do
		just --justfile "$root/justfile" --summary | tr ' ' '\n' | grep -qx "vcs::$recipe" || die "missing recipe: $recipe"
	done
	printf 'dotfiles VCS contract: ok\n'
	;;
config)
	[[ $# -eq 0 ]] || die 'config takes no arguments'
	printf 'push_timeout=%s\n' "$push_timeout"
	;;
*) die 'usage: repo-vcs.sh {status|diff|log|show|worktree-list|fetch|rebase|sync-main|describe|amend|push|push-github|land|worktree-create|worktree-drop|worktree-abandon|branch-retire|contract-test|config}' ;;
esac
