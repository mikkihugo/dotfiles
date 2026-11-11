# Infra-sourced direnv export-shell guard overlay fragment.
{
  infra,
  nixpkgs-direnv,
  system,
}: final: _prev: let
  direnvBase = (import nixpkgs-direnv {inherit system;}).direnv;
in {
  direnv = final.callPackage "${infra}/hosts/_shared/direnv-export-shell-guard.nix" {
    direnv = direnvBase;
  };
}
