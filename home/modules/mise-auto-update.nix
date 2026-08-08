{
  lib,
  pkgs,
  ...
}: let
  pythonBuildDeps = with pkgs; [
    openssl
    zlib
    bzip2
    xz
    zstd
    libffi
    readline
    sqlite
    ncurses
    gdbm
    tcl
    tk
  ];
  buildPath = lib.makeBinPath ([pkgs.gnumake pkgs.pkg-config pkgs.gcc] ++ pythonBuildDeps);
  includeFlags = lib.concatMapStringsSep " " (dep: "-I${lib.getDev dep}/include") pythonBuildDeps;
  libraryFlags = lib.concatMapStringsSep " " (dep: "-L${lib.getLib dep}/lib -Wl,-rpath,${lib.getLib dep}/lib") pythonBuildDeps;
  pkgConfigPath = lib.concatStringsSep ":" [
    (lib.makeSearchPath "lib/pkgconfig" (map lib.getDev pythonBuildDeps))
    (lib.makeSearchPath "share/pkgconfig" (map lib.getDev pythonBuildDeps))
  ];
  updateScript = pkgs.writeShellScript "mise-auto-update" ''
    set -euo pipefail

    export HOME="/home/mhugo"
    export MISE_YES=1
    export MISE_JOBS=4
    export PATH="${pkgs.mise}/bin:$HOME/.local/share/mise/shims:${buildPath}:${pkgs.coreutils}/bin:${pkgs.bash}/bin:$PATH"
    export NIX_CFLAGS_COMPILE="${includeFlags} ''${NIX_CFLAGS_COMPILE:-}"
    export NIX_LDFLAGS="${libraryFlags} ''${NIX_LDFLAGS:-}"
    export PKG_CONFIG_PATH="${pkgConfigPath}''${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"

    mise_bin="${pkgs.mise}/bin/mise"
    if [ ! -x "$mise_bin" ]; then
      echo "mise-auto-update: mise missing at $mise_bin" >&2
      exit 0
    fi

    "$mise_bin" install --yes
    "$mise_bin" upgrade --yes
  '';
in {
  systemd.user.services.mise-auto-update = {
    Unit = {
      Description = "Update mise and mise-managed tools";
      After = ["network-online.target"];
      Wants = ["network-online.target"];
    };
    Service = {
      Type = "oneshot";
      Nice = 10;
      IOSchedulingClass = "idle";
      ExecStart = "${updateScript}";
    };
  };

  systemd.user.timers.mise-auto-update = {
    Unit.Description = "Periodically update mise-managed tools";
    Timer = {
      OnCalendar = "*-*-* 04:30:00";
      RandomizedDelaySec = "1h";
      Persistent = true;
      Unit = "mise-auto-update.service";
    };
    Install.WantedBy = ["timers.target"];
  };
}
