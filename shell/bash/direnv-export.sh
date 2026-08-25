#!/usr/bin/env sh
# Load a repository environment for non-interactive shells without repeatedly
# evaluating the same repo. Consumers: bashrc, BASH_ENV (Claude/Codex/goose),
# zshenv (Cursor `zsh -c` — Cursor does not use the agent-shell wrapper as
# argv0; this sourced file is the live path), and the host-wide agent-shell
# wrapper.
# Matching Nix (impure OK, fallback != 1, DIRENV_DIR prefix of PWD): skip.
# Else eval a content-addressed dump from $XDG_RUNTIME_DIR/agent-direnv/.
# Miss: flock max 1, re-check cache, one direnv allow + export, atomic mv, eval.
# Waiters queue on the lock and hit the cache; they do not start another export.
# Fill is a bare `direnv export bash` (do not wrap in `timeout` — a SIGTERM
# matcher kills `timeout * direnv export` and the dump never publishes).
# Fail-open fallback remains timeout 15s direnv export bash.
# Nested BASH_ENV after this loader already ran: dump hit only, never flock.
# Fill strips DIRENV_DIFF / DIRENV_WATCHES from the one-line dump (python3
# assignment scanner — not grep -v) and records # agent-direnv-root:<path>.
# Hits refuse a dump whose recorded root no longer has .envrc.
# IN_NIX_SHELL=impure from direnv is valid; do not recover with nix develop.

# direnv keeps a gzip+base64 snapshot of the environment in DIRENV_DIFF, and the
# snapshot embeds the environment it was taken from, so a shell that re-enters
# direnv repeatedly grows it super-linearly. Past MAX_ARG_STRLEN (32 * PAGE_SIZE,
# 128 KiB here) the kernel refuses EVERY exec in that shell with E2BIG. That
# surfaces as "argument list too long" from every command, and any tool that
# retries a failed exec turns into a fork storm; 142,940 bytes was measured on
# this host while load sat at 555. The snapshot is a cache direnv rebuilds on
# demand, so dropping an oversized one costs one recompute and revives the shell.
# This runs before every early return below, including DIRENV_DISABLE and the
# interactive and skip paths, because a poisoned value is inherited by children
# and has to be cleared wherever it is seen.
# Read through a defaulted temporary: ${#VAR} on an unset VAR aborts a shell
# running under `set -u`, and ${#VAR:-} is not valid bash. Callers include
# non-interactive shells spawned per just recipe line, so aborting here failed
# every gated push with "DIRENV_DIFF: unbound variable" while the checks
# themselves passed.
_direnv_diff_snapshot="${DIRENV_DIFF:-}"
if [ "${#_direnv_diff_snapshot}" -gt 65536 ]; then
	unset DIRENV_DIFF
fi
_direnv_watches_snapshot="${DIRENV_WATCHES:-}"
if [ "${#_direnv_watches_snapshot}" -gt 65536 ]; then
	unset DIRENV_WATCHES
fi
unset _direnv_diff_snapshot _direnv_watches_snapshot

# `direnv export` emits an absolute `export PATH=...` snapshot of whichever shell
# produced it, never a delta, and _direnv_cache_key hashes only cwd + .envrc +
# flake bytes -- no PATH component. So the first shell to fill a dump freezes its
# own PATH for every later shell, applying a dump overwrites PATH instead of
# merging it, and nothing invalidates that until the flake changes. A filler that
# never sourced hm-session-vars.sh (nested agent shell, service unit) therefore
# strips ~/.npm-global/bin and ~/.nix-profile/bin out of healthy shells: `codex`
# and `direnv-instant` stop resolving mid-session. It also spreads, because the
# downgraded shell goes on to fill other repositories' dumps -- the .dotfiles dump
# on this host was observed carrying jcode's PATH.
if [ -n "${DIRENV_DISABLE:-}" ] || [ "${-#*i}" != "$-" ]; then
	return 0
fi

# Snapshot the caller PATH before any dump or enter can replace it. Below the
# early return: an interactive shell exits above without _direnv_cleanup, so a
# snapshot taken earlier would linger as a stray variable in every such shell.
_direnv_caller_path="$PATH"

