#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export DOTFILES_ROOT="$ROOT_DIR"

exec "$ROOT_DIR/bootstrap/bootstrap.sh" "$@"
