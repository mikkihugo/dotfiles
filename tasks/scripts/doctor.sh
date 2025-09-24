#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

cat <<REPORT
Dotfiles Doctor Report
======================
Root directory: $ROOT_DIR

- nix: $(nix --version 2>/dev/null || echo "not installed")
- node: $(node --version 2>/dev/null || echo "not installed")
- pnpm: $(pnpm --version 2>/dev/null || echo "not installed")
- python: $(python3 --version 2>/dev/null || echo "not installed")
- go: $(go version 2>/dev/null || echo "not installed")
- rust: $(rustc --version 2>/dev/null || echo "not installed")
REPORT
