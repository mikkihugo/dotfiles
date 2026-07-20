#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
profile="$("$root/scripts/current-home-profile")"
"$root/scripts/test-repo-vcs.sh"
python3 "$root/scripts/test-codex-preferences.py"
(
	cd "$root"
	node --test \
		scripts/test-codex-hosted-search.mjs \
		scripts/test-swarm-messages.mjs \
		scripts/test-swarm-hook-config.mjs \
		scripts/test-nix-tooling.mjs
)
nix-fast-build --flake "path:$root#homeConfigurations.${profile}.activationPackage" --no-link
