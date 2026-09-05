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
# default. Set it at the last host-level entrypoint so stale agent/shell
# environments cannot select a newer compiler. Explicit `cargo +toolchain`
# remains Rustup's intentional per-command override.
export RUSTUP_TOOLCHAIN="1.95.0"
exec "$rustup_bin" run "$RUSTUP_TOOLCHAIN" "$tool" "$@"
