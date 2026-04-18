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
in {
  home.activation = {
    # programs.gh and programs.jujutsu own these files as nix-store symlinks.
    # If they exist as plain files (written by `gh auth` or `jj init`) home-manager
    # aborts with "would be clobbered". Remove them before checkLinkTargets.
    removeConflictingConfigs = lib.hm.dag.entryBefore ["checkLinkTargets"] ''
      rm -f "$HOME/.config/gh/config.yml"
      rm -f "$HOME/.config/jj/config.toml"
      rm -f "$HOME/.config/systemd/user/openclaw-node.service"
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

    # openclaw is an npm package not in nixpkgs — always update to latest on hms.
    # After first install run `openclaw-setup` to register this machine as a node.
    installOpenclaw = lib.hm.dag.entryAfter ["writeBoundary"] ''
      echo "Updating openclaw to latest..."
      PATH="${pkgs.git}/bin:${pkgs.nodejs_24}/bin:$PATH" \
      ${pkgs.nodejs_24}/bin/npm install -g \
        --prefix "$HOME/.npm-global" \
        --no-fund --no-audit \
        openclaw@latest && \
        echo "openclaw updated — run: openclaw-setup if first time" || \
        echo "WARNING: openclaw update failed" >&2
    '';

    # Extract pre-built secret-tui binary from the git-tracked gzip on every hms.
    # Falls back to building from source if no pre-built binary exists for this arch.
    extractRustBinaries = let
      arch = builtins.elemAt (builtins.split "-" pkgs.stdenv.hostPlatform.system) 0;
      gzPath = ../../tools/secret-tui-rust/bin/${arch}/secret-tui.gz;
      hasGz = builtins.pathExists gzPath;
    in
      lib.hm.dag.entryAfter ["writeBoundary"] ''
        mkdir -p "$HOME/.local/bin"
        ${
          if hasGz
          then ''
            ${pkgs.gzip}/bin/gzip -dc ${gzPath} > "$HOME/.local/bin/secret-tui.tmp"
            chmod +x "$HOME/.local/bin/secret-tui.tmp"
            mv "$HOME/.local/bin/secret-tui.tmp" "$HOME/.local/bin/secret-tui"
          ''
          else ''
            if [ ! -f "$HOME/.local/bin/secret-tui" ]; then
              echo "No pre-built secret-tui for ${arch}, building from source..."
              SRCDIR="$HOME/.dotfiles/tools/secret-tui-rust"
              if [ -f "$SRCDIR/Cargo.toml" ]; then
                (
                  cd "$SRCDIR" && \
                  export CC="${pkgs.stdenv.cc}/bin/cc" && \
                  export CXX="${pkgs.stdenv.cc}/bin/c++" && \
                  export RUSTC_LINKER="${pkgs.stdenv.cc}/bin/cc" && \
                  export CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="${pkgs.stdenv.cc}/bin/cc" && \
                  export HOST_CC="${pkgs.stdenv.cc}/bin/cc" && \
                  export TARGET_CC="${pkgs.stdenv.cc}/bin/cc" && \
                  export OPENSSL_DIR="${pkgs.openssl.dev}" && \
                  export OPENSSL_INCLUDE_DIR="${pkgs.openssl.dev}/include" && \
                  export OPENSSL_LIB_DIR="${pkgs.openssl.out}/lib" && \
                  export PKG_CONFIG="${pkgs.pkg-config}/bin/pkg-config" && \
                  export PATH="${pkgs.stdenv.cc}/bin:${pkgs.pkg-config}/bin:${pkgs.cargo}/bin:$PATH" && \
                  ${pkgs.cargo}/bin/cargo build --release 2>&1
                ) && \
                cp "$SRCDIR/target/release/secret-tui" "$HOME/.local/bin/secret-tui" && \
                echo "Built and installed secret-tui"
              else
                echo "secret-tui: no binary for ${arch} and no source found"
              fi
            fi
          ''
        }
      '';
  };
}
