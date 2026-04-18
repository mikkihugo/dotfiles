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
      mode = "0600";
    };
  };

  # Persistent node host — connects to the ai.hugo.dk gateway.
  # This is not a local UI service. The browser UI lives on the gateway,
  # and the gateway can delegate work to this host node.
  # Wrapper script sources password from sops decrypted file.
  systemd.user.services.openclaw-node = {
    Unit = {
      Description = "OpenClaw Node Host";
      After = ["sops-nix.service" "network-online.target"];
      Wants = ["network-online.target"];
      Requires = ["sops-nix.service"];
    };
    Service = {
      Type = "simple";
      ExecStart = "${pkgs.bash}/bin/bash -c 'export OPENCLAW_GATEWAY_PASSWORD=$(cat ${config.sops.secrets.openclaw_gateway_password.path}) && exec ${pkgs.nodejs_24}/bin/node ${config.home.homeDirectory}/.npm-global/lib/node_modules/openclaw/dist/index.js node run --host ai.hugo.dk --port 18789 --tls --display-name %H'";
      Restart = "always"; # openclaw exits 0 on auth failure — restart regardless
      RestartSec = "30s"; # back off while awaiting pairing approval on gateway
    };
    Install.WantedBy = ["default.target"];
  };
}
