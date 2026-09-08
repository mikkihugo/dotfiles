#!/usr/bin/env bash
# Forces the managed host toolchain for the Rustup proxy entrypoints that
# long-lived shells may have cached before Home Manager changed the Mise pin.
#
# Falls back to the next real tool on PATH when the pinned toolchain cannot
# execute. That is not hypothetical: on 2026-09-08 every rustup toolchain
# binary on cc-se-sto-devbox-01 failed to exec, and because these wrappers own
# PATH position 1 they shadowed a perfectly good nix-store cargo. Rustup's own
# message for that is `error: command failed: 'cargo': No such file or
# directory (os error 2)`, which surfaces deep inside an unrelated build and
# reads as if the caller's code broke -- it cost a full debugging cycle and
# blocked every `repo vcs land` whose gate compiles a Rust binary.
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

# Probe once per boot, not per invocation: a `--version` spawn on every cargo
# call would tax every build. Only success is cached, so a repaired toolchain
# is picked up on the next probe rather than staying latched to the fallback.
probe_dir="${XDG_RUNTIME_DIR:-/tmp}/managed-rustup-toolchain"
probe_ok="${probe_dir}/${tool}-${toolchain}.ok"
if [[ -e "$probe_ok" ]] || "$rustup_bin" run "$toolchain" "$tool" --version >/dev/null 2>&1; then
	mkdir -p "$probe_dir" 2>/dev/null || true
	: >"$probe_ok" 2>/dev/null || true
	export RUSTUP_TOOLCHAIN="$toolchain"
	exec "$rustup_bin" run "$toolchain" "$tool" "$@"
fi

# Pinned toolchain is unusable. Prefer a working tool over a broken pin, and
# say so on stderr every time -- silence here is what made the original
# failure so expensive to trace. Skip the directories these wrappers own, or
# the fallback would re-enter this script.
managed_dirs=("${HOME}/.local/bin" "${HOME}/.cargo/bin")
IFS=':' read -r -a path_entries <<<"${PATH}"
for dir in "${path_entries[@]}"; do
	[[ -n "$dir" ]] || continue
	skip=0
	for managed in "${managed_dirs[@]}"; do
		[[ "$dir" == "$managed" ]] && skip=1
	done
	((skip)) && continue
	candidate="$dir/$tool"
	[[ -x "$candidate" ]] || continue
	# Probe rather than trust: the first candidate on PATH is often ANOTHER
	# proxy onto the same broken toolchain (mise shims delegate to rustup
	# too), so an unprobed fallback just reproduces the original failure with
	# a different path in the message.
	"$candidate" --version >/dev/null 2>&1 || continue
	echo "managed-rustup-toolchain: pinned toolchain ${toolchain} cannot exec '${tool}'; falling back to ${candidate}" >&2
	exec "$candidate" "$@"
done

echo "managed-rustup-toolchain: pinned toolchain ${toolchain} cannot exec '${tool}' and no unmanaged '${tool}' is on PATH" >&2
exit 127
