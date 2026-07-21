#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
profile="$("$root/scripts/current-home-profile")"
"$root/scripts/test-repo-vcs.sh"
HOME_MANAGER_PROFILE="$profile" bash "$root/scripts/test-ast-grep-shim.sh"
python3 "$root/scripts/test-codex-preferences.py"
(
	cd "$root"
	node --test \
		scripts/test-codex-hosted-search.mjs \
		scripts/test-swarm-messages.mjs \
		scripts/test-swarm-hook-config.mjs \
		scripts/test-nix-tooling.mjs
)
# This gate evaluates exactly one activation package. Using nix-fast-build here
# adds no parallelism, while its nix-eval-jobs workers reread daemon-only Nix
# settings and contend on the shared evaluation cache. Keep nix-fast-build
# installed for multi-attribute builds; use Nix directly for this single target.
nix build --no-link "path:$root#homeConfigurations.${profile}.activationPackage"
