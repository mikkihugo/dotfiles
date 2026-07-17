#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
"$root/scripts/test-repo-vcs.sh"
nix build "path:$root#homeConfigurations.cc-se-sto-devbox-01.activationPackage" --no-link
