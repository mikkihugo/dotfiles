{pkgs, ...}: let
  gcScript = pkgs.writeShellScript "jcode-gc" ''
    set -u
    J="$HOME/.jcode"

    # --- builds: keep the versions referenced by the *-version files ---
    keep=""
    for f in "$J"/builds/current-version "$J"/builds/shared-server-version \
             "$J"/builds/stable-version "$J"/builds/canary-version; do
        [ -f "$f" ] && keep="$keep $(${pkgs.coreutils}/bin/cat "$f" 2>/dev/null)"
    done
    if [ -d "$J/builds/versions" ]; then
        for d in "$J"/builds/versions/*; do
            [ -d "$d" ] || continue
            name=$(${pkgs.coreutils}/bin/basename "$d")
            case " $keep " in
                *" $name "*) continue ;; # active build, never delete
            esac
            # only delete if untouched for 3 days (recent rollback window)
            if [ "$(${pkgs.findutils}/bin/find "$d" -maxdepth 0 -mtime +3 2>/dev/null)" ]; then
                ${pkgs.coreutils}/bin/rm -rf "$d"
            fi
        done
    fi

    # --- logs: files older than 3 days (top level and memory/ rotation) ---
    ${pkgs.findutils}/bin/find "$J/logs" -type f -mtime +3 -delete 2>/dev/null

    # --- session backups, quarantine dirs, and stale sessions ---
    ${pkgs.findutils}/bin/find "$J/sessions" -maxdepth 1 -name '*.bak' -mtime +3 -delete 2>/dev/null
    ${pkgs.findutils}/bin/find "$J" -maxdepth 1 -type d -name 'sessions-quarantine-*' -mtime +3 -exec ${pkgs.coreutils}/bin/rm -rf {} + 2>/dev/null
    # full session files older than 30 days (resume history beyond that is dead weight)
    ${pkgs.findutils}/bin/find "$J/sessions" -maxdepth 1 -name 'session_*.json' -mtime +30 -delete 2>/dev/null

    # --- /tmp/jcode-* debris (test homes, diag logs, straces): entries older
    # than 3 days, but never the shared workspace build cache (deliberately
    # retained, held open by long-running jcode processes) ---
    for e in /tmp/jcode-*; do
        [ -e "$e" ] || continue
        case "$(${pkgs.coreutils}/bin/basename "$e")" in
            jcode-ws-target) continue ;;
        esac
        if [ "$(${pkgs.findutils}/bin/find "$e" -maxdepth 0 -mtime +3 2>/dev/null)" ]; then
            ${pkgs.coreutils}/bin/chmod -R u+w "$e" 2>/dev/null
            ${pkgs.coreutils}/bin/rm -rf "$e"
        fi
    done

    # --- scratch: entries older than 3 days, but never live IPC/cache dirs ---
    if [ -d "$J/scratch" ]; then
        for e in "$J"/scratch/*; do
            [ -e "$e" ] || continue
            case "$(${pkgs.coreutils}/bin/basename "$e")" in
                mix_lock_*|mix_pubsub_*|cargo-home) continue ;;
            esac
            if [ "$(${pkgs.findutils}/bin/find "$e" -maxdepth 0 -mtime +3 2>/dev/null)" ]; then
                ${pkgs.coreutils}/bin/chmod -R u+w "$e" 2>/dev/null
                ${pkgs.coreutils}/bin/rm -rf "$e"
            fi
        done
    fi
  '';
in {
  # Prune ~/.jcode artifacts that otherwise accumulate forever (old build
  # versions, rotated logs, session .bak snapshots, scratch workspaces) plus
  # /tmp/jcode-* test/diag debris.
  # Retention: 3d for builds/logs/baks/scratch/quarantine//tmp debris, 30d for
  # full session files; the active build version is never deleted, and the
  # shared /tmp/jcode-ws-target build cache is always kept.
  systemd.user.services.jcode-gc = {
    Unit = {
      Description = "Prune accumulated ~/.jcode artifacts (old builds, logs, session baks, scratch)";
      X-SwitchMethod = "keep-old";
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${gcScript}";
    };
  };

  systemd.user.timers.jcode-gc = {
    Unit.Description = "Daily jcode garbage collection";
    Timer = {
      OnCalendar = "*-*-* 04:17";
      Persistent = true;
      Unit = "jcode-gc.service";
    };
    Install.WantedBy = ["timers.target"];
  };
}
