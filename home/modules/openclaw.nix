# home/modules/openclaw.nix — openclaw node host service
#
# openclaw runs as a persistent systemd user service that connects this
# machine as a compute node to the ai.hugo.dk gateway.
#
# Setup flow (once per machine):
#   1. Add openclaw.gateway_password to secrets/api-keys.yaml via `sops`
#   2. Run `hms` — installs openclaw, renders EnvironmentFile, starts service
#   3. Run `openclaw-setup` alias to register this node on the gateway
#      (or approve the join request on ai.hugo.dk)
{
  config,
  pkgs,
  lib,
  ...
}: {
  # Render OPENCLAW_GATEWAY_PASSWORD from SOPS into a private EnvironmentFile
  # so the plaintext never touches git or the Nix store.
  # entryBefore reloadSystemd so the env file exists when systemd starts the service.
  home.activation.renderOpenclawEnv = lib.hm.dag.entryBefore ["reloadSystemd"] ''
    mkdir -p "${config.home.homeDirectory}/.config/openclaw"
    _oc_pw=$(${pkgs.sops}/bin/sops --decrypt \
      --extract '["openclaw"]["gateway_password"]' \
      "${config.home.homeDirectory}/.dotfiles/secrets/api-keys.yaml" 2>/dev/null || true)
    if [ -n "$_oc_pw" ]; then
      printf 'OPENCLAW_GATEWAY_PASSWORD=%s\n' "$_oc_pw" \
        > "${config.home.homeDirectory}/.config/openclaw/env"
      chmod 600 "${config.home.homeDirectory}/.config/openclaw/env"
    else
      echo "WARNING: openclaw: could not decrypt gateway_password from SOPS (service will start without credentials)" >&2
    fi
    unset _oc_pw
  '';

  # Persistent node host — connects to the ai.hugo.dk gateway and serves
  # local model requests. EnvironmentFile injects the gateway password at
  # runtime; the `-` prefix makes it optional so hms succeeds even before
  # the SOPS key is added.
  systemd.user.services.openclaw-node = {
    Unit = {
      Description = "OpenClaw Node Host";
      After = ["network-online.target"];
      Wants = ["network-online.target"];
    };
    Service = {
      ExecStart = "${pkgs.nodejs_24}/bin/node ${config.home.homeDirectory}/.npm-global/lib/node_modules/openclaw/dist/index.js node run --host ai.hugo.dk --port 443 --tls --display-name Laptop";
      EnvironmentFile = "-${config.home.homeDirectory}/.config/openclaw/env";
      Restart = "always"; # openclaw exits 0 on auth failure — restart regardless
      RestartSec = "30s"; # back off while awaiting pairing approval on gateway
    };
    Install.WantedBy = ["default.target"];
  };
}
