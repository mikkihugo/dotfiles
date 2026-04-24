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
}: let
  desiredHostname =
    if config.dotfiles.machine.tailnetHostname != null && config.dotfiles.machine.tailnetHostname != ""
    then config.dotfiles.machine.tailnetHostname
    else "$(${pkgs.hostname}/bin/hostname)";
in
lib.mkIf config.dotfiles.machine.enableTailscale {
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

    _desired_hostname='${desiredHostname}'
    _status_json=$($SUDO /usr/bin/tailscale status --json 2>/dev/null || true)
    _state=$(printf '%s' "$_status_json" | ${pkgs.jq}/bin/jq -r '.BackendState // ""' 2>/dev/null || echo "")
    _current_hostname=$(printf '%s' "$_status_json" | ${pkgs.jq}/bin/jq -r '.Self.HostName // .Self.DNSName // ""' 2>/dev/null || echo "")

    _login_server=$(cat ${config.sops.secrets.tailscale_login_server.path} 2>/dev/null || echo "")
    _authkey=$(cat ${config.sops.secrets.tailscale_authkey.path} 2>/dev/null || echo "")
    if [ -z "$_login_server" ] || [ -z "$_authkey" ]; then
      echo "[tailscale] secrets not decrypted yet — skipping join (will retry next hms)"
      exit 0
    fi

    if [ "$_state" = "Running" ] && [ "$_current_hostname" = "$_desired_hostname" ]; then
      echo "[tailscale] already online as $_current_hostname — $($SUDO /usr/bin/tailscale status --self=true --peers=false 2>/dev/null | head -1)"
      exit 0
    fi

    if [ "$_state" = "Running" ] && [ -n "$_current_hostname" ] && [ "$_current_hostname" != "$_desired_hostname" ]; then
      echo "[tailscale] correcting hostname $_current_hostname -> $_desired_hostname"
    else
      echo "[tailscale] joining $_login_server as $_desired_hostname…"
    fi

    # --operator avoids needing sudo for `tailscale up/down/set` from now on.
    $SUDO /usr/bin/tailscale up \
      --login-server="$_login_server" \
      --authkey="$_authkey" \
      --hostname="$_desired_hostname" \
      --operator="$(whoami)" \
      --accept-routes \
      || echo "[tailscale] up failed (non-fatal)" >&2
  '';
}
