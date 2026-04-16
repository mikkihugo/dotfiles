# home/modules/openclaw.nix — openclaw node host service
#
# Topology:
# - ai.hugo.dk is the central OpenClaw gateway and web UI.
# - Each machine runs only a node host that connects outward to that gateway.
# - wf.portal.centralcloud.com is expected to be a separate remote datanode,
#   not the gateway/UI host.
#
# Setup flow (once per machine):
#   1. Add openclaw.gateway_password to secrets/api-keys.yaml via `sops`
#   2. Run `hms` — installs openclaw, renders EnvironmentFile, starts service
#   3. Run `openclaw-setup` alias to register this node on the gateway
#      (or approve the join request on ai.hugo.dk)
{
  config,
  pkgs,
  ...
}: {
  sops = {
    defaultSopsFile = ../../secrets/api-keys.yaml;
    age.keyFile = "${config.home.homeDirectory}/.config/sops/age/keys.txt";
    secrets.openclaw_gateway_password = {
      key = "openclaw/gateway_password";
    };
    templates."openclaw/env".content = ''
      OPENCLAW_GATEWAY_PASSWORD=${config.sops.placeholder.openclaw_gateway_password}
    '';
  };

  # Persistent node host — connects to the ai.hugo.dk gateway.
  # This is not a local UI service. The browser UI lives on the gateway,
  # and the gateway can delegate work to this host node.
  # EnvironmentFile injects the gateway password at runtime; the `-` prefix
  # makes it optional so hms succeeds even before the SOPS key is added.
  systemd.user.services.openclaw-node = {
    Unit = {
      Description = "OpenClaw Node Host";
      After = ["network-online.target"];
      Wants = ["network-online.target"];
    };
    Service = {
      ExecStart = "${pkgs.nodejs_24}/bin/node ${config.home.homeDirectory}/.npm-global/lib/node_modules/openclaw/dist/index.js node run --host ai.hugo.dk --port 443 --tls --display-name %H";
      EnvironmentFile = config.sops.templates."openclaw/env".path;
      Restart = "always"; # openclaw exits 0 on auth failure — restart regardless
      RestartSec = "30s"; # back off while awaiting pairing approval on gateway
    };
    Install.WantedBy = ["default.target"];
  };
}
