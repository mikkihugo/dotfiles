# direnv export-shell guard overlay fragment.
#
# The guard itself is vendored in config/direnv/ (see flake.nix); this
# fragment only wires it to the pinned direnv package.
{
  direnvExportShellGuard,
  nixpkgs-direnv,
  system,
}: final: _prev: let
  direnvBase = (import nixpkgs-direnv {inherit system;}).direnv;
in {
  direnv = final.callPackage direnvExportShellGuard {
    direnv = direnvBase;
  };
}
