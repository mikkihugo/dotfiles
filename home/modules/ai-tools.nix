# home/modules/ai-tools.nix — AI coding CLI tools
#
# Major AI CLIs are installed globally by mise where mise has a registry or
# backend entry. Home Manager keeps only wrappers that inject SOPS secrets and
# Nix-only tools that mise cannot currently manage.
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
#   kimi-cli
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
    "${config.home.homeDirectory}/.local/share/mise/shims/gemini"
    sopsSecrets.gemini_api_key.path
    "GEMINI_API_KEY";

  # ampWrapper disabled until `amp` section exists in secrets/api-keys.yaml.
  # When ready, re-enable + add the amp_token sops.secrets block below.

  # vtcode — cargo-vtcode installed via mise. Custom wrapper because:
  # 1. vtcode is not in PATH (only mise shim at ~/.local/share/mise/shims/vtcode)
  # 2. opencode-go is OpenAI-compat; vtcode reads key via --api-key-env, not OPENAI_API_KEY
  vtcodeWrapper = pkgs.writeShellScriptBin "vtcode" ''
    export OLLAMA_API_KEY="$(cat "${sopsSecrets.ollama_api_key.path}" 2>/dev/null || echo "")"
    exec ${config.home.homeDirectory}/.local/share/mise/shims/vtcode \
      --provider ollama-cloud --model glm-5.1 --api-key-env OLLAMA_API_KEY \
      "$@"
  '';

  # vtcode-cloud — same binary, defaults to Ollama Cloud instead of opencode-go
  vtcodeCloudWrapper = pkgs.writeShellScriptBin "vtcode-cloud" ''
    export OLLAMA_API_KEY="$(cat "${sopsSecrets.ollama_api_key.path}" 2>/dev/null || echo "")"
    exec ${config.home.homeDirectory}/.local/share/mise/shims/vtcode \
      --provider ollama-cloud --api-key-env OLLAMA_API_KEY \
      "$@"
  '';

  # vtcode-devstral — Ollama Cloud devstral-2:123b for hard tasks
  vtcodeDevstralWrapper = pkgs.writeShellScriptBin "vtcode-devstral" ''
    export OLLAMA_API_KEY="$(cat "${sopsSecrets.ollama_api_key.path}" 2>/dev/null || echo "")"
    exec ${config.home.homeDirectory}/.local/share/mise/shims/vtcode \
      --provider ollama-cloud --model devstral-2:123b --api-key-env OLLAMA_API_KEY \
      "$@"
  '';

  # vtcode-mistral — Ollama Cloud mistral-large-3:675b for speed
  vtcodeMistralWrapper = pkgs.writeShellScriptBin "vtcode-mistral" ''
    export OLLAMA_API_KEY="$(cat "${sopsSecrets.ollama_api_key.path}" 2>/dev/null || echo "")"
    exec ${config.home.homeDirectory}/.local/share/mise/shims/vtcode \
      --provider ollama-cloud --model mistral-large-3:675b --api-key-env OLLAMA_API_KEY \
      "$@"
  '';

  # vtcode-kimi — Ollama Cloud kimi-k2.6
  vtcodeKimiWrapper = pkgs.writeShellScriptBin "vtcode-kimi" ''
    export OLLAMA_API_KEY="$(cat "${sopsSecrets.ollama_api_key.path}" 2>/dev/null || echo "")"
    exec ${config.home.homeDirectory}/.local/share/mise/shims/vtcode \
      --provider ollama-cloud --model kimi-k2.6 --api-key-env OLLAMA_API_KEY \
      "$@"
  '';

  # vtcode-opencode — opencode-go glm-5.1
  vtcodeOpencodeWrapper = pkgs.writeShellScriptBin "vtcode-opencode" ''
    export OPENCODE_GO_API_KEY="$(cat "${sopsSecrets.opencode_go_api_key.path}" 2>/dev/null || echo "")"
    exec ${config.home.homeDirectory}/.local/share/mise/shims/vtcode \
      --provider opencode-go --model glm-5.1 --api-key-env OPENCODE_GO_API_KEY \
      "$@"
  '';

  # copilot-kimi — GitHub Copilot CLI routed to the Kimi Code platform via BYOK.
  # Kimi /coding/v1 allowlists User-Agent (KimiCLI/*, Claude Code, etc.) and
  # rejects Copilot's default UA with 403, so we override it via
  # COPILOT_AGENT_REQUEST_HEADERS.
  # copilot-kimi — GitHub Copilot CLI routed to Kimi K2.7 (umans-kimi-k2.7)
  # through the centralcloud-ai-proxy gateway at llm-gateway.centralcloud.com
  # via BYOK. Kimi K2.7 has a 262K token context window and 32K max output.
  copilotKimiWrapper = pkgs.writeShellScriptBin "copilot-kimi" ''
    copilot_bin="$HOME/.local/share/mise/shims/copilot"
    gateway_url="https://llm-gateway.centralcloud.com"
    edge_token="$(cat "${sopsSecrets.umans_api_key.path}" 2>/dev/null || echo "")"
    if [ ! -x "$copilot_bin" ]; then
      echo "copilot-kimi: expected mise GitHub Copilot CLI at $copilot_bin" >&2
      exit 127
    fi
    if [ -z "$edge_token" ]; then
      echo "copilot-kimi: failed to read umans_api_key SOPS secret" >&2
      exit 1
    fi
    if ! curl -sS --max-time 2 -H "authorization: Bearer $edge_token" \
        "$gateway_url/v1/models" >/dev/null 2>&1; then
      echo "copilot-kimi: gateway at $gateway_url not reachable" >&2
      exit 1
    fi
    export RUST_LOG=warn
    export COPILOT_PROVIDER_TYPE=openai
    export COPILOT_PROVIDER_BASE_URL="$gateway_url/v1"
    export COPILOT_PROVIDER_API_KEY="$edge_token"
    export COPILOT_MODEL=auto-kimi
    export COPILOT_PROVIDER_MAX_PROMPT_TOKENS=262144
    export COPILOT_PROVIDER_MAX_OUTPUT_TOKENS=32768

    node "$HOME/.copilot/byok-models-patch.cjs" 2>/dev/null || true

    copilot_app="$HOME/.local/share/mise/installs/npm-github-copilot/latest/lib/node_modules/@github/copilot/node_modules/@github/copilot-linux-x64/app.js"
    if [ -f "$copilot_app" ]; then
      exec node "$copilot_app" "$@"
    fi
    exec "$copilot_bin" "$@"
  '';

  # copilot-glm — GitHub Copilot CLI routed to GLM-5.2 (umans-glm-5.2) through
  # the centralcloud-ai-proxy gateway at llm-gateway.centralcloud.com via BYOK.
  # GLM-5.2 has a 405K token context window and 131K max output tokens.
  # Top open-weight coding model: 62.1% SWE-bench Pro, 81.0% Terminal-Bench 2.1.
  copilotGlmWrapper = pkgs.writeShellScriptBin "copilot-glm" ''
    copilot_bin="$HOME/.local/share/mise/shims/copilot"
    gateway_url="https://llm-gateway.centralcloud.com"
    edge_token="$(cat "${sopsSecrets.umans_api_key.path}" 2>/dev/null || echo "")"
    if [ ! -x "$copilot_bin" ]; then
      echo "copilot-glm: expected mise GitHub Copilot CLI at $copilot_bin" >&2
      exit 127
    fi
    if [ -z "$edge_token" ]; then
      echo "copilot-glm: failed to read umans_api_key SOPS secret" >&2
      exit 1
    fi
    if ! curl -sS --max-time 2 -H "authorization: Bearer $edge_token" \
        "$gateway_url/v1/models" >/dev/null 2>&1; then
      echo "copilot-glm: gateway at $gateway_url not reachable" >&2
      exit 1
    fi
    export RUST_LOG=warn
    export COPILOT_PROVIDER_TYPE=openai
    export COPILOT_PROVIDER_BASE_URL="$gateway_url/v1"
    export COPILOT_PROVIDER_API_KEY="$edge_token"
    export COPILOT_MODEL=auto-glm
    export COPILOT_PROVIDER_MAX_PROMPT_TOKENS=400000
    export COPILOT_PROVIDER_MAX_OUTPUT_TOKENS=131072

    node "$HOME/.copilot/byok-models-patch.cjs" 2>/dev/null || true

    copilot_app="$HOME/.local/share/mise/installs/npm-github-copilot/latest/lib/node_modules/@github/copilot/node_modules/@github/copilot-linux-x64/app.js"
    if [ -f "$copilot_app" ]; then
      exec node "$copilot_app" "$@"
    fi
    exec "$copilot_bin" "$@"
  '';

  # copilot-minimax — GitHub Copilot CLI routed to MiniMax-M3 on minimax.io
  # via BYOK (direct, not through the gateway).
  # MiniMax-M3 has a 1M token context window and 131K max output tokens.
  copilotMinimaxWrapper = pkgs.writeShellScriptBin "copilot-minimax" ''
    copilot_bin="$HOME/.local/share/mise/shims/copilot"
    if [ ! -x "$copilot_bin" ]; then
      echo "copilot-minimax: expected mise GitHub Copilot CLI at $copilot_bin" >&2
      exit 127
    fi
    export COPILOT_PROVIDER_TYPE=openai
    export COPILOT_PROVIDER_BASE_URL=https://api.minimax.io/v1
    export COPILOT_PROVIDER_API_KEY="$(cat "${sopsSecrets.minimax_api_key.path}" 2>/dev/null || echo "")"
    export COPILOT_PROVIDER_MAX_PROMPT_TOKENS=1048576
    export COPILOT_PROVIDER_MAX_OUTPUT_TOKENS=131072
    export COPILOT_MODEL=MiniMax-M3
    exec "$copilot_bin" "$@"
  '';

  # copilot-all — GitHub Copilot CLI routed through the centralcloud-ai-proxy
  # at llm-gateway.centralcloud.com (the external DNS name for the
  # inference-fabric-edge service). No port-forward needed.
  copilotAllWrapper = pkgs.writeShellScriptBin "copilot-all" ''
    copilot_bin="$HOME/.local/share/mise/shims/copilot"
    gateway_url="https://llm-gateway.centralcloud.com"
    edge_token="$(cat "${sopsSecrets.umans_api_key.path}" 2>/dev/null || echo "")"
    if [ ! -x "$copilot_bin" ]; then
      echo "copilot-all: expected mise GitHub Copilot CLI at $copilot_bin" >&2
      exit 127
    fi
    if [ -z "$edge_token" ]; then
      echo "copilot-all: failed to read umans_api_key SOPS secret" >&2
      exit 1
    fi
    if ! curl -sS --max-time 2 -H "authorization: Bearer $edge_token" \
        "$gateway_url/v1/models" >/dev/null 2>&1; then
      echo "copilot-all: gateway at $gateway_url not reachable" >&2
      exit 1
    fi

    # Keep @github/copilot on the newest npm release. The copilot CLI's own
    # self-updater does not work when we disable the native binary in favour
    # of the patched JS bundle, and mise's `latest` pin is only refreshed on
    # `mise upgrade`. Throttle to once per hour so every invocation is not a
    # round-trip to the npm registry.
    upgrade_stamp="$HOME/.cache/copilot-all-last-upgrade"
    mkdir -p "$(dirname "$upgrade_stamp")"
    if [ ! -f "$upgrade_stamp" ] || [ "$(find "$upgrade_stamp" -mmin +60 2>/dev/null)" ]; then
      if mise upgrade --yes "npm:@github/copilot" >/dev/null 2>&1; then
        touch "$upgrade_stamp"
      else
        # Upgrade failure is non-fatal; the installed version may still work.
        touch "$upgrade_stamp"
        echo "copilot-all: mise upgrade failed (will retry in 1 hour)" >&2
      fi
    fi

    export RUST_LOG=warn
    export COPILOT_PROVIDER_TYPE=openai
    export COPILOT_PROVIDER_BASE_URL="$gateway_url/v1"
    export COPILOT_PROVIDER_API_KEY="$edge_token"
    export COPILOT_MODEL=auto
    export COPILOT_PROVIDER_MAX_PROMPT_TOKENS=405504
    export COPILOT_PROVIDER_MAX_OUTPUT_TOKENS=131072

    # Patch the Copilot JS bundle so BYOK mode shows every model from the
    # provider's /v1/models endpoint instead of only COPILOT_MODEL. The npm
    # package layout changed in 1.0.64: app.js lives in the optional platform
    # package, and the `copilot` shim tries the native binary first, so we run
    # the patched node bundle directly.
    node "$HOME/.copilot/byok-models-patch.cjs" 2>/dev/null || true

    copilot_app="$HOME/.local/share/mise/installs/npm-github-copilot/latest/lib/node_modules/@github/copilot/node_modules/@github/copilot-linux-x64/app.js"
    if [ -f "$copilot_app" ]; then
      exec node "$copilot_app" "$@"
    fi
    # Fallback for pre-1.0.64 layout where app.js was in the root package.
    fallback_app="$HOME/.local/share/mise/installs/npm-github-copilot/latest/lib/node_modules/@github/copilot/app.js"
    if [ -f "$fallback_app" ]; then
      exec node "$fallback_app" "$@"
    fi
    exec "$copilot_bin" "$@"
  '';
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
    opencode_api_key = {
      key = "opencode/api_key";
      mode = "0600";
      sopsFile = ../../secrets/api-keys.yaml;
    };
    opencode_go_api_key = {
      key = "sf/env/OPENCODE_GO_API_KEY";
      mode = "0600";
      sopsFile = ../../secrets/api-keys.yaml;
    };
    ollama_api_key = {
      key = "sf/env/OLLAMA_API_KEY";
      mode = "0600";
      sopsFile = ../../secrets/api-keys.yaml;
    };
    kimi_api_key = {
      key = "sf/env/KIMI_API_KEY";
      mode = "0600";
      sopsFile = ../../secrets/api-keys.yaml;
    };
    minimax_api_key = {
      key = "sf/env/MINIMAX_API_KEY";
      mode = "0600";
      sopsFile = ../../secrets/api-keys.yaml;
    };
    zai_api_key = {
      key = "sf/env/ZAI_API_KEY";
      mode = "0600";
      sopsFile = ../../secrets/api-keys.yaml;
    };
    llm_gateway_api_key = {
      key = "llm_gateway/api_key";
      mode = "0600";
      sopsFile = ../../secrets/api-keys.yaml;
    };
    umans_api_key = {
      key = "umans/api_key";
      mode = "0600";
      sopsFile = ../../secrets/api-keys.yaml;
    };
  };

  home.packages = [
    # API-key-injecting wrappers (shadow the raw Nix binaries for these tools).
    geminiWrapper
    vtcodeWrapper
    vtcodeCloudWrapper
    vtcodeDevstralWrapper
    vtcodeMistralWrapper
    vtcodeKimiWrapper
    vtcodeOpencodeWrapper
    # Raw llm-agents packages — no key injection needed.
    # NOTE: numtide's prebuilt cache is x86_64-only. On aarch64 (laptop)
    # these packages compile from source — disable per-host as needed.
    # claude-code is managed globally by mise.
    # llm-pkgs.codex # disabled — Rust rebuild on aarch64
    # opencode is managed globally by mise.
    # llm-pkgs.goose-cli # disabled — Rust rebuild on aarch64
    llm-pkgs.cursor-agent # binary: cursor-agent
    # droid is managed globally by mise.
    copilotKimiWrapper # binary: copilot-kimi -> routes mise GitHub Copilot CLI to Kimi K2.7 (umans-kimi-k2.7) via llm-gateway
    copilotGlmWrapper  # binary: copilot-glm -> routes mise GitHub Copilot CLI to GLM-5.2 (umans-glm-5.2) via llm-gateway
    copilotMinimaxWrapper  # binary: copilot-minimax -> routes mise GitHub Copilot CLI to MiniMax-M3 on minimax.io
    copilotAllWrapper     # binary: copilot-all -> routes mise GitHub Copilot CLI through local centralcloud-ai-proxy (GLM-5.2 + Kimi K2.7 + umans-flash via umans.ai, MiniMax-M3 via minimax.io)
    llm-pkgs.mistral-vibe # binary: vibe
    # llm-pkgs.amp disabled until amp/token added to secrets/api-keys.yaml
  ];
}
