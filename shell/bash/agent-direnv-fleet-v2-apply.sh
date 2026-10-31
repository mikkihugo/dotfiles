# agent-direnv-fleet-v2-apply.sh — apply host-published v2 dumps without nix eval.
# Mirrors agent_direnv_try_shared_dump in hosts/_shared/nix-direnv-3.2.0.nix for
# BASH_ENV / agent-direnv-prewarm when /etc/direnv is not on the load path.

_agent_direnv_fleet_v2_apply_dump() {
	local root="$1" repo="$2" consumer_kind="$3" identity_root="$4" dump="$5"
	local apply_dump strip_helper

	strip_helper="/srv/infra/scripts/strip-agent-direnv-snapshot.py"
	[ -f "$strip_helper" ] || return 1
	[ -f "$dump" ] && [ -r "$dump" ] || return 1

	apply_dump="$dump"
	if [ "$consumer_kind" = lane ] && [ "$identity_root" != "$root" ]; then
		apply_dump="$(mktemp "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/agent-direnv/.lane-rebind.XXXXXX")" || return 1
		sed "s|${identity_root}|${root}|g" "$dump" >"$apply_dump" || {
			rm -f "$apply_dump"
			return 1
		}
	fi

	if ! python3 "$strip_helper" --validate --admit-root "$root" --repository "$repo" --bash "$(command -v bash)" <"$apply_dump" 2>/dev/null; then
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

_agent_direnv_fleet_v2_newest_dump_for_repo() {
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

agent_direnv_fleet_v2_try_apply() {
	local root="${1:-$PWD}"
	local repo consumer_kind identity_root apply_dump
	local system devshell rebind rebind_digest inputs_digest material name path digest key
	local dump meta schema meta_repo meta_key meta_system meta_devshell meta_rebind
	local expires_at now header strip_helper
	local -a declared_inputs=() protected_args=()
	local declared

	[ -n "${BASH_VERSION:-}" ] || return 1
	identity_root="$root"
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
	[ "$schema" = centralcloud.agent-direnv/v2 ] || return 1
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
	[ "$header" = "# agent-direnv-v2 repo=$repo key=$key system=$system devshell=$devshell rebind=$rebind" ] || return 1

	apply_dump="$dump"
	if [ "$consumer_kind" = lane ] && [ "$identity_root" != "$root" ]; then
		apply_dump="$(mktemp "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/agent-direnv/.lane-rebind.XXXXXX")" || return 1
		sed "s|${identity_root}|${root}|g" "$dump" >"$apply_dump" || {
			rm -f "$apply_dump"
			return 1
		}
	fi

	strip_helper="/srv/infra/scripts/strip-agent-direnv-snapshot.py"
	[ -f "$strip_helper" ] || return 1

	if ! python3 "$strip_helper" --validate --admit-root "$root" --repository "$repo" --bash "$(command -v bash)" <"$apply_dump" 2>/dev/null; then
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

# Write a ~/.cache/agent-direnv snapshot from a valid fleet v2 dump (no nix eval).
agent_direnv_fleet_v2_write_snapshot() {
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
	[ "$schema" = centralcloud.agent-direnv/v2 ] || return 1
	[ "$meta_repo" = "$repo" ] || return 1
	[ "$meta_key" = "$key" ] || return 1
	case "$expires_at" in
	'' | *[!0-9]*) return 1 ;;
	esac
	[ "$now" -le "$expires_at" ] || return 1

	IFS= read -r header <"$dump" || return 1
	case "$header" in
	"# agent-direnv-v2 repo=$repo key=$key system=$system devshell=$devshell rebind="*) ;;
	*) return 1 ;;
	esac

	strip_helper="/srv/infra/scripts/strip-agent-direnv-snapshot.py"
	[ -f "$strip_helper" ] || return 1
	stripped="$(mktemp "${TMPDIR:-/tmp}/agent-direnv-fleet-v2.XXXXXX")" || return 1
	if ! python3 "$strip_helper" --admit-root "$root" --repository "$repo" --bash "$(command -v bash)" <"$dump" >"$stripped" 2>/dev/null ||
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
