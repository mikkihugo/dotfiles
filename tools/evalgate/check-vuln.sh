#!/usr/bin/env bash
# Vulnerability proof for evalgate (FOSDEM-2025 Go-in-Nix program:
# govulncheck-nixpkgs pattern — reachability-based scanning over pinned Go
# deps). Run alongside check-deps-fresh.sh and go test as the proof chain.
# Per-dep derivations make a vulnerable module a visible, patchable Nix input.
set -euo pipefail
cd "$(dirname "$0")"
export GOCACHE="${GOCACHE:-$HOME/.cache/go-build}" # stable cache (GOCACHEPROG lesson)
go run golang.org/x/vuln/cmd/govulncheck@latest ./... && echo "evalgate vuln scan clean"
