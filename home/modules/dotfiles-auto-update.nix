{pkgs, ...}: let
  observerScript = pkgs.writeShellScript "dotfiles-auto-update" ''
    set -euo pipefail

    export HOME="/home/mhugo"
    repo="$HOME/.dotfiles"
    state_dir="$HOME/.local/state/dotfiles-observer"
    state_file="$state_dir/last-status"

    if [ ! -d "$repo/.git" ]; then
      echo "dotfiles-auto-update: repo missing at $repo"
      exit 0
    fi

    cd "$repo"

    ${pkgs.git}/bin/git fetch --quiet origin

    upstream="$(${pkgs.git}/bin/git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null || true)"
    if [ -z "$upstream" ]; then
      upstream="origin/main"
      if ! ${pkgs.git}/bin/git rev-parse --verify "$upstream" >/dev/null 2>&1; then
        echo "dotfiles-auto-update: no upstream configured, skipping"
        exit 0
      fi
    fi

    counts="$(${pkgs.git}/bin/git rev-list --left-right --count HEAD..."$upstream")"
    local_ahead="$(${pkgs.gawk}/bin/awk '{print $1}' <<<"$counts")"
    remote_ahead="$(${pkgs.gawk}/bin/awk '{print $2}' <<<"$counts")"
    dirty_count="$(${pkgs.git}/bin/git status --porcelain | ${pkgs.gawk}/bin/awk 'END {print NR + 0}')"

    status="up-to-date"
    summary="dotfiles: local and remote are in sync"
    if [ "$remote_ahead" -gt 0 ] && [ "$local_ahead" -gt 0 ]; then
      status="diverged:''${local_ahead}:''${remote_ahead}"
      summary="dotfiles diverged: local +''${local_ahead}, remote +''${remote_ahead}"
    elif [ "$remote_ahead" -gt 0 ]; then
      status="remote-ahead:''${remote_ahead}"
      summary="dotfiles remote is ahead by ''${remote_ahead} commit(s)"
    elif [ "$local_ahead" -gt 0 ]; then
      status="local-ahead:''${local_ahead}"
      summary="dotfiles has ''${local_ahead} unpushed local commit(s)"
    fi
    if [ "$dirty_count" -gt 0 ]; then
      if [ "$status" = "up-to-date" ]; then
        status="dirty:''${dirty_count}"
        summary="dotfiles has ''${dirty_count} uncommitted change(s)"
      else
        status="''${status}:dirty:''${dirty_count}"
        summary="''${summary}; ''${dirty_count} uncommitted change(s)"
      fi
    fi

    mkdir -p "$state_dir"
    previous=""
    if [ -f "$state_file" ]; then
      previous="$(cat "$state_file")"
    fi

    if [ "$status" != "$previous" ]; then
      printf '%s\n' "$status" > "$state_file"
      if [ "$status" != "up-to-date" ]; then
        ${pkgs.libnotify}/bin/notify-send "Dotfiles status" "$summary" || \
          echo "dotfiles-auto-update: $summary"
      fi
    else
      echo "dotfiles-auto-update: unchanged status ($status)"
      exit 0
    fi
  '';
in {
  systemd.user.services.dotfiles-auto-update = {
    # User managers do not own the system network-online target. The hourly
    # timer is the retry boundary when a fetch encounters transient network
    # failure, so no cross-manager ordering dependency is needed here.
    Unit.Description = "Observe dotfiles remote status and notify on drift";
    Service = {
      Type = "oneshot";
      ExecStart = "${observerScript}";
    };
  };

  systemd.user.timers.dotfiles-auto-update = {
    Unit.Description = "Periodically check dotfiles remote status";
    Timer = {
      # Use a wall-clock schedule so Persistent can catch up after downtime.
      # Monotonic-only anchors can leave a long-lived user manager unarmed.
      OnCalendar = "hourly";
      RandomizedDelaySec = "5min";
      Persistent = true;
      Unit = "dotfiles-auto-update.service";
    };
    Install.WantedBy = ["timers.target"];
  };
}
