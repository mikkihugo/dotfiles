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

_direnv_cleanup() {
	unset _direnv_lock _direnv_cache_dir _direnv_key _direnv_file _direnv_tmp _direnv_root
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
		# Strip direnv snapshots so a hit cannot revive ARG_MAX.
		if grep -vE '^export DIRENV_(DIFF|WATCHES)=' "$_direnv_tmp" >"${_direnv_tmp}.strip"; then
			mv -f -- "${_direnv_tmp}.strip" "$_direnv_tmp"
		else
			rm -f -- "${_direnv_tmp}.strip"
		fi
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

if command -v flock >/dev/null 2>&1 && (
	umask 077
	: >>"$_direnv_lock"
) 2>/dev/null; then
	{
		if ! flock -w 90 9; then
			echo "direnv-export: queue wait timed out after 90s" >&2
		elif _direnv_skip_enter; then
			:
		elif [ -n "$_direnv_key" ] && _direnv_eval_hit; then
			:
		elif [ -n "$_direnv_key" ] && mkdir -p "$_direnv_cache_dir" 2>/dev/null; then
			chmod 0700 "$_direnv_cache_dir" 2>/dev/null || true
			_direnv_fill_cache || _direnv_do_enter
		else
			_direnv_do_enter
		fi
	} 9>>"$_direnv_lock"
else
	_direnv_do_enter
fi

_direnv_cleanup

# Child bash (Claude/Codex/goose/kimi/vtcode) reuses this loader via BASH_ENV.
export BASH_ENV="${BASH_ENV:-$HOME/.dotfiles/shell/bash/noninteractive-path.sh}"
