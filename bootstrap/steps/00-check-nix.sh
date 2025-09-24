#!/bin/bash
set -euo pipefail

if ! command -v nix >/dev/null 2>&1; then
  cat <<'MSG' >&2
Nix is not available on this system.
Install it from https://nixos.org/download.html (multi-user recommended)
then re-run the bootstrap steps inside `nix develop`.
MSG
  exit 1
fi
