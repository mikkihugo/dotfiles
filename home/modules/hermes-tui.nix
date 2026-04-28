# home/modules/hermes-tui.nix — Hermes TUI client for laptop
#
# Wraps `hermes` so it always launches in TUI mode connected to
# the local hermes-proxy gateway (localhost:8642), which forwards to the
# central agent. Keeps a single upstream path instead of two.
{
  config,
  pkgs,
  lib,
  targetSystem,
  hermes-agent ? null,
  ...
}: let
  hermesUrl = "http://localhost:8642";
  hermesBin =
    if hermes-agent != null
    then "${hermes-agent.packages.${targetSystem}.default}/bin/hermes"
    else "hermes";

  keyPath = config.sops.secrets.hermes_gateway_proxy_key.path;

  htWrapper = pkgs.writeShellScriptBin "hermes-tui" ''
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
