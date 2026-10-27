# agent-direnv.nix — instant direnv envs for agent shells (non-interactive)
#
# Trigger model (2026-10-27, operator steer): no fixed high-frequency timer.
# (a) direnv-agent self-heals: on a stale/missing snapshot it kicks the prewarm
#     service (no-block) and falls back to the queued export;
# (b) systemd path units watch .envrc/flake.nix/flake.lock per root and fire
#     the prewarm within seconds of a repo-config change;
# (c) an hourly janitor timer is the only backstop.
{
  lib,
  pkgs,
  ...
}: let
  prewarmScript = ./scripts/agent-direnv-prewarm.sh;

  # direnv-agent <root> — serve a prewarmed direnv env for eval, or fall back
  # to the real (queued) direnv export. Snapshot trusted only when its stored
  # .envrc/flake fingerprint matches and it is younger than 24h.
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
    fp_snap=$(${pkgs.coreutils}/bin/sed -n 2p "$snap/fingerprint" 2>/dev/null || true)
    fresh=true
    gen_at=$(${pkgs.coreutils}/bin/sed -n 3p "$snap/fingerprint" 2>/dev/null || echo 0)
    [ "$(date -u -d "$gen_at" +%s 2>/dev/null || echo 0)" -lt $(( $(date -u +%s) - 86400 )) ] && fresh=false

    if [ -s "$snap/env" ] && [ "$fp_now" = "$fp_snap" ] && $fresh; then
      cat "$snap/env"
      echo "direnv-agent: served prewarmed env for $root (snapshot $gen_at)" >&2
      exit 0
    fi
    # Self-heal: kick the prewarm; emit the queued export script for the
    # caller's eval — a child process cannot change the parent env, so the
    # fallback path must OUTPUT the script (direct export, never eval here).
    systemctl --user start --no-block agent-direnv-prewarm.service 2>/dev/null || true
    echo "direnv-agent: no fresh snapshot for $root; kicked prewarm; emitting queued export script" >&2
    cd -- "$root" || exit 1
    exec env DIRENV_LOG_FORMAT= "${pkgs.direnv}/bin/direnv" export bash
  '';

  prewarmUnit = {
    Unit.Description = "Prewarm agent direnv envs (on-demand, change- and janitor-triggered)";
    Service = {
      Type = "oneshot";
      ExecStart = "${pkgs.bash}/bin/bash ${prewarmScript}";
      Nice = 19;
      IOSchedulingClass = "idle";
    };
  };

  pathUnit = root: files:
    lib.listToAttrs (lib.imap0 (i: f: {
        name = "agent-direnv-path-${baseNameOf root}-${toString i}";
        value = {
          Unit.Description = "Prewarm agent direnv on ${f} change in ${baseNameOf root}";
          Path = {
            PathChanged = "${root}/${f}";
            PathExists = "${root}/.envrc";
          };
          Install.WantedBy = ["paths.target"];
          Wants = ["agent-direnv-prewarm.service"];
        };
      })
      files);

  jcodePathUnits = pathUnit "/home/mhugo/code/jcode" [".envrc" "flake.nix" "flake.lock"];
  infraPathUnits = pathUnit "/srv/infra" [".envrc" "flake.nix" "flake.lock"];
  enginePathUnits = pathUnit "/home/mhugo/code/singularity-engine" [".envrc" "flake.nix" "flake.lock"];
in {
  home.packages = [direnvAgent];

  systemd.user = {
    services.agent-direnv-prewarm = prewarmUnit;
    paths = jcodePathUnits // infraPathUnits // enginePathUnits;
    timers.agent-direnv-prewarm = {
      Unit.Description = "Janitor backstop for agent direnv prewarm";
      Timer = {
        OnCalendar = "hourly";
        RandomizedDelaySec = "10m";
        Persistent = true;
      };
      Install.WantedBy = ["timers.target"];
    };
  };
}
