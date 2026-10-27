# agent-direnv.nix — instant direnv envs for agent shells (non-interactive)
{pkgs, ...}: let
  prewarmScript = ./scripts/agent-direnv-prewarm.sh;

  # direnv-agent <root> — serve a prewarmed direnv env for eval, or fall back
  # to the real (queued) direnv export. The snapshot is trusted only when its
  # stored .envrc / flake.nix / flake.lock fingerprint matches the root now and
  # the snapshot is younger than 24h; anything else falls back to the queued
  # path, which is correct-by-construction even when the prewarm service is
  # dead.
  direnvAgent = pkgs.writeShellScriptBin "direnv-agent" ''
    set -u
    root="''${1:-}"
    [ -n "$root" ] || { echo "direnv-agent: usage: direnv-agent <root>" >&2; exit 2; }
    root=$(readlink -f "$root")
    hash=$(printf '%s' "$root" | ${pkgs.coreutils}/bin/sha256sum | cut -d" " -f1)
    snap="''${AGENT_DIRENV_STATE:-$HOME/.cache/agent-direnv}/$hash"

    fp_now=""
    for f in .envrc flake.nix flake.lock; do
      [ -e "$root/$f" ] && fp_now="''${fp_now}$(printf '%s %s\n' "$f" "$(stat -c '%Y %s' "$root/$f")")"
    done
    fp_snap=$(${pkgs.coreutils}/bin/tail -n +2 "$snap/fingerprint" 2>/dev/null || true)
    age_ok=true
    gen_at=$(${pkgs.coreutils}/bin/tail -n +3 "$snap/fingerprint" 2>/dev/null || echo 0)
    if [ "$(date -u -d "$gen_at" +%s 2>/dev/null || echo 0)" -lt $(( $(date -u +%s) - 86400 )) ]; then
      age_ok=false
    fi

    if [ -s "$snap/env" ] && [ "$fp_now" = "$fp_snap" ] && $age_ok; then
      cat "$snap/env"
      echo "direnv-agent: served prewarmed env for $root (snapshot $gen_at)" >&2
      exit 0
    fi
    echo "direnv-agent: no fresh snapshot for $root; falling back to queued direnv export" >&2
    cd -- "$root" || exit 1
    eval "$(env DIRENV_LOG_FORMAT= "${pkgs.direnv}/bin/direnv" export bash)"
  '';
in {
  home.packages = [direnvAgent];

  # Keep each root's direnv cache warm and the agent snapshot fresh.
  systemd.user.services.agent-direnv-prewarm = {
    Unit.Description = "Prewarm agent direnv envs for whitelisted roots";
    Service = {
      Type = "oneshot";
      ExecStart = "${pkgs.bash}/bin/bash ${prewarmScript}";
      Nice = 19;
      IOSchedulingClass = "idle";
      # Fail-open janitor: a failed cycle must not wedge the timer.
      RuntimeMaxSec = "1800";
    };
  };
  systemd.user.timers.agent-direnv-prewarm = {
    Unit.Description = "Prewarm agent direnv envs on a cadence";
    Timer = {
      OnCalendar = "*-*-* *:3/15:00"; # :03, :18, :33, :48 — off the :00/:30 herd
      Persistent = true;
    };
    Install.WantedBy = ["timers.target"];
  };
}
