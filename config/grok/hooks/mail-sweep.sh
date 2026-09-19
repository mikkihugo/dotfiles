#!@bash@
# shellcheck shell=bash disable=SC1008,SC2239
# Grok-native wrap. Runs only ~/.grok/hooks — never ~/.codex/hooks.
# Client label grok → identity grok-<session>. Hook session is grok-<session>-hook
# (deriveCoordinationSession). Fail-open (exit 0).
set -u
export REPO_MEMORY_COORDINATION_BUS=1
# TUI cwd is often $HOME, which would otherwise enroll only `global`.
export COORDINATION_HOME_MAILBOXES="${COORDINATION_HOME_MAILBOXES:-infra,jcode,singularity-engine,dotfiles}"
SWEEP="${HOME}/.grok/hooks/bin/coordination-mailbox-sweep.mjs"
if [[ ! -r $SWEEP ]]; then
	exit 0
fi
exec @node@ "$SWEEP" grok "${2:-UserPromptSubmit}"
