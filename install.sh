#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export DOTFILES_ROOT="$ROOT_DIR"

mkdir -p "$HOME/.config"
if [ -e "$HOME/.config/home-manager" ] && [ ! -L "$HOME/.config/home-manager" ]; then
	rm -rf "$HOME/.config/home-manager"
fi
ln -sfn "$ROOT_DIR" "$HOME/.config/home-manager"

exec "$ROOT_DIR/bootstrap/bootstrap.sh" "$@"
