# home/modules/files.nix — home.file symlinks
#
# Files that tools expect at specific $HOME paths, kept in version control
# and updated atomically on every `hms`. force=true overwrites any manually
# edited copy so the repo stays the source of truth.
{lib, ...}: {
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

    # Nix user config: remote builder (llm-gateway) + substituter (nix-serve).
    # Enables `hms` to substitute CUDA worker derivations from cache instead
    # of recompiling locally.
    ".config/nix/nix.conf" = {
      source = ../../config/nix/nix.conf;
      force = true;
    };

    # ace-coder repo lefthook config — Nix owns this so `hms` repairs the
    # symlink automatically after nix-collect-garbage breaks it.
    "code/ace-coder/lefthook.yml" = {
      force = true;
      text = ''
        pre-commit:
          parallel: true
          commands:
            nix-format:
              glob: "*.nix"
              run: alejandra --check {staged_files}

            nix-lint:
              glob: "*.nix"
              run: statix check --config statix.toml {staged_files}

            shellcheck:
              glob: "*.sh"
              run: shellcheck --external-sources {staged_files}

            shfmt:
              glob: "*.sh"
              run: shfmt -d {staged_files}

            typos:
              exclude: '\.(gz|bin|wasm|lock|pyc)$|^secrets/'
              run: typos --force-exclude {staged_files}

        pre-push:
          commands:
            quality:
              run: make quality
      '';
    };
  };
}
