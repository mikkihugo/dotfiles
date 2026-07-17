# home/modules/cursor-stable-shell.nix
#
# Cursor Agent Shell on NixOS fails when the sandbox tmpfs-hides /run, because
# login SHELL is /run/current-system/sw/bin/bash (passwd). /nix/store stays
# visible. Point SHELL at a user symlink into the store and GC-root that bash.
#
# Evidence: Cursor forum staff ack (sandbox hides /run on NixOS).
# CLI sandbox may already be disabled; this still protects IDE/sandbox-on.
{
  config,
  lib,
  pkgs,
  ...
}: let
  stableBash = "${config.home.homeDirectory}/.local/share/stable-shell/bash";
  refreshScript = ''
    #!/usr/bin/env bash
    set -euo pipefail
    STABLE="''${XDG_DATA_HOME:-$HOME/.local/share}/stable-shell/bash"
    mkdir -p "$(dirname "$STABLE")" "$HOME/.local/bin" \
      "''${XDG_DATA_HOME:-$HOME/.local/share}/gcroots"
    for candidate in \
      "$HOME/.nix-profile/bin/bash" \
      /run/current-system/sw/bin/bash
    do
      if [[ -x "$candidate" ]]; then
        target=$(${pkgs.coreutils}/bin/readlink -f "$candidate")
        ${pkgs.coreutils}/bin/ln -sfn "$target" "$STABLE"
        ${pkgs.coreutils}/bin/ln -sfn "$STABLE" "$HOME/.local/bin/bash"
        pkg=$(${pkgs.coreutils}/bin/dirname "$(${pkgs.coreutils}/bin/dirname "$target")")
        ${pkgs.coreutils}/bin/ln -sfn "$pkg" \
          "''${XDG_DATA_HOME:-$HOME/.local/share}/gcroots/bash-interactive"
        echo "stable-shell -> $target"
        exit 0
      fi
    done
    echo "refresh-stable-shell: no bash candidate found" >&2
    exit 1
  '';
in {
  home = {
    sessionVariables.SHELL = stableBash;

    file.".local/bin/refresh-stable-shell" = {
      executable = true;
      force = true;
      text = refreshScript;
    };

    activation.refreshStableShell = lib.hm.dag.entryAfter ["writeBoundary"] ''
      $DRY_RUN_CMD ${config.home.homeDirectory}/.local/bin/refresh-stable-shell \
        || $DRY_RUN_CMD bash -c ${lib.escapeShellArg refreshScript}
    '';
  };

  xdg.configFile."environment.d/90-stable-shell.conf" = {
    text = ''
      # Cursor sandbox hides /run on NixOS; keep SHELL on a store-backed path.
      SHELL=${stableBash}
    '';
    force = true;
  };
}
