#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

if command -v shellcheck >/dev/null 2>&1; then
	echo "👉 Running shellcheck on shell scripts"
	mapfile -t sh_files < <(rg -l -I --glob '!archive/**' '^#!.*(sh|bash|zsh)([[:space:]]|$)' shell bootstrap tasks bin scripts tools .scripts home config 2>/dev/null | sort)
	if [[ ${#sh_files[@]} -gt 0 ]]; then
		shellcheck --external-sources "${sh_files[@]}"
	fi
else
	echo "⚠️  shellcheck not found. Install via package manager or cargo." >&2
fi

if command -v shfmt >/dev/null 2>&1; then
	echo "👉 Checking formatting with shfmt"
	mapfile -t sh_files < <(rg -l -I --glob '!archive/**' '^#!.*(sh|bash|zsh)([[:space:]]|$)' shell bootstrap tasks bin scripts tools .scripts home config 2>/dev/null | sort)
	if [[ ${#sh_files[@]} -gt 0 ]]; then
		shfmt -d "${sh_files[@]}"
	fi
else
	echo "ℹ️  shfmt not available; skipping format check." >&2
fi
