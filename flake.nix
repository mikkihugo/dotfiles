# flake.nix — dotfiles entry point
#
# Purpose:
#   Single source of truth for the entire user environment. Profiles:
#
#   homeConfigurations."mikki-bunker"  — x86_64 WSL2 desktop
#   homeConfigurations."mikki-laptop"  — aarch64 laptop
#   homeConfigurations."cc-se-sto-devbox-01" — x86_64 fleet devbox
#   homeConfigurations."mhugo"         — generic x86_64 fallback
#
#   devShells.default  — lightweight shell for dotfiles maintenance.
#
# This file declares inputs only. All outputs are wired through flake-parts
# by the module files under flake/ (flake/default.nix is the entry):
# per-system outputs in flake/per-system.nix, home configurations in
# flake/home-configurations.nix, tool-version pins in flake/overlay.nix.
# flake-utils was removed 2026-11-10; see
# docs/work/2026-11-10-flake-parts-migration.
#
{
  description = "mhugo dotfiles — home-manager + SOPS (multi-arch)";

  nixConfig = {
    extra-substituters = [
      "https://cache.flakecache.com/default"
      "https://nix-community.cachix.org"
      "https://cache.numtide.com"
    ];
    extra-trusted-public-keys = [
      "default:ESyvaQTiq681JA0iaH5tsQWS+R5qqJUVdVY1OXbi9to="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
    ];
    accept-flake-config = true;
    fallback = true;
    connect-timeout = 5;
  };

  inputs = {
    # NixOS 26.05 release branch: stable base for the user environment.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    # Fleet-canonical nixpkgs rev (Rust toolchain packages, Engine/jcode alignment).
    # Bump only in Engine nix/toolchains/nixpkgs-pin; consumers follow nixpkgs.
    engine-nixpkgs-pin.url = "git+ssh://git@git.centralcloud.net:2222/singularity/singularity-engine?dir=nix/toolchains/nixpkgs-pin";

    # Unstable provides selected tools that lag in nixos-26.05: mise and
    # ast-grep. Drop each override when the stable input meets its contract.
    # jujutsu is not on this input. A channel update must not move it.
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Exact jujutsu 0.47.1. nixos-26.05 still ships 0.41.0. This rev is the
    # nixpkgs commit whose pkgs/by-name/ju/jujutsu/package.nix sets
    # version = "0.47.1". Bump the URL on purpose.
    nixpkgs-jujutsu = {
      url = "github:NixOS/nixpkgs/3becb8ab5af12344c3b0cfb93314f99eaf430213";
      flake = false;
    };

    # direnv 2.38.2 (published 2026-10-10). nixos-26.05 ships 2.37.1 and the
    # nixpkgs-unstable pin (6510408d147d, 2026-10-10 01:01Z) predates the
    # 2.38.2 packaging later that day. This rev is the nixos-unstable channel
    # commit that packages 2.38.2. Bump the URL on purpose.
    nixpkgs-direnv = {
      url = "github:NixOS/nixpkgs/3ec636362e1816bc2f0888fa0fa2c69f1bc9e504";
      flake = false;
    };

    # Home Manager release branch follows the matching nixpkgs release.
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # sops-nix: home-manager module that can decrypt SOPS secrets at
    # activation time and expose them as files/env vars. Wired into
    # extraSpecialArgs so home.nix can opt in when needed.
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # flake-parts: single module system for all per-system outputs. Its lib
    # input is named nixpkgs-lib in v1.x; following our nixpkgs keeps the
    # lock on one nixpkgs tree. Replaced flake-utils 2026-11-10.
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };

    # llm-agents: daily-updated Nix packages for AI coding agents (codex,
    # gemini-cli, opencode, amp, goose-cli, cursor-agent, droid, …).
    # Intentionally NOT following our nixpkgs — cache hits depend on the exact
    # store paths numtide built; overriding nixpkgs invalidates all of them.
    llm-agents.url = "github:numtide/llm-agents.nix";

    # Non-blocking interactive direnv hooks. Keep this as an explicit input
    # until the pinned nixpkgs release exports the package.
    direnv-instant = {
      url = "github:Mic92/direnv-instant/1.3.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Canonical source of the direnv export-shell guard wrapper
    # (hosts/_shared/direnv-export-shell-guard.nix). flake/overlay.nix wraps
    # pkgs.direnv with it; the previous vendored copy under config/direnv
    # drifted from this canonical implementation and was removed
    # 2026-11-10. flake = false: only the source tree is consumed (like
    # nixpkgs-jujutsu) — infra's own outputs and input closure, including
    # its stale jcode/engine pins, are never evaluated.
    infra = {
      url = "git+ssh://git@git.centralcloud.net:2222/centralcloud/infra";
      flake = false;
    };
  };

  outputs = inputs @ {flake-parts, ...}:
    flake-parts.lib.mkFlake {inherit inputs;} {
      imports = [./flake];
    };
}
