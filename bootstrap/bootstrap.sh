#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)"
export DOTFILES_ROOT="$ROOT_DIR"

PROFILE="${DOTFILES_PROFILE:-default}"
PROFILE_DIR="$ROOT_DIR/profiles/$PROFILE"

if [[ ! -d "$PROFILE_DIR" ]]; then
  echo "Unknown profile: $PROFILE" >&2
  exit 1
fi

echo "==> Using profile: $PROFILE"

for step in $(find "$ROOT_DIR/bootstrap/steps" -maxdepth 1 -type f -name "*.sh" | sort); do
  echo "==> Running $(basename "$step")"
  bash "$step" "$PROFILE"
done

echo "✅ Bootstrap complete"
