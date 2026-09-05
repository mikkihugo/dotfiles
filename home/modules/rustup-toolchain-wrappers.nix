# Devbox-only Rustup proxy wrappers for long-lived host shells.
{
  lib,
  pkgs,
  hostname ? "",
  ...
}: let
  wrapper = tool:
    pkgs.writeShellScript "managed-rustup-${tool}-1.95" ''
      exec ${pkgs.bash}/bin/bash ${./rustup-toolchain-wrapper.sh} \
        ${tool} ${pkgs.rustup}/bin/rustup "$@"
    '';
  entrypoint = tool: {
    source = wrapper tool;
    executable = true;
    force = true;
  };
in
  lib.mkIf (lib.toLower hostname == "cc-se-sto-devbox-01") {
    home.file = {
      ".local/bin/cargo" = entrypoint "cargo";
      ".local/bin/rustc" = entrypoint "rustc";
      ".local/bin/rustfmt" = entrypoint "rustfmt";
      # Bash's command hash can retain the Rustup proxy location that preceded
      # this Home Manager generation. Own those canonical paths too, so a
      # long-lived shell still enters the pinned toolchain on its next command.
      ".cargo/bin/cargo" = entrypoint "cargo";
      ".cargo/bin/rustc" = entrypoint "rustc";
      ".cargo/bin/rustfmt" = entrypoint "rustfmt";
    };
  }
