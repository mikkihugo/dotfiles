#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
home_nix="$root/home/home.nix"
activation_nix="$root/home/modules/activation.nix"

for expected in \
	"XDG_CACHE_HOME = \"\$HOME/.cache\"" \
	"CARGO_HOME = \"\$HOME/.cargo\"" \
	"MIX_HOME = \"\$HOME/.cache/mix\"" \
	"HEX_HOME = \"\$HOME/.cache/hex\"" \
	"\"npm_config_cache\" = \"\$HOME/.cache/npm\""; do
	grep -Fq "$expected" "$home_nix" || {
		printf 'missing managed cache variable: %s\n' "$expected" >&2
		exit 1
	}
done

grep -Fq 'normalizeLanguageCaches' "$activation_nix" || {
	printf 'missing activation cache migration\n' >&2
	exit 1
}
grep -Fq "cp -a \"\$old\"/. \"\$new\"/" "$activation_nix" || {
	printf 'missing safe merge for pre-existing cache targets\n' >&2
	exit 1
}

printf 'language cache layout contract: ok\n'
