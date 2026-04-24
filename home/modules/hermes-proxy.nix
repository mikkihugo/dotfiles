# home/modules/hermes-proxy.nix — Hermes thin gateway (proxy to the main host agent)
#
# Topology:
# - The main Hermes host agent API is exposed privately at
#   api.hermes.internal/hermes and resolves to flow's tailnet IP.
# - This module runs a thin gateway on each machine that forwards all agent
#   work to that host agent. Matches the "proxy mode" in Hermes docs.
# - Replaces the legacy openclaw-node service (openclaw.nix) once enabled.
#
# Setup flow (once per machine):
#   1. Add hermes.gateway_proxy_key to secrets/api-keys.yaml via `sops`
#      (same bearer token as API_SERVER_KEY on the main Hermes host agent)
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
      # Hermes API at api.hermes.internal/hermes. Headscale DNS resolves the
      # hostname to flow's tailnet IP for on-tailnet machines, and Traefik on
      # flow k3s strips the /hermes prefix and forwards to the hermes
      # Service:8642. Proxy nodes only need the API_SERVER_KEY bearer token.
      default = "https://api.hermes.internal/hermes";
      description = "Hermes host agent API endpoint this proxy forwards to.";
    };
  };

  config = lib.mkIf config.dotfiles.machine.enableHermesProxy {
    # Expose the `hermes` CLI on PATH so users can run `hermes --tui`,
    # `hermes chat`, etc. interactively. Falls back to nothing if the
    # flake input isn't wired (e.g. unsupported system).
    home.packages = lib.optionals (hermes-agent != null) [
      hermes-agent.packages.${targetSystem}.default
    ];

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
