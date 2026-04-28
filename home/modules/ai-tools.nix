# home/modules/ai-tools.nix — AI coding CLI tools
#
# All major tools sourced from github:numtide/llm-agents.nix — daily-updated
# Nix packages with a prebuilt binary cache (cache.numtide.com).
#
# Tools that need API keys are wrapped with a shell script that reads the
# decrypted SOPS secret at invocation time — never hardcoded.
#
# Keys expected in secrets/api-keys.yaml (SOPS):
#   gemini/api_key     → kv/gemini:api_key on OpenBao
#   openrouter/api_key → kv/openrouter:api_key (shared with hermes)
#   amp/token          → kv/amp:token
#
# Tools not yet in llm-agents (installed via activation.nix):
#   toad, kiro, openhands, crow-cli, kimi-cli
{
  config,
  pkgs,
  lib,
  llm-agents,
  ...
}: let
  sopsSecrets = config.sops.secrets;
  llm-pkgs = llm-agents.packages.${pkgs.stdenv.hostPlatform.system};

  mkKeyWrapper = name: bin: keyPath: envVar:
    pkgs.writeShellScriptBin name ''
      export ${envVar}="$(cat "${keyPath}" 2>/dev/null || echo "")"
      exec ${bin} "$@"
    '';

  geminiWrapper =
    mkKeyWrapper "gemini"
    "${llm-pkgs.gemini-cli}/bin/gemini"
    sopsSecrets.gemini_api_key.path
    "GEMINI_API_KEY";

  # ampWrapper disabled until `amp` section exists in secrets/api-keys.yaml.
  # When ready, re-enable + add the amp_token sops.secrets block below.

  toadWrapper =
    mkKeyWrapper "toad"
    "${config.home.homeDirectory}/.local/bin/toad"
    sopsSecrets.openrouter_api_key.path
    "OPENROUTER_API_KEY";
in {
  sops.secrets = {
    gemini_api_key = {
      key = "gemini/api_key";
      mode = "0600";
      sopsFile = ../../secrets/api-keys.yaml;
    };
    openrouter_api_key = {
      key = "openrouter/api_key";
      mode = "0600";
      sopsFile = ../../secrets/api-keys.yaml;
    };
  };

  home.packages = [
    # API-key-injecting wrappers (shadow the raw Nix binaries for these tools).
    geminiWrapper
    toadWrapper
    # Raw llm-agents packages — no key injection needed.
    llm-pkgs.claude-code # binary: claude
    llm-pkgs.codex # binary: codex
    llm-pkgs.opencode # binary: opencode
    llm-pkgs.goose-cli # binary: goose
    llm-pkgs.cursor-agent # binary: cursor-agent (note: was `agent` from curl install)
    llm-pkgs.droid # binary: droid
    llm-pkgs.mistral-vibe # binary: vibe (note: was `mistral-vibe` from uv install)
    # llm-pkgs.amp disabled until amp/token added to secrets/api-keys.yaml
  ];
}
