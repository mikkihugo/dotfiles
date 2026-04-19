# home/modules/tailscale.nix — install + join headscale via hms
#
# Now that bootstrap/steps/02-sudoers.sh grants NOPASSWD sudo, the system
# parts (apt install, systemctl enable, tailscale up) run from a hm
# activation hook. No bootstrap step needed.
#
# Idempotent: skips install if tailscaled is active, skips `tailscale up`
# if the node is already online on our login_server.
#
# Rotate authkey: generate a new one on vpn.hugo.dk
#   docker exec headscale headscale preauthkeys create --user 1 --reusable --expiration 8760h
# then `sops secrets/api-keys.yaml` to update, then hms.
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

  home.activation.tailscaleSystem = lib.hm.dag.entryAfter ["sops-nix"] ''
    # Use absolute paths — hm activation env doesn't include /usr/bin in
    # PATH on all setups, and we want the system tools (not nix shadows).
    SYSTEMCTL=/usr/bin/systemctl
    SUDO=/usr/bin/sudo

    # Install daemon if missing. apt-get is the right path on Debian/Ubuntu/WSL2;
    # the upstream tailscale install script handles repo setup the first time.
    if ! command -v /usr/sbin/tailscale >/dev/null && ! command -v /usr/bin/tailscale >/dev/null; then
      echo "[tailscale] installing system daemon via upstream script…"
      $SUDO sh -c "curl -fsSL https://tailscale.com/install.sh | sh"
    fi

    if ! $SYSTEMCTL is-active --quiet tailscaled 2>/dev/null; then
      echo "[tailscale] enabling tailscaled…"
      $SUDO $SYSTEMCTL enable --now tailscaled
      for _ in 1 2 3 4 5; do
        [ -S /var/run/tailscale/tailscaled.sock ] && break
        sleep 1
      done
    fi

    # Already online on our login_server? Skip.
    _state=$($SUDO /usr/bin/tailscale status --json 2>/dev/null | ${pkgs.jq}/bin/jq -r '.BackendState // ""')
    if [ "$_state" = "Running" ]; then
      echo "[tailscale] already online — $($SUDO /usr/bin/tailscale status --self=true --peers=false 2>/dev/null | head -1)"
      exit 0
    fi

    _login_server=$(cat ${config.sops.secrets.tailscale_login_server.path} 2>/dev/null || echo "")
    _authkey=$(cat ${config.sops.secrets.tailscale_authkey.path} 2>/dev/null || echo "")
    if [ -z "$_login_server" ] || [ -z "$_authkey" ]; then
      echo "[tailscale] secrets not decrypted yet — skipping join (will retry next hms)"
      exit 0
    fi

    echo "[tailscale] joining $_login_server as $(${pkgs.hostname}/bin/hostname)…"
    # --operator avoids needing sudo for `tailscale up/down/set` from now on.
    $SUDO /usr/bin/tailscale up \
      --login-server="$_login_server" \
      --authkey="$_authkey" \
      --hostname="$(${pkgs.hostname}/bin/hostname)" \
      --operator="$(whoami)" \
      --accept-routes \
      || echo "[tailscale] up failed (non-fatal)" >&2
  '';
}
