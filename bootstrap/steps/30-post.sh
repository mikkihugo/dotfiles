#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"/../.. && pwd)"
MACHINE_ENV="${HOME}/.config/dotfiles/machine-role.env"

if [[ -x "$ROOT_DIR/tasks/run" ]]; then
	"$ROOT_DIR/tasks/run" doctor || true
fi

if [[ -f "$MACHINE_ENV" ]] && command -v systemctl >/dev/null 2>&1; then
	# shellcheck disable=SC1090
	source "$MACHINE_ENV"

	if [[ "${DOTFILES_ENABLE_OPENCLAW_NODE:-false}" == "true" ]]; then
		systemctl --user enable --now openclaw-node.service >/dev/null 2>&1 ||
			echo "⚠️  could not start openclaw-node.service"
	fi
fi
