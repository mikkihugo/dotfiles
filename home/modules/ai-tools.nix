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
  copilotKimiWrapper = pkgs.writeShellScriptBin "copilot-kimi" ''
    copilot_bin="$HOME/.local/share/mise/shims/copilot"
    if [ ! -x "$copilot_bin" ]; then
      echo "copilot-kimi: expected mise GitHub Copilot CLI at $copilot_bin" >&2
      exit 127
    fi
    export COPILOT_PROVIDER_TYPE=openai
    export COPILOT_PROVIDER_BASE_URL=https://api.kimi.com/coding/v1
    export COPILOT_PROVIDER_API_KEY="$(cat "${sopsSecrets.kimi_api_key.path}" 2>/dev/null || echo "")"
    export COPILOT_PROVIDER_MAX_PROMPT_TOKENS=262144
    export COPILOT_PROVIDER_MAX_OUTPUT_TOKENS=32768
    export COPILOT_MODEL=kimi-for-coding
    export COPILOT_AGENT_REQUEST_HEADERS='{"User-Agent":"KimiCLI/1.43.0"}'
    exec "$copilot_bin" "$@"
  '';

  # copilot-glm — GitHub Copilot CLI routed to GLM-5.2 on Ollama Cloud via BYOK.
  # GLM-5.2 has a 1M token context window and 131K max output tokens.
  # Supports tools and thinking capabilities.
  copilotGlmWrapper = pkgs.writeShellScriptBin "copilot-glm" ''
    copilot_bin="$HOME/.local/share/mise/shims/copilot"
    if [ ! -x "$copilot_bin" ]; then
      echo "copilot-glm: expected mise GitHub Copilot CLI at $copilot_bin" >&2
      exit 127
    fi
    export COPILOT_PROVIDER_TYPE=openai
    export COPILOT_PROVIDER_BASE_URL=https://ollama.com/v1/
    export COPILOT_PROVIDER_API_KEY="$(cat "${sopsSecrets.ollama_api_key.path}" 2>/dev/null || echo "")"
    export COPILOT_PROVIDER_MAX_PROMPT_TOKENS=1000000
    export COPILOT_PROVIDER_MAX_OUTPUT_TOKENS=131072
    export COPILOT_MODEL=glm-5.2:cloud
    exec "$copilot_bin" "$@"
  '';

  # copilot-minimax — GitHub Copilot CLI routed to MiniMax-M3 on minimax.io via BYOK.
  # MiniMax-M3 has a 1M token context window (512K guaranteed minimum) and
  # 512K max output tokens. Supports tools, thinking, and vision.
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

  # copilot-all — GitHub Copilot CLI via local centralcloud-ai-proxy that
  # routes to all models through umans.ai (GLM-5.2, Kimi K2.7, umans-flash)
  # and minimax.io (MiniMax-M3). Main model is umans-glm (GLM-5.2, strongest
  # for coding). Use Copilot subagent model overrides to assign different models
  # per subagent type (e.g. explore→umans-flash, code-review→umans-kimi).
  copilotAllWrapper = pkgs.writeShellScriptBin "copilot-all" ''
    copilot_bin="$HOME/.local/share/mise/shims/copilot"
    proxy_bin="$HOME/code/inference-fabric/target/debug/centralcloud-ai-proxy"
    if [ ! -x "$copilot_bin" ]; then
      echo "copilot-all: expected mise GitHub Copilot CLI at $copilot_bin" >&2
      exit 127
    fi
    if [ ! -x "$proxy_bin" ]; then
      echo "copilot-all: expected centralcloud-ai-proxy at $proxy_bin" >&2
      echo "  Build with: cd ~/code/inference-fabric && nix develop -c cargo build -p centralcloud-ai-proxy" >&2
      exit 127
    fi

    # Read API keys from SOPS
    UMANS_API_KEY="$(cat "${sopsSecrets.umans_api_key.path}" 2>/dev/null || echo "")"
    MINIMAX_API_KEY="$(cat "${sopsSecrets.minimax_api_key.path}" 2>/dev/null || echo "")"
    GATEWAY_API_KEY="$(cat "${sopsSecrets.llm_gateway_api_key.path}" 2>/dev/null || echo "")"

    # Start centralcloud-ai-proxy if not already running on :8088
    if ! curl -s http://127.0.0.1:8088/healthz 2>/dev/null | grep -q '"ok"'; then
      echo "copilot-all: starting centralcloud-ai-proxy on :8088…" >&2
      "$proxy_bin" \
        --listen-host 127.0.0.1 --port 8088 \
        --upstream https://llm-gateway.centralcloud.com \
        --upstream-token "$GATEWAY_API_KEY" \
        --edge-token "copilot-edge" \
        --external-model "umans-glm-5.2@https://api.code.umans.ai/v1,$UMANS_API_KEY" \
        --external-model "umans-kimi-k2.7@https://api.code.umans.ai/v1,$UMANS_API_KEY" \
        --external-model "umans-qwen3.6-35b-a3b@https://api.code.umans.ai/v1,$UMANS_API_KEY" \
        --external-model "minimax-m3@https://api.minimax.io/v1,$MINIMAX_API_KEY,model=MiniMax-M3" \
        > "$HOME/.cache/centralcloud-ai-proxy.log" 2>&1 &
      for i in $(seq 1 10); do
        if curl -s http://127.0.0.1:8088/healthz 2>/dev/null | grep -q '"ok"'; then
          echo "copilot-all: centralcloud-ai-proxy ready" >&2
          break
        fi
        sleep 1
      done
      if ! curl -s http://127.0.0.1:8088/healthz 2>/dev/null | grep -q '"ok"'; then
        echo "copilot-all: centralcloud-ai-proxy failed to start, see ~/.cache/centralcloud-ai-proxy.log" >&2
        exit 1
      fi
    fi

    export COPILOT_PROVIDER_TYPE=openai
    export COPILOT_PROVIDER_BASE_URL=http://127.0.0.1:8088/v1
    export COPILOT_PROVIDER_API_KEY=copilot-edge
    export COPILOT_MODEL=umans-glm
    export COPILOT_PROVIDER_MAX_PROMPT_TOKENS=1000000
    export COPILOT_PROVIDER_MAX_OUTPUT_TOKENS=131072
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
    copilotKimiWrapper # binary: copilot-kimi -> routes mise GitHub Copilot CLI to Kimi K2.6
    copilotGlmWrapper  # binary: copilot-glm -> routes mise GitHub Copilot CLI to GLM-5.2 on Ollama Cloud
    copilotMinimaxWrapper  # binary: copilot-minimax -> routes mise GitHub Copilot CLI to MiniMax-M3 on minimax.io
    copilotAllWrapper     # binary: copilot-all -> routes mise GitHub Copilot CLI through local centralcloud-ai-proxy (GLM-5.2 + Kimi K2.7 + umans-flash via umans.ai, MiniMax-M3 via minimax.io)
    llm-pkgs.mistral-vibe # binary: vibe
    # llm-pkgs.amp disabled until amp/token added to secrets/api-keys.yaml
  ];
}
