# agent-direnv-prebuilt-apply.sh — apply host-published prebuilt direnv export dumps (no nix eval).
# Producer: agent-direnv-publish on cc-se-sto-devbox-01 → $XDG_RUNTIME_DIR/agent-direnv/*.{bash,meta}
# Mirrors agent_direnv_try_shared_dump in hosts/_shared/nix-direnv-3.2.0.nix for
# BASH_ENV / agent-direnv cache sync when /etc/direnv is not on the load path.

_agent_direnv_prebuilt_strip_helper() {
	local candidate
	for candidate in \
		"${STRIP_AGENT_DIRENV_SNAPSHOT:-}" \
		/srv/infra/scripts/strip-agent-direnv-snapshot \
		"$(command -v strip-agent-direnv-snapshot 2>/dev/null)" \
		/run/current-system/sw/bin/strip-agent-direnv-snapshot; do
		[ -n "$candidate" ] && [ -x "$candidate" ] && {
			printf '%s\n' "$candidate"
			return 0
		}
	done
	return 1
}

_agent_direnv_prebuilt_schema_ok() {
	case "$1" in
	centralcloud.agent-direnv/prebuilt | centralcloud.agent-direnv/v2) return 0 ;;
	*) return 1 ;;
	esac
}

# Lane-keyed CARGO_TARGET_DIR and direnv_layout_dir after a canonical dump applies
# to a different checkout path (bind-in-publisher; see Engine ADR se-direnv-workspace-bind).
_agent_direnv_bind_engine_workspace() {
	local root="$1"
	local bind_script="$root/.nix/se-direnv-bind-workspace.sh"
	[ -f "$bind_script" ] || return 0
	# shellcheck disable=SC1090
	. "$bind_script" "$root"
}

_agent_direnv_prebuilt_header_matches() {
	local header="$1" repo="$2" key="$3" system="$4" devshell="$5"
	case "$header" in
	"# agent-direnv-prebuilt repo=$repo key=$key system=$system devshell=$devshell rebind="*) return 0 ;;
	"# agent-direnv-v2 repo=$repo key=$key system=$system devshell=$devshell rebind="*) return 0 ;;
	*) return 1 ;;
	esac
}

_agent_direnv_prebuilt_apply_dump() {
	local root="$1" repo="$2" consumer_kind="$3" identity_root="$4" dump="$5"
	local apply_dump strip_helper

	strip_helper="$(_agent_direnv_prebuilt_strip_helper)" || return 1
	[ -f "$dump" ] && [ -r "$dump" ] || return 1

	apply_dump="$dump"
	if [ "$consumer_kind" = lane ] && [ "$identity_root" != "$root" ]; then
		apply_dump="$(mktemp "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/agent-direnv/.lane-rebind.XXXXXX")" || return 1
		sed "s|${identity_root}|${root}|g" "$dump" >"$apply_dump" || {
			rm -f "$apply_dump"
			return 1
		}
	fi

	if ! "$strip_helper" --validate --admit-root "$root" --repository "$repo" --bash "$(command -v bash)" <"$apply_dump" 2>/dev/null; then
		[ "$apply_dump" != "$dump" ] && rm -f "$apply_dump"
		return 1
	fi

	# shellcheck disable=SC1090
	. "$apply_dump" || {
		[ "$apply_dump" != "$dump" ] && rm -f "$apply_dump"
		return 1
	}
	[ "$apply_dump" != "$dump" ] && rm -f "$apply_dump"
	unset DIRENV_DIFF DIRENV_WATCHES
	return 0
}

