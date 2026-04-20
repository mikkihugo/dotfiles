# home/modules/hermes-proxy.nix — Hermes thin gateway (proxy to ai.hugo.dk)
#
# Topology:
# - ai.hugo.dk runs the Hermes host agent (API server) on port 8642.
# - This module runs a thin gateway on each machine that forwards all agent
#   work to that host agent. Matches the "proxy mode" in Hermes docs.
# - Replaces the legacy openclaw-node service (openclaw.nix) once enabled.
#
# Setup flow (once per machine):
#   1. Add hermes.gateway_proxy_key to secrets/api-keys.yaml via `sops`
#      (same bearer token as API_SERVER_KEY on the ai.hugo.dk host agent)
#   2. Flip dotfiles.machine.enableHermesProxy = true via machine-role.json
#   3. Run `hms` — installs hermes via nix flake, starts service
{
  config,
  pkgs,
  lib,
  targetSystem,
  hermes-agent ? null,
  ...
}: let
  cfg = config.dotfiles.services.hermesProxy;
in {
  options.dotfiles.services.hermesProxy = {
    upstreamUrl = lib.mkOption {
      type = lib.types.str;
      # Hermes API at api.hugo.dk/hermes, fronted by Cloudflare Tunnel +
      # CF Access (service-token policy). Traefik on flow k3s strips the
      # /hermes prefix and forwards to the hermes Service:8642.
      # Proxy nodes must present CF-Access-Client-Id + CF-Access-Client-Secret
      # headers on every request to pass CF Access, plus the API_SERVER_KEY
      # bearer token for the Hermes API itself.
      default = "https://api.hugo.dk/hermes";
      description = "Hermes host agent API endpoint this proxy forwards to.";
    };
  };

  config = lib.mkIf config.dotfiles.machine.enableHermesProxy {
    sops = {
      defaultSopsFile = ../../secrets/api-keys.yaml;
      age.keyFile = "${config.home.homeDirectory}/.config/sops/age/keys.txt";
      secrets.hermes_gateway_proxy_key = {
        key = "hermes/gateway_proxy_key";
        mode = "0600";
      };
    };

    systemd.user.services.hermes-proxy = {
      Unit = {
        Description = "Hermes proxy gateway (forwards to ${cfg.upstreamUrl})";
        After = ["sops-nix.service" "network-online.target"];
        Wants = ["network-online.target"];
        Requires = ["sops-nix.service"];
      };
      Service = let
        hermesBin =
          if hermes-agent != null
          then "${hermes-agent.packages.${targetSystem}.default}/bin/hermes"
          else "${config.home.homeDirectory}/.nix-profile/bin/hermes";
      in {
        Type = "simple";
        Environment = [
          "GATEWAY_PROXY_URL=${cfg.upstreamUrl}"
          "HOME=${config.home.homeDirectory}"
        ];
        ExecStart = "${pkgs.bash}/bin/bash -c 'export GATEWAY_PROXY_KEY=$(cat ${config.sops.secrets.hermes_gateway_proxy_key.path}) && exec ${hermesBin} gateway run'";
        Restart = "always";
        RestartSec = "30s";
      };
      Install.WantedBy = ["default.target"];
    };
  };
}
