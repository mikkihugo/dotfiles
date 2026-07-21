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
      goose_defaults = {
          "GOOSE_PROVIDER": "openai",
          "GOOSE_MODEL": "auto",
          "claude-acp_configured": True,
          "codex-acp_configured": True,
      }
      goose_mcp = {
          "centralcloud-mcp-gateway": {
              "name": "centralcloud-mcp-gateway",
              "type": "streamable_http",
              "url": gateway_url,
              "enabled": True,
              "timeout": 300,
          }
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
          for key, value in goose_defaults.items():
              goose_config.setdefault(key, value)
          goose_config["extensions"] = goose_mcp
          goose_path.parent.mkdir(parents=True, exist_ok=True)
          goose_path.write_text(
              yaml.safe_dump(goose_config, sort_keys=False),
              encoding="utf-8",
          )
          goose_path.chmod(0o600)

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
