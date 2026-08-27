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
    export OTEL_SERVICE_NAME="${binName}"
    vtcode_bin="$HOME/.local/share/mise/shims/vtcode"
    if [ ! -x "$vtcode_bin" ]; then
      echo "${binName}: expected mise vtcode at $vtcode_bin" >&2
      exit 127
    fi
    edge_token="$(cat "${sopsSecrets.llm_gateway_api_key.path}" 2>/dev/null || true)"
    if [ -z "''${edge_token:-}" ] && command -v bao >/dev/null 2>&1; then
      edge_token="$(
        BAO_ADDR="''${BAO_ADDR:-http://vault-active.vault.svc.cluster.local:8200}" \
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

  # goose — upstream GitHub releases via mise.
  # Default: openai → llm-gateway.svc /v1 (SOPS/bao token), model kimi-code/k3 (1M ctx, tools+reasoning+vision).
  # Planner: minimax-coding-plan/MiniMax-M3; swarm alternative: auto-deepseek.
  # ACP backend (claude-acp) stays available via wrappers but is disabled in config.
  # Provider resolution: $GOOSE_PROVIDER > config active_provider > openai.
  gooseGatewayWrapper = pkgs.writeShellScriptBin "goose" ''
    set -euo pipefail
    ${clientSessionIdentity "goose"}
        # shellcheck source=/dev/null
        [ -f "$HOME/.dotfiles/shell/bash/otel-env.sh" ] && . "$HOME/.dotfiles/shell/bash/otel-env.sh"
        export OTEL_SERVICE_NAME="goose"
        # Prefer the installed binary: an executable mise shim can still fail
        # when the Aqua registry is temporarily unavailable.
        goose_bin="$(ls -1d "$HOME"/.local/share/mise/installs/github-aaif-goose-goose/*/goose 2>/dev/null | sort -V | tail -n 1 || true)"
        if [ -z "''${goose_bin:-}" ] || [ ! -x "$goose_bin" ]; then
          goose_bin="$HOME/.local/share/mise/shims/goose"
        fi
        if [ -z "''${goose_bin:-}" ] || [ ! -x "$goose_bin" ]; then
          echo "goose: binary not found (mise use -g github:aaif-goose/goose)" >&2
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
          claude-acp)
            export GOOSE_MODEL="''${GOOSE_MODEL:-current}"
            exec "$goose_bin" "$@"
            ;;
        esac

        edge_token="$(cat "${sopsSecrets.llm_gateway_api_key.path}" 2>/dev/null || true)"
        if [ -z "''${edge_token:-}" ] && command -v bao >/dev/null 2>&1; then
          edge_token="$(
            BAO_ADDR="''${BAO_ADDR:-http://vault-active.vault.svc.cluster.local:8200}" \
              bao kv get -field=api_key -mount=kv llm-gateway 2>/dev/null || true
          )"
        fi
        if [ -z "''${edge_token:-}" ]; then
          echo "goose: missing llm-gateway token (SOPS llm_gateway_api_key or bao kv/llm-gateway api_key)" >&2
          exit 1
        fi

        ${gatewayUrlResolver "goose"}
        # Goose OPENAI_HOST is the API root (no /v1); client calls ''${OPENAI_HOST}/v1/models.
        export GOOSE_MODEL="''${GOOSE_MODEL:-kimi-code/k3}"
        export GOOSE_CONTEXT_LIMIT="''${GOOSE_CONTEXT_LIMIT:-1048576}"
        # Planner: MiniMax-M3 (1M ctx, tools+reasoning)
        export GOOSE_PLANNER_PROVIDER="''${GOOSE_PLANNER_PROVIDER:-openai}"
        export GOOSE_PLANNER_MODEL="''${GOOSE_PLANNER_MODEL:-minimax-coding-plan/MiniMax-M3}"
        export GOOSE_PLANNER_CONTEXT_LIMIT="''${GOOSE_PLANNER_CONTEXT_LIMIT:-1000000}"
        # Fast model for auxiliary calls (tool selection, session titles)
        export GOOSE_FAST_MODEL="''${GOOSE_FAST_MODEL:-auto-flash}"
        export GOOSE_MAX_BACKGROUND_TASKS="''${GOOSE_MAX_BACKGROUND_TASKS:-10}"
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
            BAO_ADDR="''${BAO_ADDR:-http://vault-active.vault.svc.cluster.local:8200}" \
              bao kv get -field=api_key -mount=kv llm-gateway 2>/dev/null || true
          )"
        fi
        if [ -z "''${edge_token:-}" ]; then
          echo "goose-models: missing llm-gateway token" >&2
          exit 1
        fi
        ${gatewayUrlResolver "goose-models"}
        echo "# backend: openai → llm-gateway (default: kimi-code/k3, ctx 1M)"
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

  gooseGateway = pkgs.writeShellScriptBin "goose-gateway" ''
    set -euo pipefail
    export GOOSE_PROVIDER=openai
    export GOOSE_MODEL="''${GOOSE_MODEL:-kimi-code/k3}"
    export GOOSE_CONTEXT_LIMIT="''${GOOSE_CONTEXT_LIMIT:-1048576}"
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

  # goose-deepseek — auto-deepseek (Ollama Cloud DeepSeek V4 Pro)
  gooseDeepseek = pkgs.writeShellScriptBin "goose-deepseek" ''
    set -euo pipefail
    export GOOSE_PROVIDER=openai
    export GOOSE_MODEL="auto-deepseek"
    export GOOSE_CONTEXT_LIMIT="131072"
    exec "$HOME/.local/bin/goose" "$@"
  '';

  # goose-glm — auto-glm (Ollama Cloud GLM-5.2)
  gooseGlm = pkgs.writeShellScriptBin "goose-glm" ''
    set -euo pipefail
    export GOOSE_PROVIDER=openai
    export GOOSE_MODEL="auto-glm"
    export GOOSE_CONTEXT_LIMIT="131072"
    exec "$HOME/.local/bin/goose" "$@"
  '';

  # goose-qwen-fast — auto-qwen-fast (Ollama Cloud Qwen 3.5 397B)
  gooseQwenFast = pkgs.writeShellScriptBin "goose-qwen-fast" ''
    set -euo pipefail
    export GOOSE_PROVIDER=openai
    export GOOSE_MODEL="auto-qwen-fast"
    export GOOSE_CONTEXT_LIMIT="131072"
    exec "$HOME/.local/bin/goose" "$@"
  '';

  # code / coder — @just-every/code (Codex fork). Config (~/.code/config.toml)
  # uses model_provider=llm-gateway → http://llm-gateway.svc/codex/v1.
  # Wrapper injects LLM_MUX_API_KEY (and prefers in-cluster gateway).
  codeGatewayWrapper = pkgs.writeShellScriptBin "coder" ''
    set -euo pipefail
    # shellcheck source=/dev/null
    [ -f "$HOME/.dotfiles/shell/bash/otel-env.sh" ] && . "$HOME/.dotfiles/shell/bash/otel-env.sh"
    export OTEL_SERVICE_NAME="coder"
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
        BAO_ADDR="''${BAO_ADDR:-http://vault-active.vault.svc.cluster.local:8200}" \
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

  # Cursor Agent — shared OTEL wrapper for ~/.local/bin/cursor-agent and agent.
  # Resolution: newest Cursor installer binary, then Nix store pin, then mise
  # install tree (never the mise shim or these wrappers — avoids recursion).
  cursorAgentEntrypoint = ''
    #!/usr/bin/env bash
    set -euo pipefail
    # shellcheck source=/dev/null
    [ -f "$HOME/.dotfiles/shell/bash/otel-env.sh" ] && . "$HOME/.dotfiles/shell/bash/otel-env.sh"
    export OTEL_SERVICE_NAME="cursor-agent"

    cursor_agent_bin=""
    versions="$HOME/.local/share/cursor-agent/versions"
    if [ -d "$versions" ]; then
      cursor_agent_bin="$(ls -1dt "$versions"/*/cursor-agent 2>/dev/null | head -n 1 || true)"
    fi
    if [ -z "$cursor_agent_bin" ] || [ ! -x "$cursor_agent_bin" ]; then
      nix_bin="${llm-pkgs.cursor-agent}/bin/cursor-agent"
      if [ -x "$nix_bin" ]; then
        cursor_agent_bin="$nix_bin"
      fi
    fi
    if [ -z "$cursor_agent_bin" ] || [ ! -x "$cursor_agent_bin" ]; then
      cursor_agent_bin="$(ls -1d \
        "$HOME"/.local/share/mise/installs/*/bin/cursor-agent \
        "$HOME"/.local/share/mise/installs/*/*/bin/cursor-agent \
        2>/dev/null | sort -V | tail -n 1 || true)"
    fi
    case "$cursor_agent_bin" in
      "$HOME/.local/bin/cursor-agent"|"$HOME/.local/bin/agent"|"$HOME/.local/share/mise/shims/"*)
        cursor_agent_bin=""
        ;;
    esac
    if [ -z "$cursor_agent_bin" ] || [ ! -x "$cursor_agent_bin" ]; then
      echo "cursor-agent: binary not found" >&2
      exit 127
    fi
    exec "$cursor_agent_bin" "$@"
  '';

  # jcode — shadow the self-updater binary with an exact provider allowlist:
  # llm-gateway named profile, Claude Max OAuth, and ChatGPT OAuth.
  jcodeGatewayWrapper = pkgs.writeShellScriptBin "jcode" ''
    set -euo pipefail
    ${clientSessionIdentity "jcode"}
    # shellcheck source=/dev/null
    [ -f "$HOME/.dotfiles/shell/bash/otel-env.sh" ] && . "$HOME/.dotfiles/shell/bash/otel-env.sh"
    export OTEL_SERVICE_NAME="jcode"

    edge_token="''${LLM_GATEWAY_API_KEY:-}"
    if [ -z "''${edge_token:-}" ]; then
      edge_token="$(cat "${sopsSecrets.llm_gateway_api_key.path}" 2>/dev/null || true)"
    fi
    if [ -z "''${edge_token:-}" ] && command -v bao >/dev/null 2>&1; then
      edge_token="$(
        BAO_ADDR="''${BAO_ADDR:-http://vault-active.vault.svc.cluster.local:8200}" \
          bao kv get -field=api_key -mount=kv llm-gateway 2>/dev/null || true
      )"
    fi
    if [ -z "''${edge_token:-}" ]; then
      echo "jcode: missing llm-gateway token (SOPS llm_gateway_api_key or bao kv/llm-gateway api_key)" >&2
      exit 1
    fi
    ${gatewayUrlResolver "jcode"}
    export LLM_GATEWAY_API_KEY="$edge_token"

    # Isolate jcode-owned per-provider env files from ~/.config/jcode, where
    # previously configured MiniMax/Cursor/etc. credentials may remain.
    export XDG_CONFIG_HOME="$HOME/.config/jcode-allowlisted"
    # Do not attach to a daemon started by the former unrestricted entrypoint.
    export JCODE_RUNTIME_DIR="$HOME/.jcode/runtime-allowlisted"

    # Strip ambient credentials before jcode's provider auto-detection runs.
    unset \
      ALIBABA_API_KEY \
      ALIBABA_CODING_PLAN_API_KEY \
      ALIBABA_TOKEN_PLAN_API_KEY \
      ANTHROPIC_API_KEY \
      AZURE_OPENAI_API_KEY \
      AZURE_OPENAI_ENDPOINT \
      CEREBRAS_API_KEY \
      CHUTES_API_KEY \
      COMTEGRA_API_KEY \
      COPILOT_GITHUB_TOKEN \
      CORTECS_API_KEY \
      CURSOR_ACCESS_TOKEN \
      CURSOR_API_KEY \
      CURSOR_REFRESH_TOKEN \
      DEEPINFRA_API_KEY \
      DEEPSEEK_API_KEY \
      FIREWORKS_API_KEY \
      FIRMWARE_API_KEY \
      F${"PT"}_API_KEY \
      GEMINI_API_KEY \
      GOOGLE_API_KEY \
      GOOGLE_GENERATIVE_AI_API_KEY \
      GROQ_API_KEY \
      HUGGINGFACE_API_KEY \
      HF_TOKEN \
      JCODE_NAMED_PROVIDER_PROFILE \
      JCODE_OPENAI_COMPAT_API_BASE \
      JCODE_OPENAI_COMPAT_API_KEY_NAME \
      JCODE_OPENAI_COMPAT_DEFAULT_MODEL \
      JCODE_OPENAI_COMPAT_ENV_FILE \
      JCODE_OPENROUTER_API_BASE \
      JCODE_OPENROUTER_API_KEY_NAME \
      JCODE_OPENROUTER_ENV_FILE \
      JCODE_OPENROUTER_PROVIDER \
      JCODE_PROVIDER \
      JCODE_PROVIDER_PROFILE_ACTIVE \
      JCODE_PROVIDER_PROFILE_NAME \
      KIMI_API_KEY \
      KIMI_CODE_API_KEY \
      LONGCAT_API_KEY \
      MINIMAX_API_KEY \
      MISTRAL_API_KEY \
      MOONSHOT_API_KEY \
      NEBIUS_API_KEY \
      NVIDIA_API_KEY \
      OLLAMA_API_KEY \
      OLLAMA_CLOUD_API_KEY \
      OPENAI_API_KEY \
      OPENAI_API_BASE \
      OPENAI_BASE_URL \
      OPENCODE_API_KEY \
      OPENCODE_GO_API_KEY \
      OPENROUTER_API_KEY \
      PERPLEXITY_API_KEY \
      SCALEWAY_API_KEY \
      STACKIT_API_KEY \
      TOGETHERAI_API_KEY \
      TOGETHER_API_KEY \
      XAI_API_KEY \
      XIAOMI_API_KEY \
      ZAI_API_KEY \
      GH_TOKEN \
      GITHUB_TOKEN \
      || true

    # Disable the remaining Cursor Agent CLI credential probe. File imports are
    # separately denied by [auth] in ~/.jcode/config.toml.
    export JCODE_CURSOR_CLI_PATH="/nonexistent/jcode-disabled-cursor-agent"

    jcode_bin="$HOME/.jcode/server/jcode"
    if [ ! -x "$jcode_bin" ]; then
      echo "jcode: binary not found in ~/.jcode/server/jcode" >&2
      exit 127
    fi

    allowed_provider() {
      case "$1" in
        claude|openai|minimax-direct|ollama-cloud|byteplus-ark) return 0 ;;
        *) return 1 ;;
      esac
    }

    # Fail closed for explicit provider/profile requests, even if credentials
    # for another compiled-in integration later appear on disk.
    args=("$@")
    provider_arg_seen=0
    for ((i = 0; i < ''${#args[@]}; i++)); do
      case "''${args[$i]}" in
        -p|--provider)
          provider_arg_seen=1
          i=$((i + 1))
          if [ "$i" -ge "''${#args[@]}" ] || ! allowed_provider "''${args[$i]}"; then
            echo "jcode: provider is not allowed (allowed: claude, openai, minimax-direct, ollama-cloud, byteplus-ark)" >&2
            exit 64
          fi
          ;;
        --provider=*)
          provider_arg_seen=1
          provider="''${args[$i]#--provider=}"
          if ! allowed_provider "$provider"; then
            echo "jcode: provider '$provider' is not allowed (allowed: claude, openai, minimax-direct, ollama-cloud, byteplus-ark)" >&2
            exit 64
          fi
          ;;
        -p?*)
          provider_arg_seen=1
          provider="''${args[$i]#-p}"
          if ! allowed_provider "$provider"; then
            echo "jcode: provider '$provider' is not allowed (allowed: claude, openai, minimax-direct, ollama-cloud, byteplus-ark)" >&2
            exit 64
          fi
          ;;
        --provider-profile)
          i=$((i + 1))
          if [ "$i" -ge "''${#args[@]}" ] || [ "''${args[$i]}" != "llm-gateway" ]; then
            echo "jcode: only provider profile 'llm-gateway' is allowed" >&2
            exit 64
          fi
          ;;
        --provider-profile=*)
          profile="''${args[$i]#--provider-profile=}"
          if [ "$profile" != "llm-gateway" ]; then
            echo "jcode: provider profile '$profile' is not allowed" >&2
            exit 64
          fi
          ;;
      esac
    done

    # Locate the command after global flags so `--quiet provider add ...` and
    # equivalent reorderings cannot bypass command policy.
    command_name=""
    command_arg1=""
    for ((i = 0; i < ''${#args[@]}; i++)); do
      case "''${args[$i]}" in
        --no-update|--auto-update|--trace|--quiet|--no-selfdev|--onboarding-sim|--debug-socket|--disable-base-tools)
          ;;
        -p|--provider|-C|--cwd|--remote-working-dir|--socket|-m|--model|--provider-profile|--tool-profile|--tools|--disabled-tools)
          i=$((i + 1))
          ;;
        --provider=*|--cwd=*|--remote-working-dir=*|--socket=*|--model=*|--provider-profile=*|--tool-profile=*|--tools=*|--disabled-tools=*|-p?*|-C?*|-m?*)
          ;;
        -*)
          ;;
        *)
          command_name="''${args[$i]}"
          command_arg1="''${args[$((i + 1))]:-}"
          break
          ;;
      esac
    done

    if [ "$command_name" = "provider" ] && [ "$command_arg1" = "add" ]; then
      echo "jcode: provider profiles are managed by Home Manager; only llm-gateway is allowed" >&2
      exit 64
    fi
    if [ "$command_name" = "login" ]; then
      case "$command_arg1" in
        claude|openai) ;;
        "")
          echo "jcode: specify the allowed OAuth provider: jcode login --provider claude|openai" >&2
          exit 64
          ;;
        -*)
          if [ "$provider_arg_seen" -ne 1 ]; then
            echo "jcode: login requires --provider claude or --provider openai" >&2
            exit 64
          fi
          ;;
        *)
          echo "jcode: provider $command_arg1 is not allowed for login" >&2
          exit 64
          ;;
      esac
    fi

    # These built-in inventory commands enumerate compiled integrations rather
    # than the effective allowlist, so expose the wrapper contract instead.
    if [ "$command_name" = "provider" ] && [ "$command_arg1" = "list" ]; then
      printf '%s\n' \
        "minimax-direct	OpenAI-compatible	https://api.minimax.io/v1 (MiniMax-M3)" \
        "ollama-cloud	OpenAI-compatible	https://ollama.com/v1 (glm-5.2, deepseek-v4-flash)" \
        "byteplus-ark	OpenAI-compatible	https://ark.ap-southeast.bytepluses.com/api/coding/v3 (ark-code-latest)" \
        "llm-gateway	OpenAI-compatible	internal CentralCloud LLM gateway" \
        "claude	Anthropic/Claude	Claude Pro or Max OAuth subscription" \
        "openai	OpenAI	ChatGPT Plus or Pro OAuth subscription"
      exit 0
    fi
    if [ "$command_name" = "auth" ] && [ "$command_arg1" = "status" ]; then
      if [[ " $* " = *" --json "* ]]; then
        echo "jcode: auth status --json is unavailable through the managed allowlist wrapper" >&2
        exit 64
      fi
      printf '%s\n' \
        "llm-gateway	available	API key	SOPS/bao bearer via LLM_GATEWAY_API_KEY	readiness: credential present	not validated"
      "$jcode_bin" "$@" | ${pkgs.gawk}/bin/awk '$1 == "claude" || $1 == "openai"'
      exit "''${PIPESTATUS[0]}"
    fi

    exec "$jcode_bin" "$@"
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
  };

  # Single `home` attrset — repeated `home.*` keys trip statix.
  home = {
    packages =
      [
        # API-key-injecting wrappers (shadow the raw Nix binaries for these tools).
        # kimi is managed by mise (npm:@moonshot-ai/kimi-code) and wrapped in
        # ~/.local/bin/kimi to route through the CentralCloud llm-gateway.
        # vtcode: llm-gateway.svc only (see wrappers + ~/.local/bin/vtcode).
        vtcodeWrapper
        # Raw llm-agents packages — no key injection needed.      # NOTE: numtide's prebuilt cache is x86_64-only. On aarch64 (laptop)
        # these packages compile from source — disable per-host as needed.
        # Claude Code is owned by its native installer outside Home Manager.
        # Cursor Agent is resolved by the wrapper below without a raw profile bin.
        # llm-pkgs.codex is enabled per-arch below, outside this list.
        # opencode is managed globally by mise.
        # llm-pkgs.goose-cli # disabled — Rust rebuild on aarch64
        # droid is managed globally by mise (wrapped below for OTEL).
        gooseGatewayWrapper # binary: goose -> resolves provider; openai uses llm-gateway
        gooseModels # binary: goose-models -> list llm-gateway /v1/models
        gooseClaude # binary: goose-claude -> claude-acp
        gooseGateway # binary: goose-gateway -> openai via llm-gateway
        gooseKimi # binary: goose-kimi -> kimi-code/k3 (1M ctx)
        gooseDeepseek # binary: goose-deepseek -> auto-deepseek (Ollama Cloud DeepSeek V4 Pro)
        gooseGlm # binary: goose-glm -> auto-glm (Ollama Cloud GLM-5.2)
        gooseQwenFast # binary: goose-qwen-fast -> auto-qwen-fast (Ollama Cloud Qwen 3.5 397B)
        codeGatewayWrapper # binary: coder -> @just-every/code via llm-gateway.svc /codex/v1
        jcodeGatewayWrapper # binary: jcode -> llm-gateway.svc /v1 (+ strip ambient provider keys)
        llm-pkgs.mistral-vibe # binary: vibe
        # llm-pkgs.amp disabled until amp/token added to secrets/api-keys.yaml
      ]
      # codex from llm-agents, x86_64-linux only.
      #
      # Two reasons, not one. The aarch64 laptop still has to rebuild this from
      # source (numtide's prebuilt cache is x86_64-only), so it stays off there.
      # On x86_64 it also puts codex in ~/.nix-profile/bin, and that directory
      # survives entering a repository devShell where ~/.npm-global/bin does not:
      # an interactive shell in ~/code/jcode resolves direnv-instant (nix-profile)
      # but not codex (npm-global), because the environment direnv applies there
      # drops the Home Manager session PATH entries. Owning codex here makes it
      # resolve in those shells regardless.
      #
      # Version skew, measured not assumed: the derivation is named codex-0.149.1
      # but `codex --version` from it reports codex-cli 0.148.0, while the npm
      # package reports 0.149.1. So the two are NOT identical builds. On a healthy
      # PATH ~/.npm-global/bin still precedes ~/.nix-profile/bin, so ordinary
      # shells keep getting the npm 0.149.1; only shells that lost the session
      # PATH entries fall through to this 0.148.0. Bump llm-agents when that skew
      # matters. Verified this package ships the codex-code-mode-host sidecar, so
      # it does not reproduce the aqua-registry breakage noted in mise config.
      #
      # This is deliberately NOT a fix for that PATH drop -- the root cause is
      # still open. It removes codex from the blast radius, nothing more.
      ++ pkgs.lib.optionals (pkgs.stdenv.hostPlatform.system == "x86_64-linux") [
        llm-pkgs.codex # binary: codex (+ codex-code-mode-host sidecar)
      ];

    file = {
      # jcode: shadow update/mise install so llm-gateway SOPS wrapper wins.
      ".local/bin/jcode" = {
        executable = true;
        force = true;
        source = "${jcodeGatewayWrapper}/bin/jcode";
      };

      # Managed OpenAI-compatible profile for the same fabric exposed internally
      # as http://llm-gateway.svc/v1. jcode rejects plain HTTP hostnames other
      # than localhost/private IPs, so the profile uses the public HTTPS edge.
      ".jcode/config.toml" = {
        force = true;
        text = ''
          # Managed by Home Manager (ai-tools.nix). Default traffic → llm-gateway.
          # Only Claude/ChatGPT subscription OAuth + this fabric profile are intended.
          [provider]
          default_provider = "llm-gateway"
          default_model = "auto-glm"
          model_picker_providers = ["llm-gateway", "claude", "openai"]
          cross_provider_failover = "manual"

          # Refuse external auth imports (Cursor IDE, Gemini CLI, etc.).
          [auth]
          trusted_external_sources = []
          trusted_external_source_paths = []

          [providers.llm-gateway]
          type = "openai-compatible"
          base_url = "https://llm-gateway.centralcloud.com/v1"
          auth = "bearer"
          api_key_env = "LLM_GATEWAY_API_KEY"
          default_model = "auto-glm"
          model_catalog = true
          requires_api_key = true

          [[providers.llm-gateway.models]]
          id = "auto-glm"
        '';
      };

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
          export OTEL_SERVICE_NAME="kimi-code"

          if [ -n "''${LLM_MUX_API_KEY:-}" ] && [ -n "''${LLM_MUX_BASE_URL:-}" ]; then
            export KIMI_API_KEY="$LLM_MUX_API_KEY"
            export KIMI_BASE_URL="$LLM_MUX_BASE_URL"
          fi

          exec "$HOME/.local/share/mise/shims/kimi" "$@"
        '';
      };

      # node/npm/npx entry points for mise's npm backend. mise strips its own
      # install and shim dirs from the PATH of spawned backend commands (anti-
      # recursion), so `npm view` spawns fail with ENOENT unless npm is reachable
      # on a non-mise PATH entry. ~/.local/bin survives stripping; forward to the
      # mise shims so npm-backend tools (kimi, copilot, wrangler, ...) resolve.
      ".local/bin/node" = {
        executable = true;
        force = true;
        text = ''
          #!/usr/bin/env bash
          exec "$HOME/.local/share/mise/shims/node" "$@"
        '';
      };
      ".local/bin/npm" = {
        executable = true;
        force = true;
        text = ''
          #!/usr/bin/env bash
          exec "$HOME/.local/share/mise/shims/npm" "$@"
        '';
      };
      ".local/bin/npx" = {
        executable = true;
        force = true;
        text = ''
          #!/usr/bin/env bash
          exec "$HOME/.local/share/mise/shims/npx" "$@"
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
          export OTEL_SERVICE_NAME="qoder"
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

      # Codex CLI is npm-managed (`npm i -g @openai/codex`) and needs no wrapper:
      # ~/.npm-global/bin is already on PATH via home.sessionPath.
      #
      # The former OTEL wrapper here sourced otel-env.sh and exported
      # OTEL_SERVICE_NAME. Codex 0.147.0 configures OTLP natively instead --
      # verified with `codex exec --strict-config`, which rejects unknown fields
      # and accepted otel.exporter / otel.environment / otel.log_user_prompt.
      # The exporter must be the struct form; the bare string "otlp-http" is
      # rejected with "invalid type: unit variant, expected struct variant".
      # On this host otel-env.sh resolved to the in-cluster collector with EMPTY
      # headers, so nothing dynamic was being contributed and the endpoint is
      # expressible statically. See config/codex/config.toml.

      # Codex spawns its command runner as `codex-code-mode-host`. At least one
      # invocation path resolves that name from PATH rather than beside the codex
      # binary -- that is the failure upstream reports, and it is what broke here.
      # Other paths do use the vendor sibling: processes observed at 21:54/22:04
      # ran the vendored binary while no PATH entry carried the name. So this
      # wrapper is a belt-and-braces fix for the PATH-resolving callers, not a
      # claim that every caller uses PATH. Until 2026-08-08 that name was
      # supplied by a mise shim; removing aqua:openai/codex from mise (and
      # reshimming) deleted the shim, so every Codex tool call failed with
      # "the local Codex command runner: ~/.local/bin/codex-code-mode-host is
      # missing" (openai/codex#31831, #31833). The npm package vendors the real
      # binary next to its own codex; expose it under the name Codex looks for.
      ".local/bin/codex-code-mode-host" = {
        executable = true;
        force = true;
        text = ''
          #!/usr/bin/env bash
          set -euo pipefail
          # npm links only `codex` (the meta package's sole bin; the platform
          # package declares bin: null), so the sidecar never reaches PATH.
          # Try the current layout first, then fall back to a search so a new
          # version, target triple, or npm hoisting decision does not break it.
          root="$HOME/.npm-global/lib/node_modules/@openai"
          vendor="$root/codex/node_modules/@openai/codex-linux-x64/vendor/x86_64-unknown-linux-musl/bin/codex-code-mode-host"
          if [ ! -x "$vendor" ]; then
            vendor="$(find "$root" -name codex-code-mode-host -type f -perm -u+x 2>/dev/null | head -n 1)"
          fi
          if [ -z "''${vendor:-}" ] || [ ! -x "$vendor" ]; then
            echo "codex-code-mode-host: vendored binary not found under $root (reinstall with: npm i -g @openai/codex)" >&2
            exit 127
          fi
          exec "$vendor" "$@"
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
          export OTEL_SERVICE_NAME="opencode"
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

      # Cursor Agent CLI — OTEL env; cursor-agent and agent share one wrapper.
      ".local/bin/cursor-agent" = {
        executable = true;
        force = true;
        text = cursorAgentEntrypoint;
      };

      # Cursor `agent` entrypoint (IDE / remote agent). Upstream installer
      # symlinks this to the versioned binary and never sources bashrc — so
      # long-lived sessions inherit no OTEL_*. Shadow that symlink with the
      # same OTEL loader and binary resolution as cursor-agent.
      ".local/bin/agent" = {
        executable = true;
        force = true;
        text = cursorAgentEntrypoint;
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
          export OTEL_SERVICE_NAME="factory-droid"
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

      ".local/bin/goose-glm" = {
        executable = true;
        force = true;
        source = "${gooseGlm}/bin/goose-glm";
      };

      ".local/bin/goose-qwen-fast" = {
        executable = true;
        force = true;
        source = "${gooseQwenFast}/bin/goose-qwen-fast";
      };
    };
  };
}
