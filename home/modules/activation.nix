# home/modules/activation.nix — home-manager activation hooks
#
# Runs shell commands during `hms`. Only things that cannot be declared
# statically belong here: conflict cleanup, external tool installs, binary
# extraction. Order is managed via lib.hm.dag (DAG = dependency-aware graph).
{
  config,
  pkgs,
  lib,
  ...
}: let
  pythonWithYaml = pkgs.python3.withPackages (ps: [ps.pyyaml]);
  USER_TOOL_PATH = "${config.home.homeDirectory}/.local/bin:${config.home.homeDirectory}/.npm-global/bin:${config.home.homeDirectory}/.bun/bin:${config.home.homeDirectory}/.cargo/bin";
in {
  home.activation = {
    # A previous transient user-unit failure makes home-manager report the whole
    # user manager as degraded before it reloads services. Clear stale failed
    # states first; real failures during this activation will still be reported.
    resetFailedUserUnits = lib.hm.dag.entryBefore ["reloadSystemd"] ''
      ${pkgs.systemd}/bin/systemctl --user reset-failed || true
    '';

    # Claude and Kimi keep mutable user settings alongside provider/runtime
    # state. Merge only the repo-memory hook groups and preserve every other
    # field or TOML table byte-for-byte.
    installRepoMemorySwarmHooks = lib.hm.dag.entryAfter ["writeBoundary"] ''
      ${pkgs.nodejs}/bin/node ${../../config/agent-hooks/install-swarm-hooks.mjs}
    '';

    # programs.gh and programs.jujutsu own these files as nix-store symlinks.
    # If they exist as plain files (written by `gh auth` or `jj init`) home-manager
    # aborts with "would be clobbered". Remove them before checkLinkTargets.
    removeConflictingConfigs = lib.hm.dag.entryBefore ["checkLinkTargets"] ''
      rm -f "$HOME/.config/gh/config.yml"
      rm -f "$HOME/.config/jj/config.toml"

      if [ "$(${pkgs.hostname}/bin/hostname)" = "mikki-bunker" ]; then
        rm -f "$HOME/.config/systemd/user/remote-gpu-worker.service.d/combined.conf"
        rm -f "$HOME/.config/systemd/user/remote-gpu-worker.service.d/no-watchdog.conf"
        rmdir "$HOME/.config/systemd/user/remote-gpu-worker.service.d" 2>/dev/null || true
      fi
      rm -f "$HOME/.npm-global/bin/claude"
    '';

    seedMutableCodexConfig = lib.hm.dag.entryAfter ["writeBoundary"] ''
      mkdir -p "$HOME/.codex"
      if [ -L "$HOME/.codex/config.toml" ] || [ ! -e "$HOME/.codex/config.toml" ]; then
        rm -f "$HOME/.codex/config.toml"
        cp "${../../config/codex/config.toml}" "$HOME/.codex/config.toml"
        chmod 600 "$HOME/.codex/config.toml"
      fi
    '';

    removeRetiredCodexAgentRoles = lib.hm.dag.entryAfter ["writeBoundary"] ''
      rm -f "$HOME/.codex/agents/coder.toml"
    '';

    applySharedCodexPreferences = lib.hm.dag.entryAfter ["seedMutableCodexConfig"] ''
      ${pkgs.python3}/bin/python3 "${../../scripts/codex-preferences}" apply \
        --source "${../../config/codex/shared-preferences.toml}"
      chmod 600 "$HOME/.codex/config.toml"
    '';

    linkMutableMiseConfig = lib.hm.dag.entryAfter ["writeBoundary"] ''
      mkdir -p "$HOME/.config/mise"
      target="$HOME/.dotfiles/config/mise/config.toml"
      if [ -f "$target" ]; then
        current=""
        if [ -L "$HOME/.config/mise/config.toml" ]; then
          current="$(readlink "$HOME/.config/mise/config.toml")"
        fi
        if [ "$current" != "$target" ]; then
          rm -f "$HOME/.config/mise/config.toml"
          ln -s "$target" "$HOME/.config/mise/config.toml"
        fi
      else
        echo "WARNING: mise config seed missing at $target" >&2
      fi
    '';

    # Extract personal-admin SSH key from SOPS into ~/.ssh/ for monitor,
    # portal automation, and the Hetzner storage box.
    renderPersonalAdminSshKey = lib.hm.dag.entryAfter ["installPackages"] ''
            PATH="${pkgs.sops}/bin:${pkgs.age}/bin:${pythonWithYaml}/bin:$PATH" \
            ${pythonWithYaml}/bin/python3 - <<'PY'
      import subprocess, sys, yaml
      r = subprocess.run(
        ["${pkgs.sops}/bin/sops", "--decrypt",
         "${config.home.homeDirectory}/.dotfiles/secrets/personal-servers-ssh.yaml"],
        capture_output=True, text=True)
      if r.returncode != 0:
        print("WARNING: could not decrypt personal-admin SSH key from SOPS", file=sys.stderr)
        sys.exit(0)
      key = yaml.safe_load(r.stdout)["personal_admin"]["ssh"]["private_key"]
      path = "${config.home.homeDirectory}/.ssh/personal_admin_id_ed25519"
      import os, stat
      with open(path, "w") as f:
        f.write(key if key.endswith("\n") else key + "\n")
      os.chmod(path, stat.S_IRUSR | stat.S_IWUSR)
      PY
    '';

    # Extract Hetzner SSH private key from SOPS into ~/.ssh/ so `ssh mail.hugo.dk`
    # works without a password. chmod 600 so ssh accepts it.
    renderHetznerSshKey = lib.hm.dag.entryAfter ["installPackages"] ''
            # sops --extract mangles multiline PEM keys; use python3 yaml to extract cleanly.
            PATH="${pkgs.sops}/bin:${pkgs.age}/bin:${pythonWithYaml}/bin:$PATH" \
            ${pythonWithYaml}/bin/python3 - <<'PY'
      import subprocess, sys, yaml
      r = subprocess.run(
        ["${pkgs.sops}/bin/sops", "--decrypt",
         "${config.home.homeDirectory}/.dotfiles/secrets/hetzner-ssh.yaml"],
        capture_output=True, text=True)
      if r.returncode != 0:
        print("WARNING: could not decrypt hetzner SSH key from SOPS", file=sys.stderr)
        sys.exit(0)
      key = yaml.safe_load(r.stdout)["hetzner"]["ssh"]["private_key"]
      path = "${config.home.homeDirectory}/.ssh/hetzner_id_ed25519"
      import os, stat
      with open(path, "w") as f:
        f.write(key if key.endswith("\n") else key + "\n")
      os.chmod(path, stat.S_IRUSR | stat.S_IWUSR)
      PY
    '';

    # Extract GitHub SSH private key from SOPS into ~/.ssh/github_mikkihugo.
    renderGithubSshKey = lib.hm.dag.entryAfter ["installPackages"] ''
            PATH="${pkgs.sops}/bin:${pkgs.age}/bin:${pythonWithYaml}/bin:$PATH" \
            ${pythonWithYaml}/bin/python3 - <<'PY'
      import subprocess, sys, yaml
      r = subprocess.run(
        ["${pkgs.sops}/bin/sops", "--decrypt",
         "${config.home.homeDirectory}/.dotfiles/secrets/github-ssh.yaml"],
        capture_output=True, text=True)
      if r.returncode != 0:
        print("WARNING: could not decrypt GitHub SSH key from SOPS", file=sys.stderr)
        sys.exit(0)
      key = yaml.safe_load(r.stdout)["github_mikkihugo_private_key"]
      path = "${config.home.homeDirectory}/.ssh/github_mikkihugo"
      import os, stat
      with open(path, "w") as f:
        f.write(key if key.endswith("\n") else key + "\n")
      os.chmod(path, stat.S_IRUSR | stat.S_IWUSR)
      PY
    '';

    # User-level MCP surfaces use the CentralCloud gateway. Repository-scoped
    # templates remain repository-owned and must never be rendered with secrets
    # by Home Manager.
    normalizeGlobalMcpConfigs = lib.hm.dag.entryAfter ["installPackages"] ''
      ${pythonWithYaml}/bin/python3 - <<'PY'
      import json
      from pathlib import Path
      import yaml

      home = Path.home()
      gateway_url = "http://mcp-gateway.svc/mcp"
      generic = {"centralcloud-mcp-gateway": {"url": gateway_url}}
      typed_http = {"centralcloud-mcp-gateway": {"type": "http", "url": gateway_url}}
      opencode = {"centralcloud-mcp-gateway": {"type": "remote", "url": gateway_url}}
      copilot = {
          "centralcloud-mcp-gateway": {
              "type": "http",
              "url": gateway_url,
              "tools": ["*"],
          }
      }
      factory = {
          "centralcloud-mcp-gateway": {
              "type": "http",
              "url": gateway_url,
              "disabled": False,
          }
      }

      specs = [
          (home / ".mcp.json", "mcpServers", generic),
          (home / ".cline" / "mcp.json", "mcpServers", generic),
          (home / ".claude.json", "mcpServers", typed_http),
          (home / ".config" / "amp" / "settings.json", "amp.mcpServers", generic),
          (home / ".config" / "devin" / "config.json", "mcpServers", generic),
          (home / ".gemini" / "settings.json", "mcpServers", generic),
          (home / ".copilot" / "mcp-config.json", "mcpServers", copilot),
          (home / ".cursor" / "mcp.json", "mcpServers", generic),
          (home / ".factory" / "mcp.json", "mcpServers", factory),
          (home / ".junie" / "mcp" / "mcp.json", "mcpServers", generic),
          (home / ".kimi-code" / "mcp.json", "mcpServers", generic),
          (home / ".qoder" / "settings.json", "mcpServers", generic),
          (home / ".config" / "opencode" / "opencode.json", "mcp", opencode),
          (home / ".config" / "crush" / "crush.json", "mcpServers", typed_http),
      ]

      for path, key, value in specs:
          if path.exists():
              try:
                  data = json.loads(path.read_text(encoding="utf-8"))
              except json.JSONDecodeError as exc:
                  print(f"WARNING: {path} is not valid JSON: {exc}", flush=True)
                  continue
              if not isinstance(data, dict):
                  print(f"WARNING: {path} does not contain a JSON object", flush=True)
                  continue
          else:
              data = {}
          data[key] = value
          if path == home / ".qoder" / "settings.json":
              data["mcp"] = {
                  "enabledProjectMcpServers": [],
                  "disabledProjectMcpServers": [],
              }
          path.parent.mkdir(parents=True, exist_ok=True)
          path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")

      goose_path = home / ".config" / "goose" / "config.yaml"
      # Goose streamable_http requires `uri` (not `url`); `url` is skipped as malformed.
      goose_mcp_entry = {
          "name": "centralcloud-mcp-gateway",
          "type": "streamable_http",
          "description": "CentralCloud MCP gateway",
          "uri": gateway_url,
          "enabled": True,
          "timeout": 300,
      }
      # llm-gateway only — force openai; keep ACP/mistral disabled if doctor/configure re-adds them.
      # Kimi K3 is the default; MiniMax-M3 is the planner.
      # Swarm alternative: ollama-deepseek-v4-pro (524K ctx).
      goose_provider_defaults = {
          "openai": {
              "enabled": True,
              "configured": True,
              "model": "kimi-code/k3",
          },
          "claude-acp": {"enabled": False, "configured": False, "model": "current"},
          "codex-acp": {"enabled": False, "configured": False, "model": "current"},
          "mistral": {"enabled": False, "configured": False, "model": "mistral-medium-latest"},
      }
      # Goose must be able to write telemetry consent into this file. Replace any
      # Home Manager store symlink with a mutable YAML merge of durable defaults.
      if goose_path.is_symlink():
          try:
              resolved = goose_path.resolve()
              seeded = yaml.safe_load(resolved.read_text(encoding="utf-8")) if resolved.is_file() else {}
          except Exception as exc:
              print(f"WARNING: could not read goose symlink target: {exc}", flush=True)
              seeded = {}
          goose_path.unlink()
          goose_config = seeded if isinstance(seeded, dict) else {}
      elif goose_path.exists():
          try:
              goose_config = yaml.safe_load(goose_path.read_text(encoding="utf-8"))
          except yaml.YAMLError as exc:
              print(f"WARNING: {goose_path} is not valid YAML: {exc}", flush=True)
              goose_config = None
      else:
          goose_config = {}
      if goose_config is None:
          goose_config = {}
      if not isinstance(goose_config, dict):
          print(f"WARNING: {goose_path} does not contain a YAML object", flush=True)
      else:
          goose_config["active_provider"] = "openai"
          goose_config["OPENAI_HOST"] = "http://llm-gateway.svc"
          goose_config["GOOSE_DISABLE_KEYRING"] = True
          # From llm-gateway /v1/models context_length for umans-glm.
          goose_config["GOOSE_CONTEXT_LIMIT"] = 1048576
          # CLI — Claude Code-like: clean, minimal noise
          goose_config["GOOSE_MODEL"] = "kimi-code/k3"
          goose_config["GOOSE_FAST_MODEL"] = "auto-flash"
          goose_config["GOOSE_PLANNER_PROVIDER"] = "openai"
          goose_config["GOOSE_PLANNER_MODEL"] = "minimax-coding-plan/MiniMax-M3"
          goose_config["GOOSE_PLANNER_CONTEXT_LIMIT"] = 1000000
          goose_config["GOOSE_CLI_THEME"] = "dark"
          goose_config["GOOSE_CLI_MIN_PRIORITY"] = 0.3
          goose_config["GOOSE_DISABLE_TOOL_CALL_SUMMARY"] = True
          goose_config["GOOSE_DISABLE_SESSION_NAMING"] = True
          goose_config["GOOSE_MAX_BACKGROUND_TASKS"] = 10
          goose_config["GOOSE_CLI_SHOW_COST"] = True
          goose_config["GOOSE_MAX_CODE_BLOCK_LINES"] = 100
          goose_config["GOOSE_MODE"] = "auto"
          goose_config["claude-acp_configured"] = False
          goose_config["codex-acp_configured"] = False
          goose_config["mistral_configured"] = False
          providers = goose_config.setdefault("providers", {})
          if not isinstance(providers, dict):
              providers = {}
              goose_config["providers"] = providers
          for name, defaults in goose_provider_defaults.items():
              entry = providers.setdefault(name, {})
              if not isinstance(entry, dict):
                  entry = {}
                  providers[name] = entry
              for key, value in defaults.items():
                  entry[key] = value
          # Disable any other providers doctor/configure may have enabled.
          for name, entry in list(providers.items()):
              if name == "openai" or not isinstance(entry, dict):
                  continue
              entry["enabled"] = False
              entry["configured"] = False
          goose_config.pop("GOOSE_PROVIDER", None)
          goose_config.pop("GOOSE_MODEL", None)
          extensions = goose_config.setdefault("extensions", {})
          if not isinstance(extensions, dict):
              extensions = {}
              goose_config["extensions"] = extensions
          extensions["centralcloud-mcp-gateway"] = goose_mcp_entry
          extensions["summon"] = {
              "name": "summon",
              "type": "platform",
              "description": "Load knowledge and delegate tasks to subagents",
              "enabled": True,
              "bundled": True,
              "display_name": "Summon",
          }
          extensions.pop("orchestrator", None)
          goose_path.parent.mkdir(parents=True, exist_ok=True)
          goose_path.write_text(
              yaml.safe_dump(goose_config, sort_keys=False),
              encoding="utf-8",
          )
          goose_path.chmod(0o600)

          # Seed OPENAI_API_KEY into goose secrets.yaml (keyring unavailable on
          # this host). Source is sops-nix; never commit this file.
          secrets_path = home / ".config" / "goose" / "secrets.yaml"
          token_path = home / ".config" / "sops-nix" / "secrets" / "llm_gateway_api_key"
          edge_token = ""
          if token_path.is_file():
              edge_token = token_path.read_text(encoding="utf-8").strip()
          if edge_token:
              secrets = {}
              if secrets_path.exists() and not secrets_path.is_symlink():
                  try:
                      loaded = yaml.safe_load(secrets_path.read_text(encoding="utf-8"))
                      if isinstance(loaded, dict):
                          secrets = loaded
                  except yaml.YAMLError as exc:
                      print(f"WARNING: {secrets_path} is not valid YAML: {exc}", flush=True)
              secrets["OPENAI_API_KEY"] = edge_token
              secrets_path.write_text(
                  yaml.safe_dump(secrets, sort_keys=False),
                  encoding="utf-8",
              )
              secrets_path.chmod(0o600)
          else:
              print(
                  "WARNING: missing sops llm_gateway_api_key; goose secrets.yaml not seeded",
                  flush=True,
              )

      nanobot_path = home / ".nanobot" / "config.json"
      nanobot_mcp = {
          "centralcloud-mcp-gateway": {
              "type": "streamableHttp",
              "url": gateway_url,
              "tool_timeout": 120,
              "enabled_tools": ["*"],
          }
      }
      if nanobot_path.exists():
          try:
              nanobot_config = json.loads(nanobot_path.read_text(encoding="utf-8"))
          except json.JSONDecodeError as exc:
              print(f"WARNING: {nanobot_path} is not valid JSON: {exc}", flush=True)
          else:
              if isinstance(nanobot_config, dict):
                  nanobot_config.setdefault("tools", {})["mcpServers"] = nanobot_mcp
                  nanobot_path.write_text(
                      json.dumps(nanobot_config, indent=2) + "\n",
                      encoding="utf-8",
                  )
              else:
                  print(f"WARNING: {nanobot_path} does not contain a JSON object", flush=True)

      # vtcode — pin openai → llm-gateway.svc and MCP → mcp-gateway.svc
      # via surgical edits (do not round-trip the large ~/.vtcode/vtcode.toml).
      import re

      def _normalize_vtcode_toml(path: Path) -> None:
          if not path.exists():
              return
          try:
              text = path.read_text(encoding="utf-8")
          except OSError as exc:
              print(f"WARNING: could not read {path}: {exc}", flush=True)
              return

          def set_agent_field(src: str, key: str, value: str) -> str:
              pattern = rf"(?m)^(\[agent\](?:(?!\n\[).)*?^{key}\s*=\s*)([^\n]+)"
              if re.search(pattern, src, flags=re.S):
                  return re.sub(pattern, rf'\g<1>"{value}"', src, count=1, flags=re.S)
              # Insert after [agent] if missing.
              return re.sub(
                  r"(?m)^(\[agent\]\s*\n)",
                  rf'\g<1>{key} = "{value}"\n',
                  src,
                  count=1,
              )

          text = set_agent_field(text, "provider", "openai")
          text = set_agent_field(text, "api_key_env", "OPENAI_API_KEY")
          text = set_agent_field(text, "default_model", "auto-glm")
          text = re.sub(
              r"(?m)^custom_providers\s*=\s*\[[^\]]*\]",
              "custom_providers = []",
              text,
              count=1,
          )
          # Enable MCP block.
          if re.search(r"(?m)^\[mcp\]", text):
              text = re.sub(
                  r"(?m)^(\[mcp\](?:(?!\n\[).)*?^enabled\s*=\s*)(true|false)",
                  r"\g<1>true",
                  text,
                  count=1,
                  flags=re.S,
              )
          else:
              text += "\n[mcp]\nenabled = true\n"

          provider_block = (
              "\n[[mcp.providers]]\n"
              'name = "centralcloud-mcp-gateway"\n'
              f'endpoint = "{gateway_url}"\n'
              'protocol_version = "2024-11-05"\n'
              "enabled = true\n"
              "max_concurrent_requests = 3\n"
          )
          if 'name = "centralcloud-mcp-gateway"' in text:
              # Rewrite endpoint on the centralcloud provider only.
              text = re.sub(
                  r'(?ms)(\[\[mcp\.providers\]\]\s*\nname\s*=\s*"centralcloud-mcp-gateway"\s*\n(?:(?!\[\[).)*?^endpoint\s*=\s*)"[^"]*"',
                  rf'\g<1>"{gateway_url}"',
                  text,
                  count=1,
              )
          else:
              text += provider_block

          path.write_text(text, encoding="utf-8")
          print(f"vtcode: normalized provider+mcp in {path}", flush=True)

      for vtcode_cfg in (
          home / ".vtcode" / "vtcode.toml",
          home / ".config" / "vtcode" / "vtcode.toml",
      ):
          _normalize_vtcode_toml(vtcode_cfg)
      PY
    '';

    # @opencode-ai/sdk — TypeScript SDK for OpenCode API (programmatic access to
    # both OpenAI-compatible /v1/chat/completions and Anthropic /v1/messages endpoints).
    # Installed via npm global so it is available to ad-hoc Node scripts.
    installOpencodeSdk = lib.hm.dag.entryAfter ["writeBoundary"] ''
      echo "Updating @opencode-ai/sdk..."
      export NPM_CONFIG_PREFIX="$HOME/.npm-global"
      PATH="${USER_TOOL_PATH}:$PATH" \
      ${pkgs.nodejs}/bin/npm install -g @opencode-ai/sdk@latest && \
        echo "@opencode-ai/sdk ready — import via: const { OpencodeClient } = require('@opencode-ai/sdk')" || \
        echo "WARNING: @opencode-ai/sdk install failed" >&2
    '';
  };
}