_direnv_skip_enter() {
	[ -n "${IN_NIX_SHELL:-}" ] || return 1
	[ "${NIX_DIRENV_DID_FALLBACK:-}" != "1" ] || return 1
	_direnv_active_root="${DIRENV_DIR#-}"
	[ -n "$_direnv_active_root" ] || return 1
	case "$PWD/" in
	"$_direnv_active_root/"*)
		unset _direnv_active_root
		return 0
		;;
	esac
	unset _direnv_active_root
	return 1
}

# Ceiling on concurrent flake evaluations across the whole host, and the longest
# a shell waits (in 0.2s ticks, so 100 = 20s) for a peer to publish a dump.
_DIRENV_MAX_PARALLEL=10
_DIRENV_WAIT_TICKS=100

_direnv_cleanup() {
	unset _direnv_lock _direnv_cache_dir _direnv_key _direnv_file _direnv_tmp _direnv_root
	unset _direnv_stripped _direnv_strip_helper _direnv_hdr _direnv_recorded _direnv_old
	unset _direnv_slot _direnv_ticks _DIRENV_MAX_PARALLEL _DIRENV_WAIT_TICKS
	unset _direnv_caller_path _direnv_restore_rest _direnv_restore_entry
	unset -f _direnv_take_slot _direnv_await_cache 2>/dev/null || true
	unset -f _direnv_restore_caller_path 2>/dev/null || true
	unset -f _direnv_skip_enter _direnv_cleanup _direnv_envrc_root \
		_direnv_cache_key _direnv_eval_hit _direnv_fill_cache \
		_direnv_prune_dead_dumps _direnv_do_enter 2>/dev/null || true
}

# Re-append every caller PATH entry the applied environment dropped. Append and
# never prepend: the repository environment must keep winning for anything it
# actually provides; this only restores what a frozen snapshot removed.
_direnv_restore_caller_path() {
	[ -n "${_direnv_caller_path:-}" ] || return 0
	_direnv_restore_rest="$_direnv_caller_path"
	while [ -n "$_direnv_restore_rest" ]; do
		_direnv_restore_entry="${_direnv_restore_rest%%:*}"
		case "$_direnv_restore_rest" in
		*:*) _direnv_restore_rest="${_direnv_restore_rest#*:}" ;;
		*) _direnv_restore_rest= ;;
		esac
		[ -n "$_direnv_restore_entry" ] || continue
		case ":$PATH:" in
		*":$_direnv_restore_entry:"*) ;;
		*) PATH="${PATH:+$PATH:}$_direnv_restore_entry" ;;
		esac
	done
	export PATH
	unset _direnv_restore_rest _direnv_restore_entry
}

if _direnv_skip_enter; then
	_direnv_cleanup
	return 0
fi

# Cursor `zsh -c` sanitizes PATH. If direnv/coreutils/flock are missing, pull
# them from the system profiles. Do not prepend when they already resolve —
# tests (and anyone with a wrapped direnv) must keep their PATH winner.
if ! command -v direnv >/dev/null 2>&1 ||
	! command -v timeout >/dev/null 2>&1 ||
	! command -v sha256sum >/dev/null 2>&1 ||
	! command -v flock >/dev/null 2>&1 ||
	! command -v python3 >/dev/null 2>&1; then
	PATH="/run/current-system/sw/bin:/etc/profiles/per-user/${USER:-mhugo}/bin:${HOME}/.nix-profile/bin:/usr/bin:${PATH}"
fi

# Home Manager supplies coreutils, but fail open if a dependency is absent;
# never replace the bounded contract with an unbounded fallback.
if ! command -v direnv >/dev/null 2>&1 || ! command -v timeout >/dev/null 2>&1; then
	_direnv_cleanup
	return 0
fi

_direnv_do_enter() {
	# Never trace this function: xtrace prints the eval argument already
	# expanded, so a traced agent shell writes out the whole `export DIRENV_DIFF=`
	# blob, which decodes to the previous environment -- including the live
	# SCCACHE_WEBDAV_TOKEN, because the jcode devShell unsets it on entry and
	# direnv therefore has to remember it to restore on exit. This matters more
	# than the interactive loaders: zsh's envExtra sources ONLY this file, so for
	# `zsh -c` agent shells it is the single dotfiles file in play.
	# Same rule and same zsh caveat as _load_sops_secrets in shell/bash/bashrc.
	# SC3043: this file carries a POSIX sh shebang, and `local` is not POSIX --
	# but the guard means it is only ever reached under bash, where it is valid.
	# shellcheck disable=SC3043
	[ -n "${BASH_VERSION:-}" ] && local -
	[ -n "${ZSH_VERSION:-}" ] && setopt localoptions
	set +x

	direnv allow . >/dev/null 2>&1 || true
	unset DIRENV_DIFF DIRENV_WATCHES
	eval "$(timeout 15s direnv export bash 2>/dev/null)" || true
	_direnv_restore_caller_path
}

