#!/usr/bin/env bash
# 02-sudoers.sh — grant NOPASSWD sudo so later bootstrap steps + home-manager
# activations can install system packages and drive systemctl without
# interactive password prompts.
#
# This is the only step that prompts for sudo. Everything downstream
# (system pkg installs, tailscale up, systemctl enable) runs unprompted.
#
# Idempotent. Writes /etc/sudoers.d/dotfiles-${USER}; validated with visudo -c
# before install so a syntax error can't lock you out.
set -euo pipefail

RULE="/etc/sudoers.d/dotfiles-${USER}"
CONTENT="${USER} ALL=(ALL) NOPASSWD: ALL"

if sudo test -f "$RULE" && sudo grep -qxF "$CONTENT" "$RULE" 2>/dev/null; then
	echo "[02-sudoers] already installed — skipping"
	exit 0
fi

TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT
echo "$CONTENT" >"$TMP"
sudo visudo -c -f "$TMP" >/dev/null
sudo install -m 0440 -o root -g root "$TMP" "$RULE"

echo "[02-sudoers] installed $RULE — sudo will not prompt for $USER going forward"
