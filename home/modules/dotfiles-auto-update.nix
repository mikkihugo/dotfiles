{
  config,
  pkgs,
  ...
}: let
  profileScript = "${config.home.homeDirectory}/.dotfiles/scripts/current-home-profile";
  updateScript = pkgs.writeShellScript "dotfiles-auto-update" ''
    set -euo pipefail

    export HOME="${config.home.homeDirectory}"
    repo="$HOME/.dotfiles"

    if [ ! -d "$repo/.git" ]; then
      echo "dotfiles-auto-update: repo missing at $repo"
      exit 0
    fi

    cd "$repo"

    if ! ${pkgs.git}/bin/git diff --quiet || ! ${pkgs.git}/bin/git diff --cached --quiet; then
      echo "dotfiles-auto-update: repo has local changes, skipping"
      exit 0
    fi

    ${pkgs.git}/bin/git fetch --quiet origin

    upstream="$(${pkgs.git}/bin/git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null || true)"
    if [ -z "$upstream" ]; then
      echo "dotfiles-auto-update: no upstream configured, skipping"
      exit 0
    fi

    local_rev="$(${pkgs.git}/bin/git rev-parse HEAD)"
    remote_rev="$(${pkgs.git}/bin/git rev-parse "$upstream")"
    if [ "$local_rev" = "$remote_rev" ]; then
      echo "dotfiles-auto-update: already up to date"
      exit 0
    fi

    ${pkgs.git}/bin/git pull --ff-only --quiet
    profile="$(${profileScript})"
    ${config.programs.home-manager.package}/bin/home-manager switch --flake "$repo#$profile" --impure
  '';
in {
  systemd.user.services.dotfiles-auto-update = {
    Unit = {
      Description = "Pull dotfiles and apply Home Manager when upstream changes";
      After = ["network-online.target"];
      Wants = ["network-online.target"];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${updateScript}";
    };
  };

  systemd.user.timers.dotfiles-auto-update = {
    Unit.Description = "Periodically update dotfiles and Home Manager";
    Timer = {
      OnBootSec = "3min";
      OnUnitActiveSec = "15min";
      Persistent = true;
      Unit = "dotfiles-auto-update.service";
    };
    Install.WantedBy = ["timers.target"];
  };
}
