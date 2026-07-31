# Portable cargo-pgrx fallback for the devbox JCode swarm.
{
  pkgs,
  lib,
  hostname ? "",
  ...
}: let
  cargoPgrxWrapper = pkgs.writeShellScript "cargo-pgrx" ''
    exec ${pkgs.bash}/bin/bash ${./cargo-pgrx-wrapper.sh} \
      ${pkgs.nix}/bin/nix \
      /home/mhugo/code/singularity-engine \
      "$@"
  '';
in
  lib.mkIf (lib.toLower hostname == "cc-se-sto-devbox-01") {
    home.file.".local/bin/cargo-pgrx" = {
      source = cargoPgrxWrapper;
      executable = true;
      force = true;
    };
  }
