#!/usr/bin/env bash
set -euo pipefail

if (($# < 2)); then
	echo "cargo-pgrx: internal wrapper requires Nix binary and Engine fallback root" >&2
	exit 64
fi

nix_bin="$1"
fallback_root="$2"
shift 2

if [[ "$nix_bin" != /* || ! -x "$nix_bin" || "$fallback_root" != /* ]]; then
	echo "cargo-pgrx: internal wrapper received invalid runtime paths" >&2
	exit 64
fi

if [[ "${CARGO_PGRX_NIX_WRAPPER_ACTIVE:-0}" == "1" ]]; then
	echo "cargo-pgrx: Engine Nix shell resolved the wrapper recursively" >&2
	exit 126
fi

is_engine_root() {
	local root="$1"
	[[ -f "$root/Cargo.toml" &&
		-f "$root/fabrics/data/Cargo.toml" &&
		-f "$root/fabrics/data/flake.nix" &&
		-f "$root/fabrics/data/nix/flake/packages.nix" ]]
}

search_dir="$PWD"
engine_root=""
while [[ "$search_dir" != "/" ]]; do
	if is_engine_root "$search_dir"; then
		engine_root="$search_dir"
		break
	fi
	search_dir="${search_dir%/*}"
	[[ -n "$search_dir" ]] || search_dir="/"
done

if [[ -z "$engine_root" ]]; then
	if ! is_engine_root "$fallback_root"; then
		echo "cargo-pgrx: Engine workspace and fallback root are unavailable" >&2
		exit 127
	fi
	engine_root="$fallback_root"
fi

flake_dir="$engine_root/fabrics/data"
cd "$flake_dir"
export CARGO_PGRX_NIX_WRAPPER_ACTIVE=1
exec "$nix_bin" develop "path:$flake_dir" --command cargo-pgrx "$@"
