#!/usr/bin/env bash
# Purpose: Sole agent-facing VCS facade for dotfiles.
# Contract: Validates the repository root, disables persistent SSH masters,
# verifies before publication, reads back the remote revision, and removes only
# clean registered non-current worktrees.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
remote_ssh="${DOTFILES_GIT_SSH_COMMAND:-ssh -o ControlMaster=no -o ControlPath=none -o ControlPersist=no}"
forgejo_https_url="https://git.infra.centralcloud.com/mhugo/dotfiles.git"
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
	local askpass
	askpass="$(mktemp)"
	trap 'rm -f -- "$askpass"' RETURN
	cat >"$askpass" <<'ASKPASS'
#!/usr/bin/env bash
case "$1" in
*Username*) printf '%s\n' mhugo ;;
*Password*) awk '/^[[:space:]]+token:/ { print $2; exit }' "$HOME/.config/tea/config.yml" ;;
*) exit 1 ;;
esac
ASKPASS
	chmod 700 "$askpass"
	GIT_ASKPASS="$askpass" GIT_TERMINAL_PROMPT=0 "$@"
}
valid_name() { [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || die "invalid worktree name: $1"; }

command_name="${1:-}"
shift || true
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
	run_remote git -C "$root" fetch origin --prune
	;;
rebase)
	[[ $# -eq 1 ]] || die 'rebase requires one revision'
	branch="$(git -C "$root" symbolic-ref --quiet --short HEAD)" || die 'detached HEAD cannot be rebased'
	[[ "$branch" == codex/* ]] || die 'rebase requires a codex/* task branch'
	[[ -z "$(git -C "$root" status --porcelain)" ]] || die 'working tree is not clean'
	git -C "$root" rebase "$1"
	;;
describe)
	[[ $# -eq 1 ]] || die 'describe requires one message'
	git -C "$root" add --all
	git -C "$root" diff --cached --quiet && die 'no changes to describe'
	git -C "$root" commit -m "$1"
	;;
push)
	branch="${1:-main}"
	[[ "$branch" == main ]] || die 'publication owns only main'
	[[ -z "$(git -C "$root" status --porcelain)" ]] || die 'working tree is not clean'
	run_remote git -C "$root" fetch origin main
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
	[[ "$branch" == codex/* ]] || die 'land requires a codex/* task branch'
	run_remote git -C "$root" fetch origin main
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
	run_remote git -C "$root" fetch origin main
	printf 'landed=main revision=%s forgejo_readback=true github_readback=true source=%s\n' "$local_revision" "$branch"
	;;
worktree-create)
	[[ $# -eq 2 ]] || die 'worktree-create requires name and revision'
	name="$1"
	revision="$2"
	valid_name "$name"
	path="$HOME/.dotfiles-worktrees/$name"
	[[ ! -e "$path" ]] || die "worktree path exists: $path"
	git -C "$root" worktree add -b "codex/$name" "$path" "$revision"
	;;
worktree-drop)
	[[ $# -eq 1 ]] || die 'worktree-drop requires name'
	name="$1"
	valid_name "$name"
	path="$HOME/.dotfiles-worktrees/$name"
	[[ "$(realpath "$root")" != "$(realpath "$path")" ]] || die 'cannot drop current worktree'
	git -C "$root" worktree list --porcelain | awk '/^worktree / {print substr($0,10)}' | grep -Fxq "$path" || die 'worktree is not registered'
	[[ -z "$(git -C "$path" status --porcelain)" ]] || die 'worktree is dirty'
	if ! git -C "$root" merge-base --is-ancestor "codex/$name" main; then
		run_remote git -C "$root" fetch origin main
		git -C "$root" merge-base --is-ancestor "codex/$name" origin/main || die 'worktree branch is not integrated into main'
	fi
	git -C "$root" worktree remove "$path"
	# The primary checkout may intentionally lag origin/main. Integration was
	# proven above, so delete the local task ref without re-checking stale main.
	git -C "$root" branch -D "codex/$name"
	;;
contract-test)
	[[ $# -eq 0 ]] || die 'contract-test takes no arguments'
	grep -q "mod vcs 'just/vcs.just'" "$root/justfile"
	grep -q 'ControlMaster=no.*ControlPath=none.*ControlPersist=no' "$root/scripts/repo-vcs.sh"
	grep -Fq "branch -D \"codex/\$name\"" "$root/scripts/repo-vcs.sh"
	[[ "$push_timeout" == "${DOTFILES_GIT_PUSH_TIMEOUT:-300}" ]] || die 'push timeout configuration mismatch'
	for recipe in status diff log show worktree-list fetch rebase describe push push-github worktree-create worktree-drop test; do
		just --justfile "$root/justfile" --summary | tr ' ' '\n' | grep -qx "vcs::$recipe" || die "missing recipe: $recipe"
	done
	printf 'dotfiles VCS contract: ok\n'
	;;
config)
	[[ $# -eq 0 ]] || die 'config takes no arguments'
	printf 'push_timeout=%s\n' "$push_timeout"
	;;
*) die 'usage: repo-vcs.sh {status|diff|log|show|worktree-list|fetch|rebase|describe|push|push-github|land|worktree-create|worktree-drop|contract-test|config}' ;;
esac
