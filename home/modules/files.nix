# home/modules/files.nix — home.file symlinks
#
# Files that tools expect at specific $HOME paths, kept in version control
# and updated atomically on every `hms`. force=true overwrites any manually
# edited copy so the repo stays the source of truth.
{_}: {
  home.file = {
    ".config/ripgrep/config" = {
      source = ../../config/ripgreprc;
      force = true;
    };

    ".config/bat/config".source = ../../config/bat/config;

    # VSCode: terminal font (Nerd Font), shell (zsh), editor defaults.
    # WSL2: also install the font on the Windows side for VSCode Remote:
    #   winget install -e --id DEVCOM.JetBrainsMonoNerdFont
    ".config/Code/User/settings.json" = {
      source = ../../config/vscode/settings.json;
      force = true;
    };

    # Codex CLI: models, features, project trust, MCP servers.
    # Manage MCP servers here — not via `codex mcp add` which writes locally.
    ".codex/config.toml" = {
      source = ../../config/codex/config.toml;
      force = true;
    };
    ".codex/rules/default.rules" = {
      source = ../../config/codex/default.rules;
      force = true;
    };

    # Nix user config: remote builder (llm-gateway) + substituter (nix-serve).
    # Enables `hms` to substitute CUDA worker derivations from cache instead
    # of recompiling locally.
    ".config/nix/nix.conf" = {
      source = ../../config/nix/nix.conf;
      force = true;
    };
  };
}
