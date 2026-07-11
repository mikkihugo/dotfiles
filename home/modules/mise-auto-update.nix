{pkgs, ...}: let
  updateScript = pkgs.writeShellScript "mise-auto-update" ''
    set -euo pipefail

    export HOME="/home/mhugo"
    export MISE_YES=1
    export MISE_JOBS=4
    export PATH="${pkgs.nix}/bin:${pkgs.mise}/bin:$HOME/.local/share/mise/shims:${pkgs.coreutils}/bin:${pkgs.bash}/bin:$PATH"

    mise_bin="${pkgs.mise}/bin/mise"
    if [ ! -x "$mise_bin" ]; then
      echo "mise-auto-update: mise missing at $mise_bin" >&2
      exit 0
    fi

    cd "$HOME/.dotfiles"
    ${pkgs.nix}/bin/nix --extra-experimental-features 'nix-command flakes' develop "$HOME/.dotfiles" --command just mise-upgrade
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
