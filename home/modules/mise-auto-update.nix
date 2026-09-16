{pkgs, ...}: let
  updateScript = pkgs.writeShellScript "mise-auto-update" ''
    set -euo pipefail

    export HOME="/home/mhugo"
    export MISE_YES=1
    export MISE_JOBS=4
    export PATH="${pkgs.mise}/bin:${pkgs.python3}/bin:${pkgs.coreutils}/bin:${pkgs.bash}/bin:$PATH"

    mise_bin="${pkgs.mise}/bin/mise"
    if [ ! -x "$mise_bin" ]; then
      echo "mise-auto-update: mise missing at $mise_bin" >&2
      exit 0
    fi

    # Python is nixpkgs-owned. Drop any leftover mise python so shims cannot
    # shadow ~/.nix-profile/bin/python3 on the next login.
    "$mise_bin" uninstall python --all --yes >/dev/null 2>&1 || true
    ${pkgs.coreutils}/bin/rm -f \
      "$HOME/.local/share/mise/shims/python" \
      "$HOME/.local/share/mise/shims/python3"

    "$mise_bin" install --yes
    "$mise_bin" upgrade --yes

    # install/upgrade read ~/.config/mise/config.toml, which may still be a
    # symlink to a stale ~/.dotfiles checkout that pins python=latest.
    "$mise_bin" uninstall python --all --yes >/dev/null 2>&1 || true
    ${pkgs.coreutils}/bin/rm -f \
      "$HOME/.local/share/mise/shims/python" \
      "$HOME/.local/share/mise/shims/python3"
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
