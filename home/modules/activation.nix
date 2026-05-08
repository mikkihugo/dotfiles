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

    # programs.gh and programs.jujutsu own these files as nix-store symlinks.
    # If they exist as plain files (written by `gh auth` or `jj init`) home-manager
    # aborts with "would be clobbered". Remove them before checkLinkTargets.
    removeConflictingConfigs = lib.hm.dag.entryBefore ["checkLinkTargets"] ''
      rm -f "$HOME/.config/gh/config.yml"
      rm -f "$HOME/.config/jj/config.toml"

      rm -f "$HOME/.config/systemd/user/dr-repo-maintenance.service"
      rm -f "$HOME/.config/systemd/user/dr-repo-maintenance.timer"
      rm -f "$HOME/.config/systemd/user/timers.target.wants/dr-repo-maintenance.timer"
      rm -f "$HOME/.config/systemd/user/remote-gpu-worker.service.d/combined.conf"
      rm -f "$HOME/.config/systemd/user/remote-gpu-worker.service.d/no-watchdog.conf"
      rm -f "$HOME/.local/bin/claude"
      rm -f "$HOME/.npm-global/bin/claude"
      rm -f "$HOME/.npm-global/bin/gemini"
      rmdir "$HOME/.config/systemd/user/remote-gpu-worker.service.d" 2>/dev/null || true
    '';

    seedMutableCodexConfig = lib.hm.dag.entryAfter ["writeBoundary"] ''
      mkdir -p "$HOME/.codex"
      if [ -L "$HOME/.codex/config.toml" ] || [ ! -e "$HOME/.codex/config.toml" ]; then
        rm -f "$HOME/.codex/config.toml"
        cp "${config.home.homeDirectory}/.dotfiles/config/codex/config.toml" "$HOME/.codex/config.toml"
        chmod 600 "$HOME/.codex/config.toml"
      fi
    '';

    applySharedCodexPreferences = lib.hm.dag.entryAfter ["seedMutableCodexConfig"] ''
      if [ -f "$HOME/.dotfiles/config/codex/shared-preferences.toml" ]; then
        ${pkgs.python3}/bin/python3 "$HOME/.dotfiles/scripts/codex-preferences" apply
        chmod 600 "$HOME/.codex/config.toml"
      fi
    '';

    pushHomeManagerGenerationToCache = lib.hm.dag.entryAfter ["linkGeneration"] ''
      if [ -f "$HOME/.config/attic/config.toml" ]; then
        mkdir -p "$HOME/.cache/attic"
        (
          ${pkgs.util-linux}/bin/flock -n 9 || exit 0
          for attempt in 1 2 3; do
            ${pkgs.attic-client}/bin/attic push centralcloud:default "$newGenPath" && exit 0
            status=$?
            echo "attic push attempt $attempt failed with exit $status" >&2
            [ "$attempt" -lt 3 ] || exit "$status"
            sleep "$((attempt * 30))"
          done
        ) 9>"$HOME/.cache/attic/home-manager-push.lock" \
          >"$HOME/.cache/attic/home-manager-push.log" 2>&1 &
        echo "Started background push of Home Manager generation to centralcloud:default"
        echo "Log: $HOME/.cache/attic/home-manager-push.log"
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

    # Render MCP client configs (~/.gemini/settings.json, .mcp.json, .cursor/mcp.json)
    # from SOPS-backed secrets so Gemini/Claude/Cursor always have the current ACE
    # MCP token without a manual `install_or_repair_mcp_clients.sh`.
    renderMcpConfigs = lib.hm.dag.entryAfter ["installPackages"] ''
      ACE_REPO="$HOME/code/ace-coder"
      if [ -f "$ACE_REPO/scripts/render_repo_mcp_configs.sh" ]; then
        PATH="${pkgs.sops}/bin:${pkgs.age}/bin:${pkgs.python3}/bin:$PATH" \
        bash "$ACE_REPO/scripts/render_repo_mcp_configs.sh" || \
          echo "WARNING: render_repo_mcp_configs.sh failed (MCP configs may be stale)" >&2
      fi
    '';

    # toad (batrachian.ai) is not in nixpkgs — keep it up to date on every hms.
    # Requires Python 3.14+; uv fetches the right interpreter automatically.
    # uv tool install -U is idempotent: no-op when already at latest.
    installToad = lib.hm.dag.entryAfter ["writeBoundary"] ''
      echo "Updating toad..."
      PATH="${USER_TOOL_PATH}:$PATH" \
      ${pkgs.uv}/bin/uv tool install -U batrachian-toad --python 3.14 && \
        echo "toad ready — run: toad" || \
        echo "WARNING: toad install failed" >&2
    '';

    installOpenhands = lib.hm.dag.entryAfter ["writeBoundary"] ''
      echo "Updating openhands..."
      PATH="${USER_TOOL_PATH}:$PATH" \
      ${pkgs.uv}/bin/uv tool install openhands -U --python 3.12 && \
        echo "openhands ready — run: openhands login" || \
        echo "WARNING: openhands install failed" >&2
    '';

    installCrowCli = lib.hm.dag.entryAfter ["writeBoundary"] ''
      echo "Updating crow-cli..."
      PATH="${USER_TOOL_PATH}:$PATH" \
      ${pkgs.uv}/bin/uv tool install -U crow-cli --python 3.14 && \
        echo "crow-cli ready — run: crow-cli" || \
        echo "WARNING: crow-cli install failed" >&2
    '';

    # kimi-cli (Moonshot) is not in nixpkgs — keep it up to date on every hms.
    installKimiCli = lib.hm.dag.entryAfter ["writeBoundary"] ''
      echo "Updating kimi-cli..."
      PATH="${USER_TOOL_PATH}:$PATH" \
      ${pkgs.uv}/bin/uv tool install -U kimi-cli && \
        echo "kimi-cli ready — run: kimi" || \
        echo "WARNING: kimi-cli install failed" >&2
    '';
  };
}
