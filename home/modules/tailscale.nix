# home/modules/tailscale.nix — tailscale client auto-join via headscale
#
# Joins this machine to the private mesh at vpn.hugo.dk (headscale). System
# daemon (tailscaled) is installed by bootstrap/steps/40-tailscale.sh because
# home-manager can't create system services on non-NixOS. This module only:
#   1. exposes the `tailscale` CLI in the user profile (handy for tailscale status)
#   2. on every hms, calls `tailscale up` with the authkey from SOPS if not
#      already logged into the correct login_server
#
# Pre-auth key is reusable + 1-year TTL. Rotate by generating a new key on
# vpn.hugo.dk (`headscale preauthkeys create --user 1 --reusable`) and
# `sops secrets/api-keys.yaml` to update.
{
  config,
  pkgs,
  lib,
  ...
}: {
  sops.secrets.tailscale_authkey = {
    key = "tailscale/authkey";
    mode = "0400";
  };
  sops.secrets.tailscale_login_server = {
    key = "tailscale/login_server";
    mode = "0400";
  };

  home.packages = [pkgs.tailscale];

  home.activation.tailscaleJoin = lib.hm.dag.entryAfter ["writeBoundary" "sops-nix"] ''
    if ! command -v ${pkgs.tailscale}/bin/tailscale >/dev/null 2>&1; then
      echo "tailscale binary not in PATH — skipping join"
      exit 0
    fi
    if ! systemctl is-active --quiet tailscaled 2>/dev/null; then
      echo "tailscaled system service not running — run bootstrap/steps/40-tailscale.sh first"
      exit 0
    fi

    _login_server=$(cat ${config.sops.secrets.tailscale_login_server.path} 2>/dev/null || echo "")
    _authkey=$(cat ${config.sops.secrets.tailscale_authkey.path} 2>/dev/null || echo "")
    [ -n "$_login_server" ] && [ -n "$_authkey" ] || { echo "tailscale secrets not decrypted yet — skipping"; exit 0; }

    _current=$(${pkgs.tailscale}/bin/tailscale status --json 2>/dev/null | \
      ${pkgs.jq}/bin/jq -r '.Self.Online // false, .CurrentTailnet.Name // "none"' | \
      ${pkgs.coreutils}/bin/tr '\n' ' ')

    # Already up on our login_server → skip. Re-running tailscale up is safe
    # but triggers an interactive browser auth flow even with --authkey when
    # the state file exists — avoid the noise on every hms.
    if echo "$_current" | ${pkgs.gnugrep}/bin/grep -q "^true "; then
      echo "tailscale: already online ($_current)"
    else
      echo "tailscale: joining $_login_server..."
      sudo ${pkgs.tailscale}/bin/tailscale up \
        --login-server="$_login_server" \
        --authkey="$_authkey" \
        --hostname="$(${pkgs.hostname}/bin/hostname)" \
        --accept-routes \
        --reset || echo "tailscale up failed (non-fatal)" >&2
    fi
  '';
}
