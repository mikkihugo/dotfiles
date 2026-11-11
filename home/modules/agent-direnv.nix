# agent-direnv.nix — emit direnv export scripts for agent shells (non-interactive)
#
# Prewarming is owned solely by the devbox NixOS module devshell-prewarm
# (/srv/infra/hosts/cc-se-sto-devbox-01/etc/nixos/devshell-prewarm.nix).
# BASH_ENV loads host v2 dumps via /srv/infra/scripts/agent-direnv-prebuilt-apply.sh.
{pkgs, ...}: let
  direnvAgent = pkgs.writeShellScriptBin "direnv-agent" ''
    set -u
    root="''${1:-}"
    [ -n "$root" ] || { echo "direnv-agent: usage: direnv-agent <root>" >&2; exit 2; }
    root=$(readlink -f "$root")
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
