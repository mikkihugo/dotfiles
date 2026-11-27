{
  pkgs,
  lib,
  hostname ? "",
  ...
}: let
  expire = pkgs.writeShellScript "home-trash-expire" ''
    set -eu
    state_dir="$HOME/.local/state/home-trash-expire"
    marker="$state_dir/started"
    ${pkgs.coreutils}/bin/mkdir -p "$state_dir"
    if [ ! -e "$marker" ]; then
      ${pkgs.coreutils}/bin/touch "$marker"
      exit 0
    fi
    now=$(${pkgs.coreutils}/bin/date +%s)
    started=$(${pkgs.coreutils}/bin/stat -c %Y "$marker")
    if [ "$((now - started))" -lt 259200 ]; then
      exit 0
    fi
    ${pkgs.trash-cli}/bin/trash-empty -f --trash-dir "$HOME/.local/share/Trash" 3
    uid=$(${pkgs.coreutils}/bin/id -u)
    for volume in /srv/infra/.worktrees "$HOME/code/singularity-engine/.worktrees"; do
      for trash_dir in "$volume/.Trash-$uid" "$volume/.Trash/$uid"; do
        if [ -d "$trash_dir" ]; then
          ${pkgs.trash-cli}/bin/trash-empty -f --trash-dir "$trash_dir" 3
        fi
      done
    done
  '';
in lib.mkIf (lib.toLower hostname == "cc-se-sto-devbox-01") {
  home.packages = [pkgs.trash-cli];

  systemd.user.services.home-trash-expire = {
    Unit.Description = "Expire items in home Trash after three days";
    Service = {
      Type = "oneshot";
      ExecStart = expire;
    };
  };

  systemd.user.timers.home-trash-expire = {
    Unit.Description = "Check home Trash for expired items hourly";
    Timer = {
      OnBootSec = "5min";
      OnUnitActiveSec = "1h";
    };
    Install.WantedBy = ["timers.target"];
  };
}
