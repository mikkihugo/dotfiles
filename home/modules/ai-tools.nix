# home/modules/ai-tools.nix — AI coding CLI tools for laptop
#
# Installs and auto-updates AI CLI tools that aren't in nixpkgs:
#   - gemini  (@google/gemini-cli, npm)
#   - amp     (@sourcegraph/amp, npm)
#   - toad    (batrachianai/toad, Python via uv tool)
#
# API keys come from SOPS (mirroring OpenBao KV), never hardcoded.
# Wrapper scripts read keys at invocation time from the decrypted secret paths.
#
# Keys expected in secrets/api-keys.yaml (SOPS):
#   gemini/api_key    → kv/gemini:api_key on OpenBao
#   openrouter/api_key → kv/openrouter:api_key (already present for hermes)
{
  config,
  pkgs,
  lib,
  ...
}: let
  sopsSecrets = config.sops.secrets;

  mkKeyWrapper = name: bin: keyPath: envVar:
    pkgs.writeShellScriptBin name ''
      export ${envVar}="$(cat "${keyPath}" 2>/dev/null || echo "")"
      exec ${bin} "$@"
    '';

  geminiWrapper =
    mkKeyWrapper "gemini"
    "${config.home.homeDirectory}/.npm-global/bin/gemini"
    sopsSecrets.gemini_api_key.path
    "GEMINI_API_KEY";

  ampWrapper =
    mkKeyWrapper "amp"
    "${config.home.homeDirectory}/.npm-global/bin/amp"
    sopsSecrets.amp_token.path
    "AMP_TOKEN";

  toadWrapper =
    mkKeyWrapper "toad"
    "${config.home.homeDirectory}/.local/bin/toad"
    sopsSecrets.openrouter_api_key.path
    "OPENROUTER_API_KEY";
in {
  sops.secrets = {
    gemini_api_key = lib.mkDefault {
      key = "gemini/api_key";
      mode = "0600";
      sopsFile = ../../secrets/api-keys.yaml;
    };
    openrouter_api_key = lib.mkDefault {
      key = "openrouter/api_key";
      mode = "0600";
      sopsFile = ../../secrets/api-keys.yaml;
    };
    amp_token = lib.mkDefault {
      key = "amp/token";
      mode = "0600";
      sopsFile = ../../secrets/api-keys.yaml;
    };
  };

  home.packages = [geminiWrapper ampWrapper toadWrapper];

  # Install + upgrade on every hms. npm --prefer-online updates if registry
  # has a newer version; uv tool upgrade does the same for Python.
  home.activation.installAiTools = lib.hm.dag.entryAfter ["writeBoundary"] ''
    export PATH="${pkgs.nodejs}/bin:${pkgs.uv}/bin:$PATH"
    export npm_config_prefix="$HOME/.npm-global"

    $DRY_RUN_CMD npm install -g --prefer-online \
      @google/gemini-cli \
      @sourcegraph/amp \
      2>/dev/null || true

    $DRY_RUN_CMD uv tool install --upgrade \
      "git+https://github.com/batrachianai/toad" \
      2>/dev/null || true
  '';
}
