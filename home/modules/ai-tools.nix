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
#   openrouter/api_key → kv/openrouter:api_key
#   amp/token          → kv/amp:token
#
# Tools managed by mise (see config/mise/config.toml) rely on the SOPS secret
# loader in shell/bash/bashrc for API keys. Wrappers below are only for tools
# that need key injection where the SOPS loader is not available.
{
  config,
  pkgs,
  llm-agents,
  ...
}: let
  sopsSecrets = config.sops.secrets;
  llm-pkgs = llm-agents.packages.${pkgs.stdenv.hostPlatform.system};

  # Prefer in-cluster Service (https then http on .svc), then public edge.
  # Note: llm-gateway.svc currently answers on http; https probe fails fast.
  # `edge_token` is already set (and checked non-empty) by the caller.
  gatewayUrlResolver = binName: ''
    gateway_url=""
    for candidate in \
      "https://llm-gateway.svc" \
      "http://llm-gateway.svc" \
      "https://llm-gateway.centralcloud.com"; do
      if curl -skS --max-time 2 -H "authorization: Bearer $edge_token" \
          "$candidate/v1/models" >/dev/null 2>&1; then
        gateway_url="$candidate"
        break
      fi
    done
    if [ -z "$gateway_url" ]; then
      echo "${binName}: gateway not reachable (tried llm-gateway.svc https/http and llm-gateway.centralcloud.com)" >&2
      exit 1
    fi
  '';

  # One client process gets one inherited repository-workspace owner. Tool
  # subprocesses keep this identity; hostnames and transient child PIDs never
  # become lease owners. The same ID is attached to OTLP resource attributes.
  clientSessionIdentity = client: ''
    if [ -z "''${SE_WORKSPACE_OWNER:-}" ]; then
      client_session_id="$(${pkgs.coreutils}/bin/tr -d '\n' < /proc/sys/kernel/random/uuid)"
      export SE_WORKSPACE_OWNER="${client}:$client_session_id"
    else
      client_session_id="''${SE_WORKSPACE_OWNER#*:}"
    fi
    export OTEL_RESOURCE_ATTRIBUTES="''${OTEL_RESOURCE_ATTRIBUTES:+$OTEL_RESOURCE_ATTRIBUTES,}agent.client=${client},agent.session.id=$client_session_id"
  '';

  # ampWrapper disabled until `amp` section exists in secrets/api-keys.yaml.
  # When ready, re-enable + add the amp_token sops.secrets block below.

  # vtcode — mise binary, always openai → http://llm-gateway.svc/v1 only
  # (no public edge fallback). MCP is pinned in ~/.vtcode/vtcode.toml to
  # http://mcp-gateway.svc/mcp via activation.nix. ~/.local/bin/vtcode shadows
  # the raw mise install so this wrapper wins after bashrc PATH re-prepend.
  vtcodeGatewayEnv = binName: model: ''
    set -euo pipefail
    # shellcheck source=/dev/null
    [ -f "$HOME/.dotfiles/shell/bash/otel-env.sh" ] && . "$HOME/.dotfiles/shell/bash/otel-env.sh"
    export OTEL_SERVICE_NAME="''${OTEL_SERVICE_NAME:-${binName}}"
    vtcode_bin="$HOME/.local/share/mise/shims/vtcode"
    if [ ! -x "$vtcode_bin" ]; then
      echo "${binName}: expected mise vtcode at $vtcode_bin" >&2
      exit 127
    fi
    edge_token="$(cat "${sopsSecrets.llm_gateway_api_key.path}" 2>/dev/null || true)"
    if [ -z "''${edge_token:-}" ] && command -v bao >/dev/null 2>&1; then
      edge_token="$(
        BAO_ADDR="''${BAO_ADDR:-https://kv.infra.centralcloud.com}" \
          bao kv get -field=api_key -mount=kv llm-gateway 2>/dev/null || true
      )"
    fi
    if [ -z "''${edge_token:-}" ]; then
      echo "${binName}: missing llm-gateway token (SOPS llm_gateway_api_key or bao kv/llm-gateway api_key)" >&2
      exit 1
    fi
    gateway_url="http://llm-gateway.svc"
    export OPENAI_API_KEY="$edge_token"
    export OPENAI_BASE_URL="$gateway_url/v1"
    exec "$vtcode_bin" \
      --provider openai --model ${model} --api-key-env OPENAI_API_KEY \
      "$@"
  '';

  vtcodeWrapper = pkgs.writeShellScriptBin "vtcode" (vtcodeGatewayEnv "vtcode" "auto-glm");
  # Model aliases — still llm-gateway.svc only (no other providers).
  vtcodeMinimaxGatewayWrapper = pkgs.writeShellScriptBin "vtcode-minimax" (vtcodeGatewayEnv "vtcode-minimax" "minimax-m3");
  vtcodeKimiWrapper = pkgs.writeShellScriptBin "vtcode-kimi" (vtcodeGatewayEnv "vtcode-kimi" "auto-kimi");
  vtcodeGlmWrapper = pkgs.writeShellScriptBin "vtcode-glm" (vtcodeGatewayEnv "vtcode-glm" "auto-glm");

  # copilot-kimi — GitHub Copilot CLI routed to the Kimi Code platform via BYOK.
  # Kimi /coding/v1 allowlists User-Agent (KimiCLI/*, Claude Code, etc.) and
  # rejects Copilot's default UA with 403, so we override it via
  # COPILOT_AGENT_REQUEST_HEADERS.
  # copilot-kimi — GitHub Copilot CLI routed to Kimi K2.7 (umans-kimi-k2.7)
  # through the centralcloud-ai-proxy gateway at llm-gateway.centralcloud.com
  # via BYOK. Kimi K2.7 has a 262K token context window and 32K max output.
  copilotKimiWrapper = pkgs.writeShellScriptBin "copilot-kimi" ''
    set -euo pipefail
    ${clientSessionIdentity "copilot"}
    # shellcheck source=/dev/null
    [ -f "$HOME/.dotfiles/shell/bash/otel-env.sh" ] && . "$HOME/.dotfiles/shell/bash/otel-env.sh"
    export OTEL_SERVICE_NAME="''${OTEL_SERVICE_NAME:-copilot-kimi}"
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
    set -euo pipefail
    ${clientSessionIdentity "copilot"}
    # shellcheck source=/dev/null
    [ -f "$HOME/.dotfiles/shell/bash/otel-env.sh" ] && . "$HOME/.dotfiles/shell/bash/otel-env.sh"
    export OTEL_SERVICE_NAME="''${OTEL_SERVICE_NAME:-copilot-glm}"
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
    set -euo pipefail
    ${clientSessionIdentity "copilot"}
    # shellcheck source=/dev/null
    [ -f "$HOME/.dotfiles/shell/bash/otel-env.sh" ] && . "$HOME/.dotfiles/shell/bash/otel-env.sh"
    export OTEL_SERVICE_NAME="''${OTEL_SERVICE_NAME:-copilot-minimax}"
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
    set -euo pipefail
    # shellcheck source=/dev/null
    [ -f "$HOME/.dotfiles/shell/bash/otel-env.sh" ] && . "$HOME/.dotfiles/shell/bash/otel-env.sh"
    export OTEL_SERVICE_NAME="''${OTEL_SERVICE_NAME:-claude-minimax}"
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
    set -euo pipefail
    ${clientSessionIdentity "copilot"}
    # shellcheck source=/dev/null
    [ -f "$HOME/.dotfiles/shell/bash/otel-env.sh" ] && . "$HOME/.dotfiles/shell/bash/otel-env.sh"
    export OTEL_SERVICE_NAME="''${OTEL_SERVICE_NAME:-copilot-all}"
    # Copilot's native hook processor launches the configured POSIX command
    # through the literal executable name `bash`.  Keep that runtime and the
    # shared Node hook deterministic even when the caller has a minimal PATH.
    export PATH="${pkgs.bash}/bin:${pkgs.coreutils}/bin:${pkgs.nodejs}/bin:$PATH"
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
  # goose — aaif-goose via mise.
  # Default: openai → llm-gateway.svc /v1 (SOPS/bao token), model minimax-coding-plan/MiniMax-M3 (1M ctx, tools+reasoning).
  # Swarm alternatives: kimi-code/k3 (1M ctx), ollama-deepseek-v4-pro (524K ctx).
  # ACP backends (claude-acp / codex-acp) stay available via wrappers but are disabled in config.
  # Provider resolution: $GOOSE_PROVIDER > config active_provider > openai.
  gooseGatewayWrapper = pkgs.writeShellScriptBin "goose" ''
    set -euo pipefail
    ${clientSessionIdentity "goose"}
        # shellcheck source=/dev/null
        [ -f "$HOME/.dotfiles/shell/bash/otel-env.sh" ] && . "$HOME/.dotfiles/shell/bash/otel-env.sh"
        export OTEL_SERVICE_NAME="''${OTEL_SERVICE_NAME:-goose}"
        goose_bin="$HOME/.local/share/mise/shims/goose"
        if [ ! -x "$goose_bin" ]; then
          goose_bin="$(ls -1d "$HOME"/.local/share/mise/installs/aqua-aaif-goose-goose/*/goose 2>/dev/null | sort -V | tail -n 1 || true)"
        fi
        if [ -z "''${goose_bin:-}" ] || [ ! -x "$goose_bin" ]; then
          echo "goose: binary not found (mise use -g aqua:aaif-goose/goose)" >&2
          exit 127
        fi

        cfg="$HOME/.config/goose/config.yaml"
        if [ -n "''${GOOSE_PROVIDER:-}" ]; then
          provider="$GOOSE_PROVIDER"
        elif [ -f "$cfg" ]; then
          provider="$(
            ${pkgs.python3}/bin/python3 - "$cfg" <<'PY'
    import sys
    from pathlib import Path
    try:
        import yaml
    except ImportError:
        print("openai")
        raise SystemExit(0)
    cfg = yaml.safe_load(Path(sys.argv[1]).read_text(encoding="utf-8")) or {}
    provider = cfg.get("GOOSE_PROVIDER") or cfg.get("active_provider") or "openai"
    print(provider)
    PY
          )"
        else
          provider="openai"
        fi
        export GOOSE_PROVIDER="$provider"

        case "$provider" in
          claude-acp|codex-acp)
            export GOOSE_MODEL="''${GOOSE_MODEL:-current}"
            if [ "$provider" = "codex-acp" ]; then
              export CODEX_HOME="''${CODEX_HOME:-$HOME/.codex}"
              unset OPENAI_API_KEY CODEX_API_KEY || true
            fi
            exec "$goose_bin" "$@"
            ;;
        esac

        edge_token="$(cat "${sopsSecrets.llm_gateway_api_key.path}" 2>/dev/null || true)"
        if [ -z "''${edge_token:-}" ] && command -v bao >/dev/null 2>&1; then
          edge_token="$(
            BAO_ADDR="''${BAO_ADDR:-https://kv.infra.centralcloud.com}" \
              bao kv get -field=api_key -mount=kv llm-gateway 2>/dev/null || true
          )"
        fi
        if [ -z "''${edge_token:-}" ]; then
          echo "goose: missing llm-gateway token (SOPS llm_gateway_api_key or bao kv/llm-gateway api_key)" >&2
          exit 1
        fi

        ${gatewayUrlResolver "goose"}
        # Goose OPENAI_HOST is the API root (no /v1); client calls ''${OPENAI_HOST}/v1/models.
        export GOOSE_MODEL="''${GOOSE_MODEL:-minimax-coding-plan/MiniMax-M3}"
        export GOOSE_CONTEXT_LIMIT="''${GOOSE_CONTEXT_LIMIT:-1000000}"
        # Planner: kimi-code/k3 for deep reasoning (1M ctx, tools+reasoning+vision)
        export GOOSE_PLANNER_PROVIDER="''${GOOSE_PLANNER_PROVIDER:-openai}"
        export GOOSE_PLANNER_MODEL="''${GOOSE_PLANNER_MODEL:-kimi-code/k3}"
        export GOOSE_PLANNER_CONTEXT_LIMIT="''${GOOSE_PLANNER_CONTEXT_LIMIT:-1048576}"
        # Fast model for auxiliary calls (tool selection, session titles)
        export GOOSE_FAST_MODEL="''${GOOSE_FAST_MODEL:-auto-fast}"
        export OPENAI_API_KEY="$edge_token"
        export OPENAI_HOST="$gateway_url"
        export OPENAI_BASE_URL="$gateway_url/v1"
        # TOM (Top Of Mind) — inject Purpose-First guardrails every turn.
        # Allow override via GOOSE_MOIM_MESSAGE_FILE already being set.
        if [ -z "''${GOOSE_MOIM_MESSAGE_FILE:-}" ]; then
          moim_file="$HOME/.config/goose/moim-guardrails.md"
          if [ -f "$moim_file" ]; then
            export GOOSE_MOIM_MESSAGE_FILE="$moim_file"
          fi
        fi
        exec "$goose_bin" "$@"
  '';

  gooseModels = pkgs.writeShellScriptBin "goose-models" ''
        set -euo pipefail
        edge_token="$(cat "${sopsSecrets.llm_gateway_api_key.path}" 2>/dev/null || true)"
        if [ -z "''${edge_token:-}" ] && command -v bao >/dev/null 2>&1; then
          edge_token="$(
            BAO_ADDR="''${BAO_ADDR:-https://kv.infra.centralcloud.com}" \
              bao kv get -field=api_key -mount=kv llm-gateway 2>/dev/null || true
          )"
        fi
        if [ -z "''${edge_token:-}" ]; then
          echo "goose-models: missing llm-gateway token" >&2
          exit 1
        fi
        ${gatewayUrlResolver "goose-models"}
        echo "# backend: openai → llm-gateway (default: minimax-coding-plan/MiniMax-M3, ctx 1M)"
        echo "# gateway: $gateway_url/v1/models"
        curl -sS --max-time 15 -H "authorization: Bearer $edge_token" \
          "$gateway_url/v1/models" \
          | ${pkgs.python3}/bin/python3 -c '
    import json,sys
    data=json.load(sys.stdin).get("data") or []
    for item in data:
        mid=item.get("id")
        if not mid:
            continue
        ctx=item.get("context_length") or ""
        caps=",".join(item.get("capabilities") or [])
        print(f"{mid}\tctx={ctx}\tcaps={caps}")
    print(f"# {len(data)} models — goose run --provider openai --model <id> -t \"…\"", file=sys.stderr)
    '
  '';

  gooseClaude = pkgs.writeShellScriptBin "goose-claude" ''
    set -euo pipefail
    export GOOSE_PROVIDER=claude-acp
    export GOOSE_MODEL="''${GOOSE_MODEL:-current}"
    exec "$HOME/.local/bin/goose" "$@"
  '';

  gooseChatgpt = pkgs.writeShellScriptBin "goose-chatgpt" ''
    set -euo pipefail
    export GOOSE_PROVIDER=codex-acp
    export GOOSE_MODEL="''${GOOSE_MODEL:-current}"
    export CODEX_HOME="''${CODEX_HOME:-$HOME/.codex}"
    unset OPENAI_API_KEY CODEX_API_KEY || true
    exec "$HOME/.local/bin/goose" "$@"
  '';

  gooseGateway = pkgs.writeShellScriptBin "goose-gateway" ''
    set -euo pipefail
    export GOOSE_PROVIDER=openai
    export GOOSE_MODEL="''${GOOSE_MODEL:-minimax-coding-plan/MiniMax-M3}"
    export GOOSE_CONTEXT_LIMIT="''${GOOSE_CONTEXT_LIMIT:-1000000}"
    exec "$HOME/.local/bin/goose" "$@"
  '';

  # goose-kimi — kimi-code/k3 (1M ctx, tools+reasoning+vision)
  gooseKimi = pkgs.writeShellScriptBin "goose-kimi" ''
    set -euo pipefail
    export GOOSE_PROVIDER=openai
    export GOOSE_MODEL="kimi-code/k3"
    export GOOSE_CONTEXT_LIMIT="1048576"
    exec "$HOME/.local/bin/goose" "$@"
  '';

  # goose-deepseek — ollama-deepseek-v4-pro (524K ctx, tools+reasoning)
  gooseDeepseek = pkgs.writeShellScriptBin "goose-deepseek" ''
    set -euo pipefail
    export GOOSE_PROVIDER=openai
    export GOOSE_MODEL="ollama-deepseek-v4-pro"
    export GOOSE_CONTEXT_LIMIT="524288"
    exec "$HOME/.local/bin/goose" "$@"
  '';

  # goose-minimax — minimax-ai/MiniMax-M3 direct (128K ctx, tools, minimax.io)
  gooseMinimax = pkgs.writeShellScriptBin "goose-minimax" ''
    set -euo pipefail
    export GOOSE_PROVIDER=openai
    export GOOSE_MODEL="minimax-ai/MiniMax-M3"
    export GOOSE_CONTEXT_LIMIT="128000"
    exec "$HOME/.local/bin/goose" "$@"
  '';

  # goose-umans — umans-glm (405K ctx, tools+reasoning+structured_output)
  gooseUmans = pkgs.writeShellScriptBin "goose-umans" ''
    set -euo pipefail
    export GOOSE_PROVIDER=openai
    export GOOSE_MODEL="umans-glm"
    export GOOSE_CONTEXT_LIMIT="405504"
    exec "$HOME/.local/bin/goose" "$@"
  '';

  # goose-umans-flash — umans-flash (262K ctx, tools+reasoning+vision)
  gooseUmansFlash = pkgs.writeShellScriptBin "goose-umans-flash" ''
    set -euo pipefail
    export GOOSE_PROVIDER=openai
    export GOOSE_MODEL="umans-flash"
    export GOOSE_CONTEXT_LIMIT="262144"
    exec "$HOME/.local/bin/goose" "$@"
  '';

  # goose-umans-fast — umans-fast (262K ctx, tools+reasoning+vision)
  gooseUmansFast = pkgs.writeShellScriptBin "goose-umans-fast" ''
    set -euo pipefail
    export GOOSE_PROVIDER=openai
    export GOOSE_MODEL="umans-fast"
    export GOOSE_CONTEXT_LIMIT="262144"
    exec "$HOME/.local/bin/goose" "$@"
  '';

  # code / coder — @just-every/code (Codex fork). Config (~/.code/config.toml)
  # uses model_provider=llm-gateway → http://llm-gateway.svc/codex/v1.
  # Wrapper injects LLM_MUX_API_KEY (and prefers in-cluster gateway).
  codeGatewayWrapper = pkgs.writeShellScriptBin "coder" ''
    set -euo pipefail
    # shellcheck source=/dev/null
    [ -f "$HOME/.dotfiles/shell/bash/otel-env.sh" ] && . "$HOME/.dotfiles/shell/bash/otel-env.sh"
    export OTEL_SERVICE_NAME="''${OTEL_SERVICE_NAME:-coder}"
    code_bin=""
    for candidate in \
      "$HOME/.local/share/mise/shims/coder" \
      "$HOME/.npm-global/bin/coder"; do
      if [ -x "$candidate" ]; then
        code_bin="$candidate"
        break
      fi
    done
    if [ -z "''${code_bin:-}" ]; then
      code_bin="$(ls -1d "$HOME"/.local/share/mise/installs/npm-just-every-code/*/bin/coder 2>/dev/null | sort -V | tail -n 1 || true)"
    fi
    if [ -z "''${code_bin:-}" ] || [ ! -x "$code_bin" ]; then
      echo "coder: binary not found (mise use -g npm:@just-every/code)" >&2
      exit 127
    fi

    edge_token="''${LLM_MUX_API_KEY:-}"
    if [ -z "''${edge_token:-}" ]; then
      edge_token="$(cat "${sopsSecrets.llm_gateway_api_key.path}" 2>/dev/null || true)"
    fi
    if [ -z "''${edge_token:-}" ] && command -v bao >/dev/null 2>&1; then
      edge_token="$(
        BAO_ADDR="''${BAO_ADDR:-https://kv.infra.centralcloud.com}" \
          bao kv get -field=api_key -mount=kv llm-gateway 2>/dev/null || true
      )"
    fi
    if [ -z "''${edge_token:-}" ]; then
      echo "coder: missing llm-gateway token (SOPS llm_gateway_api_key or bao kv/llm-gateway api_key)" >&2
      exit 1
    fi

    ${gatewayUrlResolver "coder"}
    export LLM_MUX_API_KEY="$edge_token"
    # Prefer cluster Service for Responses API (matches ~/.code model_providers.llm-gateway).
    export OPENAI_API_KEY="$edge_token"
    export OPENAI_BASE_URL="''${OPENAI_BASE_URL:-$gateway_url/codex/v1}"
    export OPENAI_WIRE_API="''${OPENAI_WIRE_API:-responses}"
    exec "$code_bin" "$@"
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

  # Single `home` attrset — repeated `home.*` keys trip statix.
  home = {
    packages = [
      # API-key-injecting wrappers (shadow the raw Nix binaries for these tools).
      # kimi is managed by mise (npm:@moonshot-ai/kimi-code) and wrapped in
      # ~/.local/bin/kimi to route through the CentralCloud llm-gateway.
      # vtcode: llm-gateway.svc only (see wrappers + ~/.local/bin/vtcode).
      vtcodeWrapper
      vtcodeGlmWrapper # binary: vtcode-glm -> auto-glm via llm-gateway.svc
      vtcodeKimiWrapper # binary: vtcode-kimi -> auto-kimi via llm-gateway.svc
      vtcodeMinimaxGatewayWrapper # binary: vtcode-minimax -> minimax-m3 via llm-gateway.svc
      # Raw llm-agents packages — no key injection needed.      # NOTE: numtide's prebuilt cache is x86_64-only. On aarch64 (laptop)
      # these packages compile from source — disable per-host as needed.
      pkgs.claude-code # sadjow/claude-code-nix overlay — official native binary, hourly-fresh, Cachix-cached. (Was mise; native installer's runtime self-updater is disabled in Nix.)
      # llm-pkgs.codex # disabled — Rust rebuild on aarch64
      # opencode is managed globally by mise.
      # llm-pkgs.goose-cli # disabled — Rust rebuild on aarch64
      llm-pkgs.cursor-agent # binary: cursor-agent (wrapped below for OTEL)
      # droid is managed globally by mise (wrapped below for OTEL).
      copilotKimiWrapper # binary: copilot-kimi -> routes mise GitHub Copilot CLI to Kimi K2.7 (umans-kimi-k2.7) via llm-gateway
      copilotGlmWrapper # binary: copilot-glm -> routes mise GitHub Copilot CLI to GLM-5.2 (umans-glm-5.2) via llm-gateway
      copilotMinimaxWrapper # binary: copilot-minimax -> routes mise GitHub Copilot CLI to MiniMax-M3 (auto-minimax) via llm-gateway
      copilotAllWrapper # binary: copilot-all -> routes mise GitHub Copilot CLI through local centralcloud-ai-proxy (GLM-5.2 + Kimi K2.7 + umans-flash via umans.ai, MiniMax-M3 via minimax.io)
      claudeMinimaxWrapper # binary: claude-minimax -> routes Claude Code CLI to MiniMax-M3 via llm-gateway's Anthropic-Messages endpoint
      gooseGatewayWrapper # binary: goose -> resolves provider; openai uses llm-gateway
      gooseModels # binary: goose-models -> list llm-gateway /v1/models
      gooseClaude # binary: goose-claude -> claude-acp
      gooseChatgpt # binary: goose-chatgpt -> codex-acp (~/.codex OAuth)
      gooseGateway # binary: goose-gateway -> openai via llm-gateway
      gooseKimi # binary: goose-kimi -> kimi-code/k3 (1M ctx)
      gooseDeepseek # binary: goose-deepseek -> ollama-deepseek-v4-pro (524K ctx)
      gooseMinimax # binary: goose-minimax -> minimax-ai/MiniMax-M3 (128K, direct)
      gooseUmans # binary: goose-umans -> umans-glm (405K ctx)
      gooseUmansFlash # binary: goose-umans-flash -> umans-flash (262K ctx)
      gooseUmansFast # binary: goose-umans-fast -> umans-fast (262K ctx)
      codeGatewayWrapper # binary: coder -> @just-every/code via llm-gateway.svc /codex/v1
      llm-pkgs.mistral-vibe # binary: vibe
      # llm-pkgs.amp disabled until amp/token added to secrets/api-keys.yaml
    ];

    file = {
      # Shadow the mise `kimi` shim so `kimi` routes through the CentralCloud
      # llm-gateway by default. ~/.local/bin is before ~/.local/share/mise/shims in
      # PATH, so this wrapper wins. Falls back to native Moonshot endpoints when
      # LLM_MUX_* are not exported (e.g. non-interactive shells without SOPS loader).
      ".local/bin/kimi" = {
        executable = true;
        force = true;
        text = ''
          #!/usr/bin/env bash
          set -euo pipefail

          # shellcheck source=/dev/null
          [ -f "$HOME/.dotfiles/shell/bash/otel-env.sh" ] && . "$HOME/.dotfiles/shell/bash/otel-env.sh"
          export OTEL_SERVICE_NAME="''${OTEL_SERVICE_NAME:-kimi-code}"

          if [ -n "''${LLM_MUX_API_KEY:-}" ] && [ -n "''${LLM_MUX_BASE_URL:-}" ]; then
            export KIMI_API_KEY="$LLM_MUX_API_KEY"
            export KIMI_BASE_URL="$LLM_MUX_BASE_URL"
          fi

          exec "$HOME/.local/share/mise/shims/kimi" "$@"
        '';
      };

      # Qoder CLI lives under ~/.qoder/bin/qodercli/qodercli-<ver> and is not on
      # PATH by default. Keep a stable ~/.local/bin entry that tracks version.txt.
      ".local/bin/qodercli" = {
        executable = true;
        force = true;
        text = ''
          #!/usr/bin/env bash
          set -euo pipefail
          # shellcheck source=/dev/null
          [ -f "$HOME/.dotfiles/shell/bash/otel-env.sh" ] && . "$HOME/.dotfiles/shell/bash/otel-env.sh"
          export OTEL_SERVICE_NAME="''${OTEL_SERVICE_NAME:-qoder}"
          root="$HOME/.qoder/bin/qodercli"
          bin=""
          if [[ -f "$root/version.txt" ]]; then
            ver="$(tr -d '[:space:]' <"$root/version.txt")"
            [[ -n "$ver" && -x "$root/qodercli-$ver" ]] && bin="$root/qodercli-$ver"
          fi
          if [[ -z "$bin" ]]; then
            bin="$(ls -1 "$root"/qodercli-* 2>/dev/null | sort -V | tail -n 1 || true)"
          fi
          [[ -n "$bin" && -x "$bin" ]] || {
            echo "qodercli: no binary under $root (install Qoder CLI first)" >&2
            exit 127
          }
          exec "$bin" "$@"
        '';
      };

      # Bare GitHub Copilot CLI (mise) — inject OTEL; model routing stays on
      # copilot-kimi / copilot-glm / copilot-minimax / copilot-all.
      ".local/bin/copilot" = {
        executable = true;
        force = true;
        text = ''
          #!/usr/bin/env bash
          set -euo pipefail
          ${clientSessionIdentity "copilot"}
          # shellcheck source=/dev/null
          [ -f "$HOME/.dotfiles/shell/bash/otel-env.sh" ] && . "$HOME/.dotfiles/shell/bash/otel-env.sh"
          export OTEL_SERVICE_NAME="''${OTEL_SERVICE_NAME:-copilot}"
          exec "$HOME/.local/share/mise/shims/copilot" "$@"
        '';
      };

      # Claude Code — call the Nix package directly (avoid ~/.local/bin recursion).
      ".local/bin/claude" = {
        executable = true;
        force = true;
        text = ''
          #!/usr/bin/env bash
          set -euo pipefail
          # shellcheck source=/dev/null
          [ -f "$HOME/.dotfiles/shell/bash/otel-env.sh" ] && . "$HOME/.dotfiles/shell/bash/otel-env.sh"
          export OTEL_SERVICE_NAME="''${OTEL_SERVICE_NAME:-claude-code}"
          exec "${pkgs.claude-code}/bin/claude" "$@"
        '';
      };

      # Codex CLI — mise-managed; inject OTEL.
      ".local/bin/codex" = {
        executable = true;
        force = true;
        text = ''
          #!/usr/bin/env bash
          set -euo pipefail
          # shellcheck source=/dev/null
          [ -f "$HOME/.dotfiles/shell/bash/otel-env.sh" ] && . "$HOME/.dotfiles/shell/bash/otel-env.sh"
          export OTEL_SERVICE_NAME="''${OTEL_SERVICE_NAME:-codex}"
          exec "$HOME/.local/share/mise/shims/codex" "$@"
        '';
      };

      # OpenCode — mise-managed; inject OTEL (native OTLP when
      # OTEL_EXPORTER_OTLP_ENDPOINT is set; AI SDK spans via
      # experimental.openTelemetry in ~/.config/opencode/opencode.json).
      ".local/bin/opencode" = {
        executable = true;
        force = true;
        text = ''
          #!/usr/bin/env bash
          set -euo pipefail
          # shellcheck source=/dev/null
          [ -f "$HOME/.dotfiles/shell/bash/otel-env.sh" ] && . "$HOME/.dotfiles/shell/bash/otel-env.sh"
          export OTEL_SERVICE_NAME="''${OTEL_SERVICE_NAME:-opencode}"
          exec "$HOME/.local/share/mise/shims/opencode" "$@"
        '';
      };

      # VT Code — shadow mise install so llm-gateway.svc wrapper wins.
      # Delegates to the HM package (same name in nix-profile) which injects
      # OPENAI_BASE_URL=http://llm-gateway.svc/v1 + OTEL.
      ".local/bin/vtcode" = {
        executable = true;
        force = true;
        text = ''
          #!/usr/bin/env bash
          set -euo pipefail
          exec "$HOME/.nix-profile/bin/vtcode" "$@"
        '';
      };

      ".local/bin/qoder" = {
        executable = true;
        force = true;
        text = ''
          #!/usr/bin/env bash
          set -euo pipefail
          exec "$HOME/.local/bin/qodercli" "$@"
        '';
      };

      # Cursor Agent CLI — OTEL env + prefer HM package if present.
      ".local/bin/cursor-agent" = {
        executable = true;
        force = true;
        text = ''
          #!/usr/bin/env bash
          set -euo pipefail
          # shellcheck source=/dev/null
          [ -f "$HOME/.dotfiles/shell/bash/otel-env.sh" ] && . "$HOME/.dotfiles/shell/bash/otel-env.sh"
          export OTEL_SERVICE_NAME="''${OTEL_SERVICE_NAME:-cursor-agent}"
          for candidate in \
            "${llm-pkgs.cursor-agent}/bin/cursor-agent" \
            "$HOME/.local/share/mise/shims/cursor-agent" \
            "$HOME/.nix-profile/bin/cursor-agent"; do
            if [ -x "$candidate" ]; then
              exec "$candidate" "$@"
            fi
          done
          echo "cursor-agent: binary not found" >&2
          exit 127
        '';
      };

      # Factory Droid — mise-managed; inject OTEL.
      ".local/bin/droid" = {
        executable = true;
        force = true;
        text = ''
          #!/usr/bin/env bash
          set -euo pipefail
          # shellcheck source=/dev/null
          [ -f "$HOME/.dotfiles/shell/bash/otel-env.sh" ] && . "$HOME/.dotfiles/shell/bash/otel-env.sh"
          export OTEL_SERVICE_NAME="''${OTEL_SERVICE_NAME:-factory-droid}"
          exec "$HOME/.local/share/mise/shims/droid" "$@"
        '';
      };

      # Shadow mise `goose` so the llm-gateway + SOPS/bao inject wrapper wins
      # (~/.local/bin before mise shims).
      ".local/bin/goose" = {
        executable = true;
        force = true;
        source = "${gooseGatewayWrapper}/bin/goose";
      };

      ".local/bin/goose-models" = {
        executable = true;
        force = true;
        source = "${gooseModels}/bin/goose-models";
      };

      ".local/bin/goose-claude" = {
        executable = true;
        force = true;
        source = "${gooseClaude}/bin/goose-claude";
      };

      ".local/bin/goose-chatgpt" = {
        executable = true;
        force = true;
        source = "${gooseChatgpt}/bin/goose-chatgpt";
      };

      ".local/bin/goose-gateway" = {
        executable = true;
        force = true;
        source = "${gooseGateway}/bin/goose-gateway";
      };

      ".local/bin/goose-kimi" = {
        executable = true;
        force = true;
        source = "${gooseKimi}/bin/goose-kimi";
      };

      ".local/bin/goose-deepseek" = {
        executable = true;
        force = true;
        source = "${gooseDeepseek}/bin/goose-deepseek";
      };

      ".local/bin/goose-minimax" = {
        executable = true;
        force = true;
        source = "${gooseMinimax}/bin/goose-minimax";
      };

      ".local/bin/goose-umans" = {
        executable = true;
        force = true;
        source = "${gooseUmans}/bin/goose-umans";
      };

      ".local/bin/goose-umans-flash" = {
        executable = true;
        force = true;
        source = "${gooseUmansFlash}/bin/goose-umans-flash";
      };

      ".local/bin/goose-umans-fast" = {
        executable = true;
        force = true;
        source = "${gooseUmansFast}/bin/goose-umans-fast";
      };
    };
  };
}
