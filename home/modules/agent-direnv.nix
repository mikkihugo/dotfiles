# agent-direnv.nix — emit direnv export scripts for agent shells (non-interactive)
#
# Prewarming is owned solely by the devbox NixOS module devshell-prewarm
# (/srv/infra/hosts/cc-se-sto-devbox-01/etc/nixos/devshell-prewarm.nix).
# BASH_ENV loads host v2 dumps via /srv/infra/scripts/agent-direnv-prebuilt-apply.sh.
{
  lib,
  pkgs,
  hostname,
  ...
}: let
  prebuiltOnly = lib.toLower hostname == "cc-se-sto-devbox-01";
  direnvAgent = pkgs.writeShellScriptBin "direnv-agent" ''
    set -u
    root="''${1:-}"
    [ -n "$root" ] || { echo "direnv-agent: usage: direnv-agent <root>" >&2; exit 2; }
    root=$(readlink -f "$root")

    if [ "${lib.optionalString prebuiltOnly "1"}" = 1 ] || [ "''${AGENT_DIRENV_PREBUILT_ONLY:-}" = 1 ]; then
      helper="$HOME/.dotfiles/shell/bash/agent-direnv-prebuilt-apply.sh"
      tmp=$(${pkgs.coreutils}/bin/mktemp -d) || exit 75
      if [ -r "$helper" ]; then
        . "$helper"
        if agent_direnv_prebuilt_write_snapshot "$root" "$tmp"; then
          if cat "$tmp/env"; then
            result=0
          else
            result=$?
          fi
          rm -f "$tmp/env" "$tmp/fingerprint"
          rmdir "$tmp"
          exit "$result"
        fi
      fi
      rm -f "$tmp/env" "$tmp/fingerprint"
      rmdir "$tmp"
      echo "direnv-agent: no valid prebuilt export for $root" >&2
      exit 75
    fi

    echo "direnv-agent: emitting queued export for $root (use BASH_ENV for host prebuilt)" >&2
    cd -- "$root" || exit 1
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
