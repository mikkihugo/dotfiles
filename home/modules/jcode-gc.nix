{pkgs, ...}: let
  gcScript = pkgs.writeShellScript "jcode-gc" ''
    set -u
    J="$HOME/.jcode"

    # --- builds: never delete a version that a live reference points at;
    # prune the rest after 3 days. CI prunes to 10 on deploy, but run GC as a
    # safety net for local builds ---
    #
    # FOUR things reference builds/versions, not one. Guarding only the server
    # symlink deleted the dirs behind the CLI launcher and all three channel
    # markers (dotfiles#49): the server stayed healthy precisely because it was
    # the single protected path. readlink -f still yields the intended target
    # for an already-dangling link, which is what we want -- a broken reference
    # must not make its target eligible for deletion.
    protected="$(
        for ref in "$J/server/jcode" "$J/builds/current/jcode"; do
            ${pkgs.coreutils}/bin/readlink -f "$ref" 2>/dev/null || true
        done
        for marker in current-version stable-version shared-server-version; do
            marker_version="$(${pkgs.coreutils}/bin/cat "$J/builds/$marker" 2>/dev/null || true)"
            if [ -n "$marker_version" ]; then
                ${pkgs.coreutils}/bin/printf '%s\n' "$J/builds/versions/$marker_version/jcode"
            fi
        done
    )"
    if [ -d "$J/builds/versions" ]; then
        # Delete versions older than 3 days that no live reference points at
        for d in "$J"/builds/versions/*; do
            [ -d "$d" ] || continue
            if ${pkgs.coreutils}/bin/printf '%s\n' "$protected" \
                | ${pkgs.gnugrep}/bin/grep -Fxq "$d/jcode"; then continue; fi
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
  # full session files; any build version referenced by the server symlink, the
  # CLI launcher (builds/current), or a channel marker is never deleted, and
  # the shared /tmp/jcode-ws-target build cache is always kept.
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
