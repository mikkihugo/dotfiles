# home/modules/files.nix — home.file symlinks
#
# Files that tools expect at specific $HOME paths, kept in version control
# and updated atomically on every `hms`. force=true overwrites any manually
# edited copy so the repo stays the source of truth.
{
  lib,
  hostname ? "",
  ...
}: let
  lowercaseHostname = lib.toLower hostname;
  # mikki-bunker delegates worker builds to llm-gateway (remote builder) —
  # llama-cpp + candle deps take ~20 min to compile locally. mikki-laptop
  # stays on local-build (no SSH path to llm-gateway from there).
  usesLocalBuildNixConfig = lowercaseHostname == "mikki-laptop";
  nixConfigSource =
    if usesLocalBuildNixConfig
    then ../../config/nix/local-build.nix.conf
    else ../../config/nix/remote-builder.nix.conf;
in {
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

    # SSH client config: host aliases for all servers (mail.hugo.dk, aidev, llm-gateway).
    # hetzner_id_ed25519 is rendered from SOPS by the renderHetznerSshKey activation hook.
    ".ssh/config" = {
      source = ../../config/ssh_config;
      force = true;
    };

    # Nix user config is host-specific:
    # bunker/laptop build locally; the main Linux workstation can use llm-gateway.
    ".config/nix/nix.conf" = {
      source = nixConfigSource;
      force = true;
    };
  };
}
