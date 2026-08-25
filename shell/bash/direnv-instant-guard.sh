#!/usr/bin/env bash
# shell/bash/direnv-instant-guard.sh
#
# Interactive twin of the caller-PATH restore in direnv-export.sh.
#
# NixOS `programs.direnv-instant` installs `eval "$(direnv-instant hook bash)"`
# in /etc/bashrc, which bash sources BEFORE ~/.bashrc. That hook arms
# `trap '_direnv_handler' USR1` and runs `direnv-instant start` immediately, so
# the daemon computes the repository environment from a PATH that still lacks
# every home.sessionPath entry -- ~/.bashrc only re-sources hm-session-vars.sh
# later. `direnv export` emits an absolute `export PATH=...` snapshot, so when
# the daemon's SIGUSR1 lands (observed mid-~/.bashrc, inside the runtime bashrc)
# `_direnv_handler` evals that snapshot and replaces the repaired PATH with the
# truncated one. ~/.npm-global/bin disappears and `codex` stops resolving.
#
# Re-arm the trap and take over the PROMPT_COMMAND entry so every application of
# that environment is followed by the same restore direnv-export.sh performs for
# non-interactive shells.

# shellInit is shared with zsh; this file uses bash-only builtins.
[ -n "${BASH_VERSION:-}" ] || return 0
case $- in
*i*) ;;
*) return 0 ;;
esac

# direnv-instant sends one SIGUSR1 per `direnv-instant start`, so a second
# signal cannot arrive while the handler is mid-apply and overwrite the snapshot
# with a half-truncated PATH. If that ever changes, this must become a stack.
_direnv_instant_guard_snapshot() {
	_DIRENV_INSTANT_GUARD_PATH="$PATH"
}

# Re-append every snapshot entry the applied environment dropped. Append, never
# prepend: the repository environment must keep winning for anything it actually
# provides. Same rule as _direnv_restore_caller_path in direnv-export.sh, which
# owns the non-interactive half.
_direnv_instant_guard_restore() {
	local rest entry
	[ -n "${_DIRENV_INSTANT_GUARD_PATH:-}" ] || return 0
	rest="$_DIRENV_INSTANT_GUARD_PATH"
	unset _DIRENV_INSTANT_GUARD_PATH
	while [ -n "$rest" ]; do
		entry="${rest%%:*}"
		case "$rest" in
		*:*) rest="${rest#*:}" ;;
		*) rest= ;;
		esac
		[ -n "$entry" ] || continue
		case ":$PATH:" in
		*":$entry:"*) ;;
		*) PATH="${PATH:+$PATH:}$entry" ;;
		esac
	done
	export PATH
}

_direnv_instant_guard_hook() {
	local _direnv_instant_guard_status
	_direnv_instant_guard_snapshot
	_direnv_hook "$@"
	_direnv_instant_guard_status=$?
	_direnv_instant_guard_restore
	return "$_direnv_instant_guard_status"
}

# A trap stores a command string, so re-arming here survives the later
# `eval "$(direnv-instant hook bash)"` in ~/.bashrc: that re-eval redefines both
# functions, but its trap and PROMPT_COMMAND setup sit behind
# __DIRENV_INSTANT_HOOKED and never run a second time.
if declare -f _direnv_handler >/dev/null 2>&1; then
	trap -- '_direnv_instant_guard_snapshot; _direnv_handler; _direnv_instant_guard_restore' USR1
fi

_direnv_instant_guard_take_prompt_array() {
	local i
	for i in "${!PROMPT_COMMAND[@]}"; do
		if [ "${PROMPT_COMMAND[i]}" = "_direnv_hook" ]; then
			PROMPT_COMMAND[i]=_direnv_instant_guard_hook
		fi
	done
}

# PROMPT_COMMAND is a string in most shells and an array in bash 5.1+ when the
# user made it one; direnv-instant's own hook branches on the same distinction.
# shellcheck disable=SC2178 # the array form is handled by the sibling function
_direnv_instant_guard_take_prompt_string() {
	case ";${PROMPT_COMMAND:-};" in
	*";_direnv_hook;"*)
		PROMPT_COMMAND="${PROMPT_COMMAND//_direnv_hook/_direnv_instant_guard_hook}"
		;;
	esac
}

# PROMPT_COMMAND is the only place the prompt-time apply can be intercepted: it
# holds the function NAME, so this substitution survives the later re-eval that
# redefines _direnv_hook. Re-running this file is a no-op because
# _direnv_instant_guard_hook does not contain the substring _direnv_hook.
if declare -f _direnv_hook >/dev/null 2>&1; then
	if [[ "$(declare -p PROMPT_COMMAND 2>/dev/null)" == "declare -a"* ]]; then
		_direnv_instant_guard_take_prompt_array
	else
		_direnv_instant_guard_take_prompt_string
	fi
fi
