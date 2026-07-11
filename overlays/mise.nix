# overlays/mise.nix — pin mise ahead of nixpkgs
#
# Why: nixos-26.05 (and even nixos-unstable) lag upstream mise. As of
# 2026-07-11 the stable channel ships 2025.11.7 while upstream is at 2026.7.5,
# which mise nags about on every invocation. The binary lives in the read-only
# Nix store, so `mise self-update` cannot work; the only correct upgrade path
# is to override the package version here.
#
# Remove this overlay once nixos-26.05 carries >= 2026.6.1 and let the normal
# flake bump take over. Verify with:
#   nix eval --raw github:NixOS/nixpkgs/nixos-26.05#mise.version
#
# Hashes are produced by:
#   nix-prefetch-url --unpack https://github.com/jdx/mise/archive/refs/tags/vX.tar.gz
#   (vendor hash: build once with lib.fakeHash and read the mismatch)
final: prev: {
  mise = prev.mise.overrideAttrs (old: rec {
    version = "2026.7.5";
    src = prev.fetchFromGitHub {
      owner = "jdx";
      repo = "mise";
      tag = "v${version}";
      hash = "sha256-oHZXd9u+FbwOs60yrmg5oSnQoHskVCi29TRgu0RKOpM=";
    };
    cargoDeps = prev.rustPlatform.fetchCargoVendor {
      inherit src;
      name = "mise-${version}-vendor";
      hash = "sha256-JXipQn9gN5cJx6PSpDYHuxjYLNRyAwpjSaROxqSvIog=";
    };
  });
}
