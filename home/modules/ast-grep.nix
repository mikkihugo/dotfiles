# home/modules/ast-grep.nix — deterministic structural-search entrypoints
{pkgs, ...}: let
  sgShim = pkgs.writeShellScript "sg" ''
    exec ${pkgs.ast-grep}/bin/ast-grep "$@"
  '';
in {
  home.packages = [pkgs.ast-grep];

  # ast-grep's historical CLI name collides with the system `sg` group
  # utility. ~/.local/bin precedes /run/wrappers/bin in every managed shell,
  # so this explicit shim gives agents one stable structural-search command.
  home.file.".local/bin/sg" = {
    source = sgShim;
    executable = true;
    force = true;
  };
}
