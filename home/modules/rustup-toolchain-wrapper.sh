#!/usr/bin/env bash
# Forces the managed host toolchain for the Rustup proxy entrypoints that
# long-lived shells may have cached before Home Manager changed the Mise pin.
set -euo pipefail

tool="${1:?missing Rust entrypoint name}"
rustup_bin="${2:?missing Rustup executable}"
shift 2

if [[ ! -x "$rustup_bin" ]]; then
	echo "managed-rustup-toolchain: Rustup executable missing: $rustup_bin" >&2
	exit 127
fi

# An inherited RUSTUP_TOOLCHAIN wins over rust-toolchain files and Rustup's
# default. Select the managed default at the last host-level entrypoint so
# stale agent/shell environments cannot select a newer compiler. Rustup's
# explicit `cargo +toolchain` selector remains an intentional one-command
# override and must be parsed before invoking `rustup run`.
toolchain="1.95.0"
if [[ "${1:-}" == +* ]]; then
	toolchain="${1#+}"
	shift
fi
export RUSTUP_TOOLCHAIN="$toolchain"
exec "$rustup_bin" run "$toolchain" "$tool" "$@"
