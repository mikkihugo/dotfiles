#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
"$root/scripts/test-repo-vcs.sh"
python3 "$root/scripts/test-codex-preferences.py"
(
	cd "$root"
	node --test scripts/test-codex-hosted-search.mjs
)
nix build "path:$root#homeConfigurations.cc-se-sto-devbox-01.activationPackage" --no-link
