# Devbox-only Rustup proxy wrappers for long-lived host shells.
{
  lib,
  pkgs,
  hostname ? "",
  ...
}: let
  wrapper = tool:
    pkgs.writeShellScript "managed-rustup-${tool}-1.95" ''
      exec ${pkgs.bash}/bin/bash ${./rustup-toolchain-wrapper.sh} ${tool} "$@"
    '';
in
  lib.mkIf (lib.toLower hostname == "cc-se-sto-devbox-01") {
    home.file = {
      ".local/bin/cargo" = {
        source = wrapper "cargo";
        executable = true;
        force = true;
      };
      ".local/bin/rustc" = {
        source = wrapper "rustc";
        executable = true;
        force = true;
      };
      ".local/bin/rustfmt" = {
        source = wrapper "rustfmt";
        executable = true;
        force = true;
      };
    };
  }