_agent_direnv_prebuilt_newest_dump_for_repo() {
	local repo="$1"
	local meta m meta_repo expires_at created now best_created=0 best_dump=
	now="$(date +%s)"
	for meta in "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/agent-direnv"/*.meta; do
		[ -f "$meta" ] && [ -r "$meta" ] || continue
		meta_repo="$(awk -F= '$1 == "repo" {print $2; exit}' "$meta")"
		[ "$meta_repo" = "$repo" ] || continue
		expires_at="$(awk -F= '$1 == "expires_at" {print $2; exit}' "$meta")"
		case "$expires_at" in
		'' | *[!0-9]*) continue ;;
		esac
		[ "$now" -le "$expires_at" ] || continue
		created="$(awk -F= '$1 == "created_at" {print $2; exit}' "$meta")"
		case "$created" in
		'' | *[!0-9]*) continue ;;
		esac
		m="${meta%.meta}.bash"
		[ -f "$m" ] && [ -r "$m" ] || continue
		if [ "$created" -gt "$best_created" ]; then
			best_created=$created
			best_dump=$m
		fi
	done
	[ -n "$best_dump" ] || return 1
	printf '%s\n' "$best_dump"
}

# The repository root a direnv-instant dump was produced for.
#
# direnv-instant's cache directory name is a Rust DefaultHasher over the
# .envrc directory, and DefaultHasher's output is not stable across Rust
# releases, so the shell side cannot recompute it. The only attribution the
# dump itself carries is direnv's own DIRENV_DIR, which names the directory
# whose .envrc produced it. A dump without that marker cannot be attributed
# to any root and must never be applied to one.
_direnv_instant_recorded_root() {
	local env_file="$1" raw
	[ -f "$env_file" ] && [ -r "$env_file" ] || return 1
	raw="$(grep -o "export DIRENV_DIR=\$'[^']*'" -- "$env_file" 2>/dev/null | head -1)" || true
	if [ -z "$raw" ]; then
		raw="$(grep -o 'export DIRENV_DIR="[^"]*"' -- "$env_file" 2>/dev/null | head -1)" || true
	fi
	[ -n "$raw" ] || return 1
	raw="${raw#export DIRENV_DIR=\$'}"
	raw="${raw%\'}"
	raw="${raw#export DIRENV_DIR=\"}"
	raw="${raw%\"}"
	# direnv marks an evaluated-but-not-loaded directory with a leading '-'.
	raw="${raw#-}"
	[ -n "$raw" ] || return 1
	printf '%s\n' "$raw"
}

# direnv-instant's cached environment file, when one exists for this root.
#
# direnv-instant runs `direnv export` in a background daemon and caches the
# result at $XDG_CACHE_HOME/direnv-instant/<hash>/env. The <hash> is a Rust
# DefaultHasher over the .envrc directory, and DefaultHasher's output is not
# stable across Rust releases, so the shell side cannot recompute it. The
# reliable source is the path the shell hook already exports:
# __DIRENV_INSTANT_ENV_FILE.
#
# When that variable is absent (a non-interactive agent shell that never ran
# the interactive hook), fall back to scanning the cache for the newest env
# file that records THIS root.
#
# Every candidate must prove its root (DIRENV_DIR == root). The cache is
# host-wide, so an unattributed or foreign dump applied here hands the shell
# another repository's environment: the loader reports success, the shell
# ends up with no IN_NIX_SHELL and no devshell PATH, and the repository
# operator refuses the root ("invalid Nix environment for repository root").
# Attribute or reject; never guess.
_direnv_instant_cached_env() {
	local root="$1"
	local candidate env_file newest=0 newest_file= recorded
	local -a candidates=()

	[ -n "$root" ] || return 1

	# Preferred: the path the interactive hook exported. It is per-shell and
	# per-root, but a child shell inherits it across a cd, so it is held to
	# the same attribution rule as the scanned candidates.
	if [ -n "${__DIRENV_INSTANT_ENV_FILE:-}" ] &&
		[ -f "$__DIRENV_INSTANT_ENV_FILE" ] &&
		[ -r "$__DIRENV_INSTANT_ENV_FILE" ]; then
		recorded="$(_direnv_instant_recorded_root "$__DIRENV_INSTANT_ENV_FILE")" || recorded=
		if [ "$recorded" = "$root" ]; then
			printf '%s\n' "$__DIRENV_INSTANT_ENV_FILE"
			return 0
		fi
	fi

	# Fallback: newest env file under the direnv-instant cache whose recorded
	# root is this root. `find` instead of a glob: an unmatched glob aborts
	# under zsh nomatch.
	local cache_base="${XDG_CACHE_HOME:-$HOME/.cache}"
	find "$cache_base/direnv-instant" -mindepth 2 -maxdepth 2 -name env -type f \
		-print 2>/dev/null | while IFS= read -r candidate; do
		[ -f "$candidate" ] && [ -r "$candidate" ] || continue
		printf '%s\n' "$candidate"
	done >"${TMPDIR:-/tmp}/.agent-direnv-instant-candidates.$$" 2>/dev/null || true

	while IFS= read -r env_file; do
		[ -n "$env_file" ] || continue
		[ -f "$env_file" ] && [ -r "$env_file" ] || continue
		recorded="$(_direnv_instant_recorded_root "$env_file")" || recorded=
		[ "$recorded" = "$root" ] || continue
		candidates+=("$env_file")
	done <"${TMPDIR:-/tmp}/.agent-direnv-instant-candidates.$$"
	rm -f -- "${TMPDIR:-/tmp}/.agent-direnv-instant-candidates.$$"

	[ "${#candidates[@]}" -gt 0 ] || return 1
	for candidate in "${candidates[@]}"; do
		local mtime
		mtime="$(stat -c %Y -- "$candidate" 2>/dev/null || printf '0')"
		if [ "$mtime" -gt "$newest" ]; then
			newest="$mtime"
			newest_file="$candidate"
		fi
	done
	[ -n "$newest_file" ] || return 1
	printf '%s\n' "$newest_file"
}

# Apply direnv-instant's cached environment file as the prebuilt source.
#
# Precedence: direnv-instant's cache first (it is the live, continuously
# refreshed source), then the host-published prebuilt dumps below. The cached
# file is a plain `direnv export` dump, so it is sourced the same way and
# gets the same DIRENV_DIFF/DIRENV_WATCHES stripping.
agent_direnv_prebuilt_try_direnv_instant() {
	local root="$1"
	local env_file

	[ -n "${BASH_VERSION:-}" ] || return 1
	[ -n "$root" ] || return 1
	env_file="$(_direnv_instant_cached_env "$root")" || return 1
	[ -f "$env_file" ] && [ -r "$env_file" ] || return 1

	# Never source a file that is not a regular, non-symlink dump.
	[ ! -L "$env_file" ] || return 1

	# shellcheck disable=SC1090
	. "$env_file" 2>/dev/null || return 1
	unset DIRENV_DIFF DIRENV_WATCHES
	return 0
}

agent_direnv_prebuilt_try_apply() {
	local root="${1:-$PWD}"
	local repo consumer_kind identity_root apply_dump
	local system devshell rebind rebind_digest inputs_digest material name path digest key
	local dump meta schema meta_repo meta_key meta_system meta_devshell meta_rebind
	local expires_at now header strip_helper
	local -a declared_inputs=() protected_args=()
	local declared

	[ -n "${BASH_VERSION:-}" ] || return 1
	identity_root="$root"

	# direnv-instant's own cached environment file is the live source: the
	# daemon refreshes it continuously, and it exists for every repository with
	# an .envrc -- including ones this function does not know about. Try it
	# before the host-published dumps, which are a per-repo fallback.
	if agent_direnv_prebuilt_try_direnv_instant "$root"; then
		return 0
	fi

	case "$root" in
	/home/mhugo/code/jcode) repo=jcode; consumer_kind=canonical ;;
	/home/mhugo/code/singularity-engine) repo=singularity-engine; consumer_kind=canonical ;;
	/srv/infra) repo=infra; consumer_kind=canonical ;;
	/home/mhugo/code/worktrees/jj/jcode/* | /home/mhugo/code/worktrees/git/jcode/*)
		repo=jcode
		consumer_kind=lane
		identity_root=/home/mhugo/code/jcode
		;;
	/home/mhugo/code/worktrees/jj/singularity-engine/* | /home/mhugo/code/worktrees/git/singularity-engine/* | /home/mhugo/code/.worktrees/singularity-engine/*)
		repo=singularity-engine
		consumer_kind=lane
		identity_root=/home/mhugo/code/singularity-engine
		;;
	/home/mhugo/code/worktrees/jj/infra/* | /home/mhugo/code/worktrees/git/infra/* | /srv/infra-worktrees/* | /srv/worktrees/*/infra/*)
		repo=infra
		consumer_kind=lane
		identity_root=/srv/infra
		;;
	*) return 1 ;;
	esac

	system="${NIX_SYSTEM:-x86_64-linux}"
	devshell=default
	rebind=-
	rebind_digest=-
	inputs_digest=-
	declared_inputs=()

	if [ -e "$identity_root/.agent-direnv-inputs" ]; then
		[ -f "$identity_root/.agent-direnv-inputs" ] && [ ! -L "$identity_root/.agent-direnv-inputs" ] || return 1
		inputs_digest="$(sha256sum -- "$identity_root/.agent-direnv-inputs")"
		inputs_digest="${inputs_digest%% *}"
		while IFS= read -r declared || [ -n "$declared" ]; do
			declared="${declared#"${declared%%[![:space:]]*}"}"
			declared="${declared%"${declared##*[![:space:]]}"}"
			[ -n "$declared" ] && [ "${declared#\#}" = "$declared" ] || continue
			case "$declared" in
			/* | ../* | */../* | */.. | *'*'* | *'?'* | *'['* | *']'*) return 1 ;;
			esac
			declared_inputs+=("$declared")
		done <"$identity_root/.agent-direnv-inputs"
	fi

	material="$(
		printf 'repo:%s\nsystem:%s\ndevShell:%s\n' "$repo" "$system" "$devshell"
		for name in .envrc flake.lock flake.nix; do
			path="$identity_root/$name"
			digest=-
			if [ -f "$path" ]; then
				digest="$(sha256sum -- "$path")"
				digest="${digest%% *}"
			fi
			printf '%s:%s\n' "$name" "$digest"
		done
		printf 'inputs:%s\n' "$inputs_digest"
		for declared in "${declared_inputs[@]}"; do
			path="$identity_root/$declared"
			digest=-
			if [ -f "$path" ] && [ ! -L "$path" ]; then
				digest="$(sha256sum -- "$path")"
				digest="${digest%% *}"
			fi
			printf 'input:%s:%s\n' "$declared" "$digest"
		done
		printf 'rebind:%s\n' "$rebind_digest"
	)"
	key="$(printf '%s\n' "$material" | sha256sum)"
	key="${key%% *}"
	dump="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/agent-direnv/$key.bash"
	meta="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/agent-direnv/$key.meta"
	[ -f "$dump" ] && [ ! -L "$dump" ] && [ -r "$dump" ] && [ ! -w "$dump" ] || return 1
	[ -f "$meta" ] && [ ! -L "$meta" ] && [ -r "$meta" ] && [ ! -w "$meta" ] || return 1

	schema="$(awk -F= '$1 == "schema" {print $2}' "$meta")"
	meta_repo="$(awk -F= '$1 == "repo" {print $2}' "$meta")"
	meta_key="$(awk -F= '$1 == "key" {print $2}' "$meta")"
	meta_system="$(awk -F= '$1 == "system" {print $2}' "$meta")"
	meta_devshell="$(awk -F= '$1 == "devshell" {print $2}' "$meta")"
	meta_rebind="$(awk -F= '$1 == "rebind" {print $2}' "$meta")"
	expires_at="$(awk -F= '$1 == "expires_at" {print $2}' "$meta")"
	now="$(date +%s)"
	_agent_direnv_prebuilt_schema_ok "$schema" || return 1
	[ "$meta_repo" = "$repo" ] || return 1
	[ "$meta_key" = "$key" ] || return 1
	[ "$meta_system" = "$system" ] || return 1
	[ "$meta_devshell" = "$devshell" ] || return 1
	[ "$meta_rebind" = "$rebind" ] || return 1
	case "$expires_at" in
	'' | *[!0-9]*) return 1 ;;
	esac
	[ "$now" -le "$expires_at" ] || return 1

	IFS= read -r header <"$dump" || return 1
	_agent_direnv_prebuilt_header_matches "$header" "$repo" "$key" "$system" "$devshell" || return 1

	apply_dump="$dump"
	if [ "$consumer_kind" = lane ] && [ "$identity_root" != "$root" ]; then
		apply_dump="$(mktemp "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/agent-direnv/.lane-rebind.XXXXXX")" || return 1
		sed "s|${identity_root}|${root}|g" "$dump" >"$apply_dump" || {
			rm -f "$apply_dump"
			return 1
		}
	fi

	strip_helper="$(_agent_direnv_prebuilt_strip_helper)" || return 1

	if ! "$strip_helper" --validate --admit-root "$root" --repository "$repo" --bash "$(command -v bash)" <"$apply_dump" 2>/dev/null; then
		[ "$apply_dump" != "$dump" ] && rm -f "$apply_dump"
		return 1
	fi

	# shellcheck disable=SC1090
	. "$apply_dump" || {
		[ "$apply_dump" != "$dump" ] && rm -f "$apply_dump"
		return 1
	}
	[ "$apply_dump" != "$dump" ] && rm -f "$apply_dump"
	unset DIRENV_DIFF DIRENV_WATCHES
	if [ "$repo" = "singularity-engine" ]; then
		_agent_direnv_bind_engine_workspace "$root" || return 1
	fi
	return 0
}

