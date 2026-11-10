# The dotfiles tool-version overlay — single source of truth for every
# package whose version deliberately differs from the pinned nixpkgs
# release. Consumed only by flake/home-configurations.nix: mkHome imports
# nixpkgs with this overlay, so every home configuration shares these pins.
#
# Parameters are the flake inputs the overrides draw from; keeping them
# explicit makes the overlay independently importable (and testable).
{
  nixpkgs-unstable,
  nixpkgs-jujutsu,
  nixpkgs-direnv,
  infra,
}: _final: prev: let
  sys = prev.stdenv.hostPlatform.system;
  # Canonical wrapper, single-sourced from the infra flake input (replaces a
  # vendored copy that had drifted from it; see
  # docs/work/2026-11-10-flake-parts-migration).
  direnvExportShellGuard = "${infra}/hosts/_shared/direnv-export-shell-guard.nix";
  direnvBase = (import nixpkgs-direnv {system = sys;}).direnv;
in {
  # jujutsu 0.47.1 comes from the exact nixpkgs-jujutsu input.
  # 26.05 still ships 0.41.0. Do not take it from nixpkgs-unstable.
  #
  # mise 2026.10.3: pull from nixpkgs-unstable for newer version
  # (26.05 has 2026.5.12, unstable has 2026.10.3)
  #
  # ripgrep 15.2.0: pull from nixpkgs-unstable for the .jj VCS
  # detection + gitignore-across-dirs fixes (#3212/#3320/#3376).
  # 26.05 has 15.1.0, where cwd-based rg inside jj lanes
  # intermittently returns exit 1 / zero results (verified on
  # cc-se-sto-devbox-01 2026-10-27, reproducible 10/10).
  #
  # direnv 2.38.2 + export-shell guard (AIP-193-style CLI errors).
  ast-grep = nixpkgs-unstable.legacyPackages.${sys}.ast-grep;
  inherit (nixpkgs-unstable.legacyPackages.${sys}) ripgrep;
  direnv = prev.callPackage direnvExportShellGuard {
    direnv = direnvBase;
  };
  inherit (import nixpkgs-jujutsu {system = sys;}) jujutsu;
  inherit (nixpkgs-unstable.legacyPackages.${sys}) mise;
  # vultr-cli 3.11.0: from nixpkgs-unstable so the Nix build serves
  # the same version mise served (3.11.0; nixos-26.05 ships 3.10.0).
  # The vultr-cli-pin check fails loudly if this input moves.
  # cntb is NOT a nix package here anymore: it is a manual pinned
  # binary at ~/.local/share/cntb/cntb, driven through the
  # ~/.local/bin/cntb -> cntb-bao shim (OpenBao credentials).
  vultr-cli = nixpkgs-unstable.legacyPackages.${sys}."vultr-cli";
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
}
