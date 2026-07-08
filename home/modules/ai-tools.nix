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
#   openrouter/api_key → kv/openrouter:api_key (shared with hermes)
#   amp/token          → kv/amp:token
#
# Tools managed by mise (see config/mise/config.toml) rely on the SOPS secret
# loader in shell/bash/bashrc for API keys. Wrappers below are only for tools
# that need key injection where the SOPS loader is not available.
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

  # llm-gateway is reachable two ways: the in-cluster Service
  # (http://llm-gateway.svc, ~0.1-0.3s, only resolves on Cilium-meshed hosts)
  # and the public edge (https://llm-gateway.centralcloud.com, DNS-round-robins
  # 3 IPs and has seen cold-request latency up to ~5s). Try internal first —
  # fast fail via DNS if unreachable — then fall back to public with a longer
  # budget so the check doesn't flake on a slow-but-fine cold request. Assumes
  # `edge_token` is already set (and checked non-empty) by the caller.
  gatewayUrlResolver = binName: ''
    gateway_url="http://llm-gateway.svc"
    if ! curl -sS --max-time 1 -H "authorization: Bearer $edge_token" \
        "$gateway_url/v1/models" >/dev/null 2>&1; then
      gateway_url="https://llm-gateway.centralcloud.com"
      if ! curl -sS --max-time 6 -H "authorization: Bearer $edge_token" \
          "$gateway_url/v1/models" >/dev/null 2>&1; then
        echo "${binName}: gateway not reachable (tried llm-gateway.svc and llm-gateway.centralcloud.com)" >&2
        exit 1
      fi
    fi
  '';

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

  # vtcode-minimax — vtcode routed to MiniMax-M3 through the
  # centralcloud-ai-proxy gateway via BYOK. vtcode has no first-class
  # "custom OpenAI-compatible endpoint" provider name; `openai` + a
  # base-url override is the documented escape hatch (matches the
  # `[providers.openai]` block vtcode.toml already scaffolds).
  vtcodeMinimaxGatewayWrapper = pkgs.writeShellScriptBin "vtcode-minimax" ''
    edge_token="$(cat "${sopsSecrets.llm_gateway_api_key.path}" 2>/dev/null || echo "")"
    if [ -z "$edge_token" ]; then
      echo "vtcode-minimax: failed to read llm_gateway_api_key SOPS secret" >&2
      exit 1
    fi
    ${gatewayUrlResolver "vtcode-minimax"}
    export OPENAI_API_KEY="$edge_token"
    export OPENAI_BASE_URL="$gateway_url/v1"
    exec ${config.home.homeDirectory}/.local/share/mise/shims/vtcode \
      --provider openai --model minimax-m3 --api-key-env OPENAI_API_KEY \
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
    edge_token="$(cat "${sopsSecrets.llm_gateway_api_key.path}" 2>/dev/null || echo "")"
    if [ ! -x "$copilot_bin" ]; then
      echo "copilot-kimi: expected mise GitHub Copilot CLI at $copilot_bin" >&2
      exit 127
    fi
    if [ -z "$edge_token" ]; then
      echo "copilot-kimi: failed to read llm_gateway_api_key SOPS secret" >&2
      exit 1
    fi
    ${gatewayUrlResolver "copilot-kimi"}
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
    edge_token="$(cat "${sopsSecrets.llm_gateway_api_key.path}" 2>/dev/null || echo "")"
    if [ ! -x "$copilot_bin" ]; then
      echo "copilot-glm: expected mise GitHub Copilot CLI at $copilot_bin" >&2
      exit 127
    fi
    if [ -z "$edge_token" ]; then
      echo "copilot-glm: failed to read llm_gateway_api_key SOPS secret" >&2
      exit 1
    fi
    ${gatewayUrlResolver "copilot-glm"}
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

  # copilot-minimax — GitHub Copilot CLI routed to MiniMax-M3
  # (auto-minimax/MiniMax-M3) through the centralcloud-ai-proxy gateway at
  # llm-gateway.centralcloud.com via BYOK. MiniMax-M3 has a 512K token context
  # window and 131K max output tokens.
  copilotMinimaxWrapper = pkgs.writeShellScriptBin "copilot-minimax" ''
    copilot_bin="$HOME/.local/share/mise/shims/copilot"
    edge_token="$(cat "${sopsSecrets.llm_gateway_api_key.path}" 2>/dev/null || echo "")"
    if [ ! -x "$copilot_bin" ]; then
      echo "copilot-minimax: expected mise GitHub Copilot CLI at $copilot_bin" >&2
      exit 127
    fi
    if [ -z "$edge_token" ]; then
      echo "copilot-minimax: failed to read llm_gateway_api_key SOPS secret" >&2
      exit 1
    fi
    ${gatewayUrlResolver "copilot-minimax"}
    export RUST_LOG=warn
    export COPILOT_PROVIDER_TYPE=openai
    export COPILOT_PROVIDER_BASE_URL="$gateway_url/v1"
    export COPILOT_PROVIDER_API_KEY="$edge_token"
    export COPILOT_MODEL=auto-minimax
    export COPILOT_PROVIDER_MAX_PROMPT_TOKENS=512000
    export COPILOT_PROVIDER_MAX_OUTPUT_TOKENS=131072

    node "$HOME/.copilot/byok-models-patch.cjs" 2>/dev/null || true

    copilot_app="$HOME/.local/share/mise/installs/npm-github-copilot/latest/lib/node_modules/@github/copilot/node_modules/@github/copilot-linux-x64/app.js"
    if [ -f "$copilot_app" ]; then
      exec node "$copilot_app" "$@"
    fi
    exec "$copilot_bin" "$@"
  '';

  # claude-minimax — Claude Code CLI routed to MiniMax-M3 through the
  # centralcloud-ai-proxy gateway's Anthropic-Messages-compatible endpoint
  # (llm-gateway.centralcloud.com/v1/messages) via BYOK. The gateway's `auto`/
  # `umans-*` aliases currently hang on this route (only wired through the
  # OpenAI-compatible /v1/chat/completions path) — minimax-m3 is confirmed
  # working, so it's pinned explicitly rather than left to alias resolution.
  claudeMinimaxWrapper = pkgs.writeShellScriptBin "claude-minimax" ''
    claude_bin="$HOME/.local/bin/claude"
    edge_token="$(cat "${sopsSecrets.llm_gateway_api_key.path}" 2>/dev/null || echo "")"
    if [ ! -x "$claude_bin" ]; then
      echo "claude-minimax: expected Claude Code CLI at $claude_bin" >&2
      exit 127
    fi
    if [ -z "$edge_token" ]; then
      echo "claude-minimax: failed to read llm_gateway_api_key SOPS secret" >&2
      exit 1
    fi
    ${gatewayUrlResolver "claude-minimax"}
    export ANTHROPIC_BASE_URL="$gateway_url"
    export ANTHROPIC_API_KEY="$edge_token"
    export API_TIMEOUT_MS=120000
    exec "$claude_bin" --model minimax-m3 "$@"
  '';

  # copilot-all — GitHub Copilot CLI routed through the centralcloud-ai-proxy
  # at llm-gateway.centralcloud.com (the external DNS name for the
  # inference-fabric-edge service). No port-forward needed.
  copilotAllWrapper = pkgs.writeShellScriptBin "copilot-all" ''
    copilot_bin="$HOME/.local/share/mise/shims/copilot"
    edge_token="$(cat "${sopsSecrets.llm_gateway_api_key.path}" 2>/dev/null || echo "")"
    if [ ! -x "$copilot_bin" ]; then
      echo "copilot-all: expected mise GitHub Copilot CLI at $copilot_bin" >&2
      exit 127
    fi
    if [ -z "$edge_token" ]; then
      echo "copilot-all: failed to read llm_gateway_api_key SOPS secret" >&2
      exit 1
    fi
    ${gatewayUrlResolver "copilot-all"}

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
    # kimi is managed by mise (npm:@moonshot-ai/kimi-code) and wrapped in
    # ~/.local/bin/kimi to route through the CentralCloud llm-gateway.
    vtcodeWrapper
    vtcodeCloudWrapper
    vtcodeDevstralWrapper
    vtcodeMistralWrapper
    vtcodeKimiWrapper
    vtcodeMinimaxGatewayWrapper # binary: vtcode-minimax -> routes vtcode to MiniMax-M3 via llm-gateway
    vtcodeOpencodeWrapper
    # Raw llm-agents packages — no key injection needed.
    # NOTE: numtide's prebuilt cache is x86_64-only. On aarch64 (laptop)
    # these packages compile from source — disable per-host as needed.
    pkgs.claude-code # sadjow/claude-code-nix overlay — official native binary, hourly-fresh, Cachix-cached. (Was mise; native installer's runtime self-updater is disabled in Nix.)
    # llm-pkgs.codex # disabled — Rust rebuild on aarch64
    # opencode is managed globally by mise.
    # llm-pkgs.goose-cli # disabled — Rust rebuild on aarch64
    llm-pkgs.cursor-agent # binary: cursor-agent
    # droid is managed globally by mise.
    copilotKimiWrapper # binary: copilot-kimi -> routes mise GitHub Copilot CLI to Kimi K2.7 (umans-kimi-k2.7) via llm-gateway
    copilotGlmWrapper  # binary: copilot-glm -> routes mise GitHub Copilot CLI to GLM-5.2 (umans-glm-5.2) via llm-gateway
    copilotMinimaxWrapper  # binary: copilot-minimax -> routes mise GitHub Copilot CLI to MiniMax-M3 (auto-minimax) via llm-gateway
    copilotAllWrapper     # binary: copilot-all -> routes mise GitHub Copilot CLI through local centralcloud-ai-proxy (GLM-5.2 + Kimi K2.7 + umans-flash via umans.ai, MiniMax-M3 via minimax.io)
    claudeMinimaxWrapper   # binary: claude-minimax -> routes Claude Code CLI to MiniMax-M3 via llm-gateway's Anthropic-Messages endpoint
    llm-pkgs.mistral-vibe # binary: vibe
    # llm-pkgs.amp disabled until amp/token added to secrets/api-keys.yaml
  ];

  # Shadow the mise `kimi` shim so `kimi` routes through the CentralCloud
  # llm-gateway by default. ~/.local/bin is before ~/.local/share/mise/shims in
  # PATH, so this wrapper wins. Falls back to native Moonshot endpoints when
  # LLM_MUX_* are not exported (e.g. non-interactive shells without SOPS loader).
  home.file.".local/bin/kimi" = {
    executable = true;
    force = true;
    text = ''
      #!/usr/bin/env bash
      set -euo pipefail

      if [ -n "''${LLM_MUX_API_KEY:-}" ] && [ -n "''${LLM_MUX_BASE_URL:-}" ]; then
        export KIMI_API_KEY="$LLM_MUX_API_KEY"
        export KIMI_BASE_URL="$LLM_MUX_BASE_URL"
      fi

      exec "$HOME/.local/share/mise/shims/kimi" "$@"
    '';
  };
}
