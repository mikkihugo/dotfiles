{pkgs, ...}: let
  gcScript = pkgs.writeShellScript "jcode-gc" ''
    set -u
    J="$HOME/.jcode"

    # --- builds: pruned by jcode itself ---
    #
    # Removed 2026-10-23. jcode's Rust already owns this:
    # crates/jcode-build-support/src/lib.rs calls prune_unreferenced_versions()
    # with PRUNE_KEEP_RECENT headroom, and protects every referenced version
    # (server symlink, per-channel markers, pending rollback targets, canary).
    # The comment that used to sit here recorded the same lesson this timer
    # duplicated: guarding only one reference path deleted the dirs behind the
    # CLI launcher and the channel markers.
    #
    # Kept here originally as "a safety net for local builds"; it was in fact a
    # second, weaker copy of a routine that already runs in-process. One owner
    # per rule, so a retention change lands in jcode and not in two places.

    # --- logs: files older than 3 days (top level and memory/ rotation) ---
    ${pkgs.findutils}/bin/find "$J/logs" -type f -mtime +3 -delete 2>/dev/null

    # --- session quarantine dirs and stale sessions ---
    #
    # The '*.bak' rule that used to sit here was removed 2026-10-23:
    # crates/jcode-base/src/session/maintenance.rs prunes session backups
    # itself (BACKUP_RETENTION_DAYS = 30), rate-limited to one walk per 24h
    # across every jcode process by a sessions-bak-prune.stamp marker, because
    # that directory holds 100k+ entries and is the largest CPU cost of TUI
    # startup. The in-process owner is both stricter and cheaper.
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
  # Prune ~/.jcode artifacts that otherwise accumulate forever, plus
  # /tmp/jcode-* test/diag debris.
  #
  # Scope (2026-10-23): jcode's own Rust now owns build-version pruning and
  # session .bak pruning, so this timer covers only what it does not: rotated
  # logs, session quarantine dirs, stale session transcripts, scratch
  # workspaces and /tmp debris. One owner per rule.
  # Retention: 3d for logs/quarantine/scratch//tmp debris, 30d for full
  # session files; the shared /tmp/jcode-ws-target build cache and the scratch
  # cargo-home are always kept.
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
