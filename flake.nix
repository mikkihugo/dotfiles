{
  description = "mhugo dotfiles dev environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";
    flake-utils.url = "github:numtide/flake-utils";
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, flake-utils, sops-nix }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };
      in {
        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            # Languages & runtimes
            nodejs_20
            pnpm
            python312
            poetry
            go_1_22
            rustup
            cargo
            gcc

            # Shell utilities
            git
            git-lfs
            gitui
            zsh
            nushell
            starship
            zoxide
            direnv
            nix-direnv
            mise
            ripgrep
            fd
            fzf
            bat
            eza
            delta
            tmate
            eternal-terminal
            tmux
            htop
            cloudflared
            tailscale
            openssh
            jq
            yq
            shellcheck
            shfmt
            unzip
            wget
            curl

            # Secret management tools
            sops
            age
            ssh-to-age
          ];

          shellHook = ''
            export DOTFILES_ROOT="$(pwd -P)"
            export PATH="$DOTFILES_ROOT/tasks:$PATH"

            # SOPS setup
            export SOPS_AGE_KEY_FILE="$HOME/.config/sops/age/keys.txt"
            mkdir -p "$(dirname "$SOPS_AGE_KEY_FILE")"

            echo "Entering dotfiles dev shell with SOPS-nix (system: ${system})"

            # Show available secrets (if any)
            if [ -d secrets ] && [ "$(ls -A secrets 2>/dev/null)" ]; then
              echo "Available encrypted secrets:"
              ls -la secrets/
            fi

            # Helper functions
            alias age-keygen="ssh-to-age -i ~/.ssh/id_ed25519.pub"
            alias secrets-edit="sops secrets/tokens.yaml"
            alias secrets-view="sops -d secrets/tokens.yaml"
          '';
        };
      });
}
