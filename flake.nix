# flake.nix — dotfiles entry point
#
# Purpose:
#   Single source of truth for the entire user environment. Two outputs:
#
#   1. homeConfigurations."mikki-bunker"  — the Home Manager profile applied
#      by `hms` on this machine.
#      Wires home/home.nix (packages, shell, git, tools) and sops-nix (secret
#      decryption hooks available for future use).
#
#   2. devShells.default  — a lightweight shell for dotfiles *maintenance*
#      (editing secrets, running alejandra/statix). Not the daily shell;
#      home-manager provides that.
#
# Requires --impure because builtins.currentSystem reads the host arch at
# eval time. The `hms` alias in home.nix already passes --impure.
{
  description = "Mikki-Bunker dotfiles — home-manager + SOPS";

  inputs = {
    # nixos-unstable: rolling channel with the newest packages.
    # Pin here so every `nix develop` / `home-manager switch` uses the same
    # nixpkgs snapshot across all machines.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # home-manager: declarative user-space config (dotfiles, packages, shell).
    # Follows our nixpkgs pin so there's exactly one nixpkgs in the closure.
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
    # builtins.currentSystem reads the host arch at eval time.
    # Requires --impure; already set in the `hms` shell alias.
    system = builtins.currentSystem;
    pkgs = import nixpkgs {
      inherit system;
      config.allowUnfree = true;
    };
    # Single definition reused for both config-name and username-based lookups.
    homeConfig = home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      # Pass sops-nix so home.nix can use sops.secrets.* if needed in future.
      extraSpecialArgs = {
        inherit sops-nix ace-coder;
      };
      modules = [./home/home.nix];
    };
  in
    {
      # `home-manager switch --flake .#mikki-bunker --impure`
      homeConfigurations."mikki-bunker" = homeConfig;
      # Username alias: home-manager auto-detects by $USER when no #name is given,
      # so `home-manager switch --flake ~/.config/home-manager --impure` works.
      homeConfigurations."mhugo" = homeConfig;
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
