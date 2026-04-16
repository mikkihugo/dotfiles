# flake.nix — dotfiles entry point
#
# Purpose:
#   Single source of truth for the entire user environment. Profiles:
#
#   homeConfigurations."mikki-bunker"  — x86_64 WSL2 desktop (GPU worker, CUDA)
#   homeConfigurations."mikki-laptop"  — aarch64 laptop (no GPU, no CUDA)
#   homeConfigurations."mhugo"         — username alias, resolves to current host
#
#   devShells.default  — lightweight shell for dotfiles maintenance.
#
# Requires --impure because builtins.currentSystem reads host arch at eval time.
# The `hms` alias already passes --impure.
{
  description = "mhugo dotfiles — home-manager + SOPS (multi-arch)";

  inputs = {
    # nixos-unstable: rolling pre-release tracking towards 26.05 (due ~May 2026).
    # Switch to nixos-26.05 + home-manager/release-26.05 once that branch exists.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # home-manager: master follows unstable nixpkgs.
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # sops-nix: home-manager module that can decrypt SOPS secrets at
    # activation time and expose them as files/env vars. Wired into
    # extraSpecialArgs so home.nix can opt in when needed.
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # flake-utils: builds the devShell for all default systems without
    # copy-pasting the per-system boilerplate.
    flake-utils.url = "github:numtide/flake-utils";

    # ace-coder: pinned clean source for the CUDA worker package and HM module.
    # Use a committed git revision from the local repo, not the live dirty tree,
    # so worker builds remain cacheable and reproducible.
    ace-coder.url = "git+file:///home/mhugo/code/ace-coder?ref=main";
  };

  outputs = {
    self,
    nixpkgs,
    home-manager,
    sops-nix,
    flake-utils,
    ace-coder,
  }: let
    # builtins.currentSystem reads host arch at eval time — requires --impure.
    # The `hms` alias already passes --impure.
    system = builtins.currentSystem;
    pkgs = import nixpkgs {
      inherit system;
      config.allowUnfree = true;
    };
    specialArgs = {inherit sops-nix ace-coder;};

    # Single home.nix works on all arches — GPU service is gated by lib.optionals.
    # targetSystem is passed as specialArgs so imports can branch without
    # referencing pkgs (which would cause infinite recursion in imports).
    mkHome = sys:
      home-manager.lib.homeManagerConfiguration {
        pkgs = import nixpkgs {
          system = sys;
          config.allowUnfree = true;
        };
        extraSpecialArgs = specialArgs // {targetSystem = sys;};
        modules = [./home/home.nix];
      };
  in
    {
      homeConfigurations = {
        # mikki-bunker: x86_64 WSL2 desktop (GPU worker enabled via lib.optionals).
        "mikki-bunker" = mkHome "x86_64-linux";
        # mikki-laptop: aarch64 portable machine (GPU worker skipped automatically).
        "mikki-laptop" = mkHome "aarch64-linux";
        # Username alias — resolves to current host arch via builtins.currentSystem.
        "mhugo" = mkHome system;
      };
    }
    // flake-utils.lib.eachDefaultSystem (sys: let
      maintenance-pkgs = import nixpkgs {
        system = sys;
        config.allowUnfree = true;
      };
    in {
      # `nix develop` — for editing secrets and running dotfiles linters.
      # Not the daily shell (home-manager provides that); this shell is
      # only needed when working on the dotfiles repo itself.
      devShells.default = maintenance-pkgs.mkShell {
        packages = with maintenance-pkgs; [
          sops # encrypt/decrypt secrets/api-keys.yaml
          age # age key generation and encryption backend
          ssh-to-age # derive age public key from SSH ed25519 key
          shellcheck # lint shell scripts
          shfmt # format shell scripts
        ];

        shellHook = ''
          export DOTFILES_ROOT="$(pwd -P)"
          export SOPS_AGE_KEY_FILE="$HOME/.config/sops/age/keys.txt"
          mkdir -p "$(dirname "$SOPS_AGE_KEY_FILE")"

          echo "dotfiles maintenance shell (${sys})"
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
    });
}
