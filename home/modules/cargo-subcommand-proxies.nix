# Overwrites rustup's own self-installed cargo-<subcommand> proxies with
# Nix-managed binaries.
#
# The rustup-toolchain-wrappers module (removed in d8cd0e26) only ever
# declared plain cargo/rustc/rustfmt at ~/.local/bin and ~/.cargo/bin.
# rustup itself separately installs ~/.cargo/bin/cargo-fmt,
# ~/.cargo/bin/cargo-clippy, and ~/.cargo/bin/clippy-driver as its OWN
# symlinks, pointing at ~/.cargo/bin/rustup -- home-manager never declared
# or managed those paths, so removing the wrapper module does nothing to
# them.
#
# This matters because cargo resolves `cargo-<subcommand>` from
# $CARGO_HOME/bin FIRST, regardless of PATH (verified 2026-09-08 by
# claude-674f9a3f: stripping every proxy from PATH and confirming
# `command -v rustfmt` resolved to a working nix binary still left
# `cargo fmt` hitting the dead rustup toolchain -- only redirecting
# CARGO_HOME away from ~/.cargo, or overriding $RUSTFMT directly, changed
# the outcome). So `cargo fmt` / `cargo clippy` kept routing into rustup's
# toolchain -- which can lose a transitively-linked shared library to an
# ordinary nix GC sweep, same failure class as the 2026-09-08 incident this
# whole migration exists to fix -- even after the plain cargo/rustc/rustfmt
# proxies were removed.
#
# `cargo-miri` is deliberately NOT covered: miri is a nightly-only rustup
# component with no stable nixpkgs package, same accepted gap as the
# `cargo +nightly` call-sites documented in
# /srv/infra hosts/_shared/rust-toolchain.nix.
{
  pkgs,
  lib,
  hostname ? "",
  ...
}:
lib.mkIf (lib.toLower hostname == "cc-se-sto-devbox-01") {
  home.file = {
    ".cargo/bin/cargo-fmt" = {
      source = "${pkgs.rustfmt}/bin/cargo-fmt";
      force = true;
    };
    ".cargo/bin/cargo-clippy" = {
      source = "${pkgs.clippy}/bin/cargo-clippy";
      force = true;
    };
    ".cargo/bin/clippy-driver" = {
      source = "${pkgs.clippy}/bin/clippy-driver";
      force = true;
    };
  };
}
