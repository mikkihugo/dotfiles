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
}: {
  home.activation = {
    # programs.gh and programs.jujutsu own these files as nix-store symlinks.
    # If they exist as plain files (written by `gh auth` or `jj init`) home-manager
    # aborts with "would be clobbered". Remove them before checkLinkTargets.
    removeConflictingConfigs = lib.hm.dag.entryBefore ["checkLinkTargets"] ''
      rm -f "$HOME/.config/gh/config.yml"
      rm -f "$HOME/.config/jj/config.toml"
    '';

    # Render MCP client configs (~/.gemini/settings.json, .mcp.json, .cursor/mcp.json)
    # from SOPS-backed secrets so Gemini/Claude/Cursor always have the current ACE
    # MCP token without a manual `install_or_repair_mcp_clients.sh`.
    renderMcpConfigs = lib.hm.dag.entryAfter ["installPackages"] ''
      ACE_REPO="$HOME/code/ace-coder"
      if [ -f "$ACE_REPO/scripts/render_repo_mcp_configs.sh" ]; then
        bash "$ACE_REPO/scripts/render_repo_mcp_configs.sh" || \
          echo "WARNING: render_repo_mcp_configs.sh failed (MCP configs may be stale)" >&2
      fi
    '';

    # openclaw is an npm package not in nixpkgs — install once via npm using
    # Nix-managed Node.js. Skips if already present so re-runs are fast.
    # After first install run `openclaw-setup` to register this machine as a node.
    installOpenclaw = lib.hm.dag.entryAfter ["writeBoundary"] ''
      if ! command -v openclaw >/dev/null 2>&1; then
        echo "Installing openclaw via npm..."
        PATH="${pkgs.git}/bin:${pkgs.nodejs_24}/bin:$PATH" \
        ${pkgs.nodejs_24}/bin/npm install -g \
          --prefix "$HOME/.npm-global" \
          --no-fund --no-audit \
          openclaw@latest && \
          echo "openclaw installed — run: openclaw-setup" || \
          echo "WARNING: openclaw install failed" >&2
      fi
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
