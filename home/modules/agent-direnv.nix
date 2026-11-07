# agent-direnv.nix — instant direnv envs for agent shells (non-interactive)
#
# Prewarming is owned by the host's /srv/infra NixOS module. This user module
# only serves snapshots and provides a queue-tolerant fallback export.
{pkgs, ...}: let
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
      [ -e "$root/$f" ] && fp_now="''${fp_now}$(printf '%s %s ' "$f" "$(stat -c '%Y %s' "$root/$f")")"
    done
    fp_snap=$("${pkgs.gnused}/bin/sed" '1d;$d' "$snap/fingerprint" 2>/dev/null || true)
    fresh=true
    gen_at=$(${pkgs.coreutils}/bin/tail -n 1 "$snap/fingerprint" 2>/dev/null || echo 0)
    [ "$(date -u -d "$gen_at" +%s 2>/dev/null || echo 0)" -lt $(( $(date -u +%s) - 86400 )) ] && fresh=false

    if [ -s "$snap/env" ] && [ "$fp_now" = "$fp_snap" ] && $fresh; then
      cat "$snap/env"
      echo "direnv-agent: served prewarmed env for $root (snapshot $gen_at)" >&2
      exit 0
    fi
    # Emit the queued export script for the
    # caller's eval — a child process cannot change the parent env, so the
    # fallback path must OUTPUT the script (direct export, never eval here).
    echo "direnv-agent: no fresh snapshot for $root; emitting queued export script" >&2
    cd -- "$root" || exit 1
    # Queue-tolerant: raise the repo .envrc's own lock timeout (jcode honors
    # JCODE_DIRENV_LOCK_TIMEOUT_S, engine SE_DIRENV_LOCK_TIMEOUT_SECONDS) so
    # the fallback WAITS IN THE QUEUE instead of giving up at 120s during the
    # fleet eval storm. Retries are the last resort if even that fails.
    out=""
    for attempt in 1 2 3; do
      out=$(env DIRENV_LOG_FORMAT= JCODE_DIRENV_LOCK_TIMEOUT_S=540 SE_DIRENV_LOCK_TIMEOUT_SECONDS=540 "${pkgs.direnv}/bin/direnv" export bash)
      [ -n "$out" ] && break
      sleep 45
    done
    printf '%s\n' "$out"
  '';
in {
  home.packages = [direnvAgent];
}
