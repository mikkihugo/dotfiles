{
  description = "mhugo dotfiles dev environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, flake-utils, home-manager, sops-nix }:
    let
      system = "aarch64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
    in
    {
      homeConfigurations."mhugo" = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        extraSpecialArgs = { inherit sops-nix; };
        modules = [ ./home/home.nix ];
      };
    } //
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };
      in {
        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            # Secret management tools (devShell for dotfiles maintenance)
            sops
            age
            ssh-to-age
            shellcheck
            shfmt
          ];

          shellHook = ''
            export DOTFILES_ROOT="$(pwd -P)"
            export PATH="$DOTFILES_ROOT/tasks:$PATH"

            export SOPS_AGE_KEY_FILE="$HOME/.config/sops/age/keys.txt"
            mkdir -p "$(dirname "$SOPS_AGE_KEY_FILE")"

            echo "dotfiles dev shell (system: ${system})"

            if [ -d secrets ] && [ "$(ls -A secrets 2>/dev/null)" ]; then
              echo "Available encrypted secrets:"
              ls -la secrets/
            fi

            alias age-keygen="ssh-to-age -i ~/.ssh/id_ed25519.pub"
            alias secrets-edit="sops secrets/tokens.yaml"
            alias secrets-view="sops -d secrets/tokens.yaml"
          '';
        };
      });
}
