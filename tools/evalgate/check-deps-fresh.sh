#!/usr/bin/env bash
# Freshness check for the gomod2nix lock (ADR-0097 *2nix doctrine).
# Fails when go.mod/go.sum changed without regenerating gomod2nix.toml:
#   nix run github:nix-community/gomod2nix -- generate
# Wired into repo test; run from anywhere.
set -euo pipefail
cd "$(dirname "$0")"
export GOCACHE="${GOCACHE:-$HOME/.cache/go-build}" # stable cache (GOCACHEPROG lesson)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cp go.mod go.sum gomod2nix.toml "$tmp/"
nix run github:nix-community/gomod2nix -- generate >/dev/null 2>&1
if ! diff -q "$tmp/gomod2nix.toml" gomod2nix.toml >/dev/null; then
	cp "$tmp/gomod2nix.toml" gomod2nix.toml # restore pristine copy
	echo "evalgate deps stale: go.mod/go.sum changed without regenerating gomod2nix.toml" >&2
	echo "fix: nix run github:nix-community/gomod2nix -- generate (in tools/evalgate)" >&2
	exit 1
fi
echo "evalgate deps fresh"
