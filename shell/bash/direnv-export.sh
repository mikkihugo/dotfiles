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
if [ "${#DIRENV_DIFF}" -gt 65536 ]; then
	unset DIRENV_DIFF
fi
if [ "${#DIRENV_WATCHES}" -gt 65536 ]; then
	unset DIRENV_WATCHES
fi

if [ -n "${DIRENV_DISABLE:-}" ] || [ "${-#*i}" != "$-" ]; then
	return 0
fi

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
	unset _direnv_slot _direnv_ticks _DIRENV_MAX_PARALLEL _DIRENV_WAIT_TICKS
	unset -f _direnv_take_slot _direnv_await_cache 2>/dev/null || true
	unset -f _direnv_skip_enter _direnv_cleanup _direnv_envrc_root \
		_direnv_cache_key _direnv_eval_hit _direnv_fill_cache \
		_direnv_do_enter 2>/dev/null || true
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
	! command -v flock >/dev/null 2>&1; then
	PATH="/run/current-system/sw/bin:/etc/profiles/per-user/${USER:-mhugo}/bin:${HOME}/.nix-profile/bin:/usr/bin:${PATH}"
fi

# Home Manager supplies coreutils, but fail open if a dependency is absent;
# never replace the bounded contract with an unbounded fallback.
if ! command -v direnv >/dev/null 2>&1 || ! command -v timeout >/dev/null 2>&1; then
	_direnv_cleanup
	return 0
fi

_direnv_do_enter() {
	direnv allow . >/dev/null 2>&1 || true
	unset DIRENV_DIFF DIRENV_WATCHES
	eval "$(timeout 15s direnv export bash 2>/dev/null)" || true
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
	# Source the dump. eval "$(<file)" hits ARG_MAX on nix-direnv exports.
	# Ignore source status: dumps may end on a non-zero builtin, and deleting
	# the cache on that re-stormed every Cursor zsh -c.
	# shellcheck disable=SC1090
	. "$_direnv_file" 2>/dev/null || true
	# Dumps re-export DIRENV_DIFF; past ARG_MAX every later exec is E2BIG.
	if [ "${#DIRENV_DIFF}" -gt 65536 ]; then
		unset DIRENV_DIFF
	fi
	if [ "${#DIRENV_WATCHES}" -gt 65536 ]; then
		unset DIRENV_WATCHES
	fi
	return 0
}

_direnv_fill_cache() {
	direnv allow . >/dev/null 2>&1 || true
	unset DIRENV_DIFF DIRENV_WATCHES
	_direnv_tmp="${_direnv_cache_dir}/.${_direnv_key}.$$.tmp"
	# Do not wrap this export in `timeout`: a sibling SIGTERM matcher kills
	# `timeout * direnv export` and the dump never publishes. Flock max 1
	# already serializes the fill.
	if direnv export bash >"$_direnv_tmp" 2>/dev/null && [ -s "$_direnv_tmp" ]; then
		# No DIRENV_DIFF/DIRENV_WATCHES strip here on purpose. `direnv export
		# bash` emits ONE semicolon-joined line, so a line-oriented `grep -v`
		# either drops the whole dump or changes nothing -- measured across all
		# 14 live dumps: 10 byte-identical, 4 emptied and discarded. It has never
		# removed a snapshot. Worse, if a dump ever spanned two lines the filter
		# would publish only the surviving line, and the `mv` below would install
		# a dump missing nearly every export. A no-op with a destructive edge is
		# strictly worse than no filter, and the snapshot is already handled
		# twice: `unset DIRENV_DIFF DIRENV_WATCHES` above runs before the export
		# so nothing nests, and the size guard re-checks after a cache hit.
		chmod 0600 "$_direnv_tmp" 2>/dev/null || true
		mv -f -- "$_direnv_tmp" "${_direnv_cache_dir}/${_direnv_key}.bash"
		_direnv_eval_hit && return 0
	fi
	rm -f -- "$_direnv_tmp"
	return 1
}

_direnv_root=$(_direnv_envrc_root) ||
	_direnv_root=$(CDPATH='' cd -P -- "${PWD:-.}" 2>/dev/null && pwd -P) ||
	_direnv_root=$PWD

_direnv_cache_dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/agent-direnv"
_direnv_lock="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/agent-direnv-export.lock"
_direnv_key=

if command -v sha256sum >/dev/null 2>&1; then
	_direnv_key=$(_direnv_cache_key "$_direnv_root")
	_direnv_key=${_direnv_key%% *}
	if [ -n "$_direnv_key" ] && _direnv_eval_hit; then
		_direnv_cleanup
		export BASH_ENV="${BASH_ENV:-$HOME/.dotfiles/shell/bash/noninteractive-path.sh}"
		return 0
	fi
fi

# zshenv already ran this loader; child bash via BASH_ENV must not wait on
# the same flock (that doubled every Cursor tool shell to 180s of queue).
if [ -n "${AGENT_DIRENV_EXPORT_TRIED:-}" ]; then
	_direnv_cleanup
	export BASH_ENV="${BASH_ENV:-$HOME/.dotfiles/shell/bash/noninteractive-path.sh}"
	return 0
fi
export AGENT_DIRENV_EXPORT_TRIED=1

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
