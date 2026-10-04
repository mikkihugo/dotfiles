#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
tmp_home="$(mktemp -d)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf -- "$tmp_home" "$tmp_dir"' EXIT

if HOME="$tmp_home" CODEX_ROLLOUT_GC_AGE_DAYS=-1 "$root/scripts/codex-rollout-gc.sh" >"$tmp_dir/negative.out" 2>&1; then
	echo "FAIL: negative retention was accepted" >&2
	exit 1
fi
grep -q 'must be an integer from 1 to 3650' "$tmp_dir/negative.out"
echo "codex rollout GC rejects unsafe retention values"
