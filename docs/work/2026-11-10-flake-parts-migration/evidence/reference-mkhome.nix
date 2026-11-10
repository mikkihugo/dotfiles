# Same-tree reference for the home-manager equivalence check (T2).
#
# Reconstructs the PRE-CHANGE mkHome mechanism — `import nixpkgs { overlays =
# [inline overlay]; }` with the overlay inlined verbatim from the old
# flake.nix — and returns each profile's activationPackage outPath. The
# home-manager generations embed the flake source tree (the repo's home
# modules reference tree paths), so their outPaths move with ANY file
# addition; comparing against the pre-change baseline would flag the tree,
# not the refactor. Comparing the new flake's generations against this
# reference at the SAME tree state isolates the refactor's effect: any
# divergence here is caused by the module restructure, never by tree content.
#
# Usage: nix eval --json --impure --expr 'import ./reference-mkhome.nix'
#
# The flake MUST be resolved as a git+file ref, not a bare path:
# `builtins.getFlake (toString ./.)` under --impure copies the whole
# directory (including .jj/, .direnv/, result), producing a DIFFERENT
# source tree than `.#` evaluation, which uses the git-aware copy. The
# starship config path in the session vars exposed the divergence.
let
  flake = builtins.getFlake "git+file:///home/mhugo/.dotfiles";
  inherit (flake) inputs;
  inherit (inputs) nixpkgs home-manager sops-nix llm-agents direnv-instant engine-nixpkgs-pin;
  src = flake.outPath;
  specialArgs = {inherit sops-nix llm-agents direnv-instant engine-nixpkgs-pin;};

  # Mirrors flake/overlay.nix as of the 2026-11-10 single-sourcing: the
  # guard wrapper comes from the infra flake input (flake = false source),
  # replacing the removed vendored copy.
  overlay = _final: prev: let
    direnvExportShellGuard = "${inputs.infra}/hosts/_shared/direnv-export-shell-guard.nix";
    sys = prev.stdenv.hostPlatform.system;
    direnvBase = (import inputs.nixpkgs-direnv {system = sys;}).direnv;
  in {
    ast-grep = inputs.nixpkgs-unstable.legacyPackages.${sys}.ast-grep;
    inherit (inputs.nixpkgs-unstable.legacyPackages.${sys}) ripgrep;
    direnv = prev.callPackage direnvExportShellGuard {direnv = direnvBase;};
    inherit (import inputs.nixpkgs-jujutsu {system = sys;}) jujutsu;
    inherit (inputs.nixpkgs-unstable.legacyPackages.${sys}) mise;
    vultr-cli = inputs.nixpkgs-unstable.legacyPackages.${sys}."vultr-cli";
    nix-index = prev.nix-index.overrideAttrs (old: {
      buildCommand =
        old.buildCommand
        + ''
          command_not_found=$out/etc/profile.d/command-not-found.sh
          command_not_found_source=$(readlink -f "$command_not_found")
          rm -f "$command_not_found"
          cp "$command_not_found_source" "$command_not_found"
          chmod u+w "$command_not_found"
          substituteInPlace "$command_not_found" \
            --replace-fail "nix profile install" "nix profile add"
        '';
    });
  };

  mkHomeOld = sys: hostname: let
    pkgs = import nixpkgs {
      system = sys;
      config.allowUnfree = true;
      overlays = [overlay];
    };
    toolchain = import (src + "/home/lib/toolchain.nix") pkgs;
    home = home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      extraSpecialArgs =
        specialArgs
        // {
          targetSystem = sys;
          inherit hostname toolchain;
        };
      modules = [
        direnv-instant.homeModules.direnv-instant
        (src + "/home/home.nix")
      ];
    };
  in
    (home
      // {
        activationPackage = home.activationPackage.overrideAttrs (old: {
          buildCommand =
            old.buildCommand
            + ''
              substituteInPlace $out/activate \
                --replace-fail "profile install" "profile add"
            '';
        });
      }).activationPackage;

  profiles = {
    "mikki-bunker" = {
      sys = "x86_64-linux";
      hostname = "mikki-bunker";
    };
    "mikki-laptop" = {
      sys = "aarch64-linux";
      hostname = "mikki-laptop";
    };
    "cc-se-sto-devbox-01" = {
      sys = "x86_64-linux";
      hostname = "cc-se-sto-devbox-01";
    };
    "mhugo" = {
      sys = "x86_64-linux";
      hostname = "";
    };
  };
in
  builtins.mapAttrs (_name: p: (mkHomeOld p.sys p.hostname).outPath) profiles
