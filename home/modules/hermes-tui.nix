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
  hermesUrl = "https://api.hugo.dk/hermes";
  hermesBin =
    if hermes-agent != null
    then "${hermes-agent.packages.${targetSystem}.default}/bin/hermes"
    else "hermes";

  keyPath = config.sops.secrets.hermes_gateway_proxy_key.path;

  htWrapper = pkgs.writeShellScriptBin "hermes" ''
    export GATEWAY_PROXY_URL="${hermesUrl}"
    export GATEWAY_PROXY_KEY="$(cat "${keyPath}")"
    exec ${hermesBin} --tui "$@"
  '';
in {
  # Reuse the SOPS secret declared in hermes-proxy.nix if that module is
  # active; otherwise declare it here. lib.mkDefault avoids duplicate-key
  # errors when both modules are loaded.
  sops.secrets.hermes_gateway_proxy_key = lib.mkDefault {
    key = "hermes/gateway_proxy_key";
    mode = "0600";
    sopsFile = ../../secrets/api-keys.yaml;
  };

  home.packages =
    [htWrapper]
    ++ lib.optional (hermes-agent != null)
    hermes-agent.packages.${targetSystem}.default;
}