# Write a ~/.cache/agent-direnv snapshot from a valid prebuilt dump (no nix eval).
agent_direnv_prebuilt_write_snapshot() {
	local root="$1"
	local out_dir="$2"
	local repo identity_root
	local system devshell rebind_digest inputs_digest material name path digest key
	local dump meta schema meta_repo meta_key expires_at now header strip_helper stripped
	local -a declared_inputs=()
	local declared

	[ -n "${BASH_VERSION:-}" ] || return 1
	[ -n "$root" ] && [ -n "$out_dir" ] || return 1
	identity_root="$root"
	case "$root" in
	/home/mhugo/code/jcode) repo=jcode ;;
	/home/mhugo/code/singularity-engine) repo=singularity-engine ;;
	/srv/infra) repo=infra ;;
	*) return 1 ;;
	esac

	system="${NIX_SYSTEM:-x86_64-linux}"
	devshell=default
	rebind_digest=-
	inputs_digest=-
	declared_inputs=()

	if [ -e "$identity_root/.agent-direnv-inputs" ]; then
		[ -f "$identity_root/.agent-direnv-inputs" ] && [ ! -L "$identity_root/.agent-direnv-inputs" ] || return 1
		inputs_digest="$(sha256sum -- "$identity_root/.agent-direnv-inputs")"
		inputs_digest="${inputs_digest%% *}"
	fi

	material="$(
		printf 'repo:%s\nsystem:%s\ndevShell:%s\n' "$repo" "$system" "$devshell"
		for name in .envrc flake.lock flake.nix; do
			path="$identity_root/$name"
			digest=-
			if [ -f "$path" ]; then
				digest="$(sha256sum -- "$path")"
				digest="${digest%% *}"
			fi
			printf '%s:%s\n' "$name" "$digest"
		done
		printf 'inputs:%s\n' "$inputs_digest"
		printf 'rebind:%s\n' "$rebind_digest"
	)"
	key="$(printf '%s\n' "$material" | sha256sum)"
	key="${key%% *}"
	dump="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/agent-direnv/$key.bash"
	meta="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/agent-direnv/$key.meta"
	[ -f "$dump" ] && [ -r "$dump" ] || return 1
	[ -f "$meta" ] && [ -r "$meta" ] || return 1

	schema="$(awk -F= '$1 == "schema" {print $2}' "$meta")"
	meta_repo="$(awk -F= '$1 == "repo" {print $2}' "$meta")"
	meta_key="$(awk -F= '$1 == "key" {print $2}' "$meta")"
	expires_at="$(awk -F= '$1 == "expires_at" {print $2}' "$meta")"
	now="$(date +%s)"
	_agent_direnv_prebuilt_schema_ok "$schema" || return 1
	[ "$meta_repo" = "$repo" ] || return 1
	[ "$meta_key" = "$key" ] || return 1
	case "$expires_at" in
	'' | *[!0-9]*) return 1 ;;
	esac
	[ "$now" -le "$expires_at" ] || return 1

	IFS= read -r header <"$dump" || return 1
	_agent_direnv_prebuilt_header_matches "$header" "$repo" "$key" "$system" "$devshell" || return 1

	strip_helper="$(_agent_direnv_prebuilt_strip_helper)" || return 1
	stripped="$(mktemp "${TMPDIR:-/tmp}/agent-direnv-prebuilt.XXXXXX")" || return 1
	if ! "$strip_helper" --admit-root "$root" --repository "$repo" --bash "$(command -v bash)" <"$dump" >"$stripped" 2>/dev/null ||
		[ ! -s "$stripped" ]; then
		rm -f "$stripped"
		return 1
	fi

	mkdir -p "$out_dir"
	{
		printf '# agent-direnv-root:%s\n' "$root"
		cat "$stripped"
	} >"$out_dir/env"
	rm -f "$stripped"
	return 0
}