_direnv_envrc_root() {
	_direnv_walk=$PWD
	while [ -n "$_direnv_walk" ]; do
		if [ -f "$_direnv_walk/.envrc" ]; then
			_direnv_canon=$(CDPATH='' cd -P -- "$_direnv_walk" 2>/dev/null && pwd -P) ||
				_direnv_canon=$_direnv_walk
			printf '%s\n' "$_direnv_canon"
			unset _direnv_walk _direnv_canon
			return 0
		fi
		[ "$_direnv_walk" = / ] && break
		_direnv_walk=${_direnv_walk%/*}
		[ -n "$_direnv_walk" ] || _direnv_walk=/
	done
	unset _direnv_walk
	return 1
}

_direnv_cache_key() {
	{
		printf 'cwd:%s\n' "$1"
		[ -f "$1/.envrc" ] && sha256sum -- "$1/.envrc"
		[ -f "$1/flake.lock" ] && sha256sum -- "$1/flake.lock"
		[ -f "$1/flake.nix" ] && sha256sum -- "$1/flake.nix"
	} | sha256sum
}

_direnv_eval_hit() {
	_direnv_file="${_direnv_cache_dir}/${_direnv_key}.bash"
	[ -s "$_direnv_file" ] || return 1
	IFS= read -r _direnv_hdr <"$_direnv_file" || true
	case "$_direnv_hdr" in
	"# agent-direnv-envrc-root:"*)
		_direnv_recorded=${_direnv_hdr#\# agent-direnv-envrc-root:}
		if [ ! -f "${_direnv_recorded}/.envrc" ]; then
			rm -f -- "$_direnv_file"
			unset _direnv_hdr _direnv_recorded
			return 1
		fi
		;;
	"# agent-direnv-root:"*)
		_direnv_recorded=${_direnv_hdr#\# agent-direnv-root:}
		if [ ! -d "$_direnv_recorded" ]; then
			rm -f -- "$_direnv_file"
			unset _direnv_hdr _direnv_recorded
			return 1
		fi
		;;
	esac
	unset _direnv_hdr _direnv_recorded
	# Source the dump. eval "$(<file)" hits ARG_MAX on nix-direnv exports.
	# Ignore source status: dumps may end on a non-zero builtin, and deleting
	# the cache on that re-stormed every Cursor zsh -c.
	# shellcheck disable=SC1090
	. "$_direnv_file" 2>/dev/null || true
	# Strip already removed these from new dumps; always drop them after
	# source so a stale one-line dump cannot re-poison ARG_MAX. The 64KiB
	# guard at the top of this file remains for inherited skip paths.
	unset DIRENV_DIFF DIRENV_WATCHES
	_direnv_restore_caller_path
	# The two size guards that used to sit here measured ${#DIRENV_DIFF} and
	# ${#DIRENV_WATCHES} on the line after that unconditional unset, so their
	# length could never exceed the threshold and the unsets they guarded could
	# never run. Dead either way -- but under `set -u` measuring an unset
	# variable aborts the shell, so on this path the dead code was the only
	# thing the guards reliably did. The 64KiB guard at the top of this file
	# still covers inherited skip paths, which is where a poisoned value can
	# actually arrive.
	return 0
}

_direnv_prune_dead_dumps() {
	[ -d "$_direnv_cache_dir" ] || return 0
	# find, not a glob: this file is sourced from zsh, and unmatched
	# globs abort the whole Cursor zsh -c under nomatch.
	find "$_direnv_cache_dir" -maxdepth 1 -name '.*.tmp' -type f -delete 2>/dev/null || true
	find "$_direnv_cache_dir" -maxdepth 1 -name '*.bash' -type f -print |
		while IFS= read -r _direnv_old; do
			[ -f "$_direnv_old" ] || continue
			IFS= read -r _direnv_hdr <"$_direnv_old" || continue
			case "$_direnv_hdr" in
			"# agent-direnv-envrc-root:"*)
				_direnv_recorded=${_direnv_hdr#\# agent-direnv-envrc-root:}
				if [ ! -f "${_direnv_recorded}/.envrc" ]; then
					rm -f -- "$_direnv_old"
				fi
				;;
			"# agent-direnv-root:"*)
				_direnv_recorded=${_direnv_hdr#\# agent-direnv-root:}
				if [ ! -d "$_direnv_recorded" ]; then
					rm -f -- "$_direnv_old"
				fi
				;;
			esac
		done
	find "$_direnv_cache_dir" -maxdepth 1 -name '*.lock' -type f -print |
		while IFS= read -r _direnv_old; do
			[ -f "$_direnv_old" ] || continue
			_direnv_stem=${_direnv_old%.lock}
			if [ ! -f "${_direnv_stem}.bash" ]; then
				rm -f -- "$_direnv_old"
			fi
		done
	unset _direnv_old _direnv_hdr _direnv_recorded _direnv_stem
}

_direnv_fill_cache() {
	direnv allow . >/dev/null 2>&1 || true
	unset DIRENV_DIFF DIRENV_WATCHES
	_direnv_tmp="${_direnv_cache_dir}/.${_direnv_key}.$$.tmp"
	_direnv_stripped="${_direnv_tmp}.stripped"
	_direnv_strip_helper="${HOME}/.dotfiles/shell/bash/direnv-strip-snapshot.py"
	# Do not wrap this export in `timeout`: a sibling SIGTERM matcher kills
	# `timeout * direnv export` and the dump never publishes. Flock max 1
	# already serializes the fill.
	if direnv export bash >"$_direnv_tmp" 2>/dev/null && [ -s "$_direnv_tmp" ]; then
		# Byte-safe assignment strip. grep -v is a no-op or a dump-killer on
		# nix-direnv's single semicolon-joined line.
		if ! command -v python3 >/dev/null 2>&1 ||
			[ ! -f "$_direnv_strip_helper" ] ||
			! python3 "$_direnv_strip_helper" <"$_direnv_tmp" >"$_direnv_stripped" ||
			[ ! -s "$_direnv_stripped" ]; then
			rm -f -- "$_direnv_tmp" "$_direnv_stripped"
			return 1
		fi
		{
			if [ -f "${_direnv_root}/.envrc" ]; then
				printf '# agent-direnv-envrc-root:%s\n' "$_direnv_root"
			else
				printf '# agent-direnv-root:%s\n' "$_direnv_root"
			fi
			cat -- "$_direnv_stripped"
		} >"$_direnv_tmp"
		rm -f -- "$_direnv_stripped"
		chmod 0600 "$_direnv_tmp" 2>/dev/null || true
		mv -f -- "$_direnv_tmp" "${_direnv_cache_dir}/${_direnv_key}.bash"
		_direnv_eval_hit && return 0
	fi
	rm -f -- "$_direnv_tmp" "$_direnv_stripped"
	return 1
}

if ! _direnv_root=$(_direnv_envrc_root); then
	_direnv_cleanup
	export BASH_ENV="${BASH_ENV:-$HOME/.dotfiles/shell/bash/noninteractive-path.sh}"
	return 0
fi

_direnv_cache_dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/agent-direnv"
_direnv_lock="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/agent-direnv-export.lock"
_direnv_key=

# A wrapper and its exec'd bash share one repository root. Skip the second
# entry before hashing or reading the dump, but do not let a parent shell from
# another repository suppress this root's environment.
if [ "${AGENT_DIRENV_EXPORT_TRIED_ROOT:-}" = "$_direnv_root" ]; then
	_direnv_cleanup
	export BASH_ENV="${BASH_ENV:-$HOME/.dotfiles/shell/bash/noninteractive-path.sh}"
	return 0
fi

if command -v sha256sum >/dev/null 2>&1; then
	_direnv_key=$(_direnv_cache_key "$_direnv_root")
	_direnv_key=${_direnv_key%% *}
	if [ -n "$_direnv_key" ] && _direnv_eval_hit; then
		_direnv_cleanup
		export BASH_ENV="${BASH_ENV:-$HOME/.dotfiles/shell/bash/noninteractive-path.sh}"
		return 0
	fi
	_direnv_prune_dead_dumps
fi

export AGENT_DIRENV_EXPORT_TRIED=1
export AGENT_DIRENV_EXPORT_TRIED_ROOT="$_direnv_root"

mkdir -p "$_direnv_cache_dir" 2>/dev/null || true
chmod 0700 "$_direnv_cache_dir" 2>/dev/null || true

# Serialize per repository root, not host-wide. One global lock made every shell
# in every repository queue behind whichever repo happened to be evaluating, and
# with a cache that could not publish they each burned the full wait and returned
# with no environment. Per-root locking keeps the part that matters -- same-root
# shells still dedupe to a single evaluation, so no flake is ever built twice --
# and drops the part that serialized unrelated repositories against each other.
if [ -n "$_direnv_key" ]; then
	_direnv_lock="${_direnv_cache_dir}/${_direnv_key}.lock"
fi

# Host-wide ceiling, so N cold repositories cannot start N evaluations at once.
# Slots are probed non-blocking: a shell that finds all of them busy learns so
# immediately and waits for the dump instead of joining a queue. fd 8 holds the
# slot, fd 9 below holds the per-root lock.
_direnv_take_slot() {
	_direnv_slot=0
	while [ "$_direnv_slot" -lt "$_DIRENV_MAX_PARALLEL" ]; do
		# Create the slot in a subshell: `exec` with redirections and no command
		# applies them to THIS shell permanently, so an `exec ... 2>/dev/null`
		# would send every later diagnostic on this shell to /dev/null. That is
		# not hypothetical -- it silently swallowed a wrapper's stderr until the
		# cargo-pgrx contract test caught it. Keep suppression inside a subshell
		# or on a real command, never on a bare exec.
		if (
			umask 077
			: >>"${_direnv_cache_dir}/slot.${_direnv_slot}"
		) 2>/dev/null; then
			exec 8>>"${_direnv_cache_dir}/slot.${_direnv_slot}"
			if flock -n 8 2>/dev/null; then
				return 0
			fi
			exec 8>&-
		fi
		_direnv_slot=$((_direnv_slot + 1))
	done
	return 1
}

# Poll for a dump a peer is filling. Re-checking beats blocking on the lock: the
# moment any filler publishes, every waiter returns on its next tick for the
# cost of one file read.
_direnv_await_cache() {
	_direnv_ticks=0
	while [ "$_direnv_ticks" -lt "$_DIRENV_WAIT_TICKS" ]; do
		sleep 0.2 2>/dev/null || return 1
		if [ -n "$_direnv_key" ] && _direnv_eval_hit; then
			return 0
		fi
		_direnv_ticks=$((_direnv_ticks + 1))
	done
	return 1
}

if command -v flock >/dev/null 2>&1 && (
	umask 077
	: >>"$_direnv_lock"
) 2>/dev/null; then
	{
		# 20s, not 90s: this wait exists only to let a peer publish the dump, and
		# a publish that has not landed in 20s will not land inside 90 either.
		# That 20s is this lock only, not a per-shell bound. A shell that loses
		# every race chains 20s here, then 20s in _direnv_await_cache, then the
		# fail-open `timeout 15s direnv export` — 55s worst case. Better than the
		# 90s+15s it replaces, but do not read "20s" as the ceiling.
		# Every branch must leave the shell with an environment -- the previous
		# timeout branch only logged, so a shell that lost the race continued
		# with no Nix environment at all, which is what kept the queue alive.
		if ! flock -w 20 9; then
			_direnv_await_cache || _direnv_do_enter
		elif _direnv_skip_enter; then
			:
		elif [ -n "$_direnv_key" ] && _direnv_eval_hit; then
			:
		elif [ -n "$_direnv_key" ] && _direnv_take_slot; then
			_direnv_fill_cache || _direnv_do_enter
			exec 8>&-
		else
			_direnv_await_cache || _direnv_do_enter
		fi
	} 9>>"$_direnv_lock"
else
	_direnv_do_enter
fi

_direnv_cleanup

# Child bash (Claude/Codex/goose/kimi/vtcode) reuses this loader via BASH_ENV.
export BASH_ENV="${BASH_ENV:-$HOME/.dotfiles/shell/bash/noninteractive-path.sh}"
