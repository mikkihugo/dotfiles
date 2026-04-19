# home/modules/tailscale.nix — tailscale CLI in user profile + SOPS secrets
#
# Actual tailnet join happens in bootstrap/steps/40-tailscale.sh because
# it needs sudo to install the daemon and run `tailscale up`. That script
# reads the authkey from sops-nix decrypted files when available (after
# the first hms) or falls back to direct `sops -d` on the repo file.
#
# Rotate: generate a new key on vpn.hugo.dk —
#   headscale preauthkeys create --user 1 --reusable --expiration 8760h
# then `sops secrets/api-keys.yaml` to update, then re-run
# `bootstrap/steps/40-tailscale.sh` on each node to rejoin.
{pkgs, ...}: {
  sops.secrets.tailscale_authkey = {
    key = "tailscale/authkey";
    mode = "0400";
  };
  sops.secrets.tailscale_login_server = {
    key = "tailscale/login_server";
    mode = "0400";
  };

  home.packages = [pkgs.tailscale];
}
