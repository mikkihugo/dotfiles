# home/modules/hermes-tui.nix — Hermes TUI client for laptop
#
# Wraps `hermes` so it always launches in TUI mode connected to
# the central Hermes agent at api.hugo.dk/hermes via HTTPS (CF Tunnel).
# No tailscale required — works anywhere with internet access.
#
# The GATEWAY_PROXY_KEY is read from SOPS at runtime (same secret as
# hermes-proxy.nix uses, key hermes/gateway_proxy_key in api-keys.yaml).
{
  config,
  pkgs,
  lib,
  targetSystem,
  hermes-agent ? null,
  ...
}: let
  hermesUrl = "https://hdm.hugo.dk";
  hermesBin =
    if hermes-agent != null
    then "${hermes-agent.packages.${targetSystem}.default}/bin/hermes"
    else "hermes";

  keyPath = config.sops.secrets.hermes_gateway_proxy_key.path;

  htWrapper = pkgs.writeShellScriptBin "hermes" ''
    export GATEWAY_PROXY_URL="${hermesUrl}"
    export GATEWAY_PROXY_KEY="$(cat "${keyPath}")"
    export HERMES_TUI_DIR="$HOME/.hermes/ui-tui"
    unset OPENROUTER_API_KEY
    exec ${hermesBin} --tui "$@"
  '';
in {
  sops.secrets.hermes_gateway_proxy_key = {
    key = "hermes/gateway_proxy_key";
    mode = "0600";
    sopsFile = ../../secrets/api-keys.yaml;
  };

  home.packages = [htWrapper];
}
