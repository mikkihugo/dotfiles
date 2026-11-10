# Per-system outputs: formatter, checks, packages.home-manager,
# devShells.default. Imported by flake/default.nix through flake-parts'
# perSystem module system; `system` and the configured `pkgs` are bound by
# flake/default.nix, so this file carries no per-system boilerplate of its
# own.
#
# These outputs use plain nixpkgs (allowUnfree, no dotfiles overlay) — the
# overlay is owned by flake/overlay.nix and only home configurations apply
# it (via home-configurations.nix). Maintenance outputs and home
# configurations therefore stay independently substitutable.
{
  pkgs,
  system,
  inputs',
  nixpkgs-jujutsu-src,
  ...
}: {
  # `nix fmt` runs alejandra on every .nix file in the repo.
  formatter = pkgs.alejandra;

  # `nix flake check` runs the same lint chain the pre-commit hook
  # enforces. Canonical Nix shape: each check is a NAMED derivation
  # under `checks.<system>` (not a single derivation per system;
  # that's the schema trap because an unnamed `checks.<sys> =
  # derivation;` is read as a derivation whose `.outPath` is then
  # checked as if it were itself a derivation).
  #
  # src: `..` is the flake root — the module file lives in flake/, and
  # the flake source is a single store tree, so this is byte-identical to
  # the `./.` the inline flake.nix used before the modular split.
  checks = {
    format =
      pkgs.runCommand "dotfiles-format-check-${system}" {
        src = ../.;
        buildInputs = [pkgs.alejandra];
      } ''
        cd "$src"
        alejandra --check .
        touch $out
      '';
    statix-check =
      pkgs.runCommand "dotfiles-statix-check-${system}" {
        src = ../.;
        buildInputs = [pkgs.statix];
      } ''
        cd "$src"
        statix check .
        touch $out
      '';
    deadnix-check =
      pkgs.runCommand "dotfiles-deadnix-check-${system}" {
        src = ../.;
        buildInputs = [pkgs.deadnix];
      } ''
        cd "$src"
        # 1.3 dropped --no-unused/--error. --fail matches lefthook.
        deadnix --fail .
        touch $out
      '';
    jujutsu-pin = let
      pinned = import nixpkgs-jujutsu-src {inherit system;};
    in
      pkgs.runCommand "dotfiles-jujutsu-pin-${system}" {
        inherit (pinned.jujutsu) version;
      } ''
        test "$version" = 0.47.1
        printf '%s\n' "$version" > "$out"
      '';
    vultr-cli-pin =
      pkgs.runCommand "dotfiles-vultr-cli-pin-${system}" {
        inherit (inputs'.nixpkgs-unstable.legacyPackages."vultr-cli") version;
      } ''
        test "$version" = 3.11.0
        printf '%s\n' "$version" > "$out"
      '';
  };

  # Bootstrap runner from the same locked Home Manager input used to build
  # the profiles. `nix run path:.#home-manager -- switch ...` therefore
  # cannot drift to a mutable Home Manager branch.
  packages.home-manager = inputs'.home-manager.packages.home-manager;

  # `nix develop` — for editing secrets and running dotfiles linters.
  # Not the daily shell (home-manager provides that); this shell is
  # only needed when working on the dotfiles repo itself.
  devShells.default = pkgs.mkShell {
    packages = with pkgs; [
      go_1_27 # Engine contract (versions.json languages.go.attr)
      cargo # build and validate local Rust tools
      nodejs_26 # run Node contract tests from the canonical repo check
      python314 # Engine contract (versions.json languages.python.attr)
      nix-fast-build # parallel activation evaluation/build for `repo check`
      gnumake # native builds in the maintenance shell
      pkg-config # native dependency discovery for rust crates when needed
      sops # encrypt/decrypt secrets/api-keys.yaml
      age # age key generation and encryption backend
      ssh-to-age # derive age public key from SSH ed25519 key
      shellcheck # lint shell scripts
      shfmt # format shell scripts
    ];

    shellHook = ''
      export DOTFILES_ROOT="$(pwd -P)"
      export PATH="$DOTFILES_ROOT/bin:$PATH"
      # Contract tests scope this immutable Git path to child processes
      # that need native Git while keeping the agent-facing facade intact.
      export SE_GIT_BIN="${pkgs.git}/bin/git"
      export SOPS_AGE_KEY_FILE="$HOME/.config/sops/age/keys.txt"
      mkdir -p "$(dirname "$SOPS_AGE_KEY_FILE")"

      echo "dotfiles maintenance shell (${system})"
      echo "  secrets-view  — decrypt and print api-keys.yaml"
      echo "  secrets-edit  — open api-keys.yaml in \$EDITOR via sops"
      echo "  age-keygen    — print age pubkey derived from SSH key"

      # Convenience aliases for the secrets workflow.
      # sops set/unset must be used for in-place edits (never redirect stdout
      # back to the same file — sops overwrites it atomically).
      alias age-keygen="ssh-to-age -i ~/.ssh/id_ed25519.pub"
      alias secrets-edit="sops secrets/api-keys.yaml"
      alias secrets-view="sops -d secrets/api-keys.yaml"
    '';
  };
}
