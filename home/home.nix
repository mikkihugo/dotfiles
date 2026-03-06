# home/home.nix — declarative user environment
#
# Purpose:
#   Single source of truth for everything installed and configured in $HOME.
#   Applied by `home-manager switch --flake .#mhugo --impure` (alias: `hms`).
#
#   Why home-manager instead of dotfile symlinks?
#   - Atomic: either the whole generation activates or nothing changes.
#   - Reproducible: same flake.lock = identical environment on any machine.
#   - No drift: editing files in $HOME directly gets overwritten on next switch.
#
#   dotfilesRoot is passed into shell init blocks so they can source runtime
#   files (like shell/bash/bashrc) that need the live shell environment.
{
  pkgs,
  lib,
  ...
}: let
  dotfilesRoot = "$HOME/.dotfiles";
in {
  imports = [
    ../services/ace-embedding-worker
  ];

  services.ace-embedding-worker = {
    enable = true;
    codeModel = "jina-code-embeddings-1.5b-Q8_0.gguf";
  };
  home = {
    # ── Pre-built Rust binaries ──────────────────────────────────────────
    # Extracted from git-tracked gzips on every `hms` activation.
    activation.extractRustBinaries = let
      arch = builtins.elemAt (builtins.split "-" pkgs.stdenv.hostPlatform.system) 0;
      secretTuiSrc = ../tools/secret-tui-rust;
      # Use tryEval to handle missing arch binary gracefully
      gzPath = ../tools/secret-tui-rust/bin/${arch}/secret-tui.gz;
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
                (cd "$SRCDIR" && ${pkgs.cargo}/bin/cargo build --release 2>&1) && \
                cp "$SRCDIR/target/release/secret-tui" "$HOME/.local/bin/secret-tui" && \
                echo "Built and installed secret-tui"
              else
                echo "secret-tui: no binary for ${arch} and no source found"
              fi
            fi
          ''
        }
      '';
    username = "mhugo";
    homeDirectory = "/home/mhugo";

    # stateVersion pins the home-manager release that manages migration.
    # Do NOT change this after first activation — it controls format upgrades,
    # not the software versions (those come from nixpkgs).
    stateVersion = "24.11";

    # ── Session variables ──────────────────────────────────────────────────
    # Exported into every session before any shell init runs.
    # SOPS_AGE_KEY_FILE tells sops where to find the age private key used to
    # decrypt secrets/api-keys.yaml. Derived from SSH key via ssh-to-age.
    # ── PATH ──────────────────────────────────────────────────────────────
    # ~/.local/bin: pip/pipx installs, claude CLI, and other user tools.
    # ~/.npm-global/bin: global npm packages (opencode, etc.)
    # ~/.cargo/bin: cargo-installed Rust binaries.
    sessionPath = [
      "$HOME/.local/bin"
      "$HOME/.npm-global/bin"
      "$HOME/.cargo/bin"
    ];

    sessionVariables = {
      NPM_CONFIG_PREFIX = "$HOME/.npm-global";
      SOPS_AGE_KEY_FILE = "$HOME/.config/sops/age/keys.txt";
      # Point ripgrep at its config file so smart-case, colors, and glob
      # ignores apply automatically without passing flags every time.
      RIPGREP_CONFIG_PATH = "$HOME/.config/ripgrep/config";
      # bat picks up its config from BAT_CONFIG_PATH (Nord theme, line numbers).
      BAT_CONFIG_PATH = "$HOME/.config/bat/config";
    };

    # ── Config file links ──────────────────────────────────────────────────
    # Files that tools expect at specific paths under $HOME, managed here so
    # they stay in version control and update atomically with hms.
    file = {
      ".config/ripgrep/config".source = ../config/ripgreprc;
      ".config/bat/config".source = ../config/bat/config;
      # VSCode settings — terminal font (Nerd Font), shell (zsh), editor defaults.
      # NOTE: Nerd Font must be installed on the Windows side for WSL2 VSCode.
      #   winget install -e --id DEVCOM.JetBrainsMonoNerdFont
      ".config/Code/User/settings.json" = {
        source = ../config/vscode/settings.json;
        force = true;
      };
      # Codex CLI config — models, features, project trust, MCP servers.
      # force=true overwrites on every `hms`; manage MCP servers here, not via `codex mcp add`.
      ".codex/config.toml" = {
        source = ../config/codex/config.toml;
        force = true;
      };
    };

    # ── Packages ───────────────────────────────────────────────────────────
    # Installed into the user profile (available on PATH without a shell hook).
    # Grouped by role so it's clear what each block is for and what to remove
    # if a machine doesn't need it.
    packages = with pkgs; [
      # Modern CLI replacements — faster, friendlier alternatives to coreutils.
      # Aliases (ls, ll, lt, cat, grep, find) are declared in home.shellAliases below.
      eza # ls replacement (tree view, git status, icons)
      bat # cat replacement (syntax highlight, paging)
      fd # find replacement (respects .gitignore, faster)
      ripgrep # grep replacement (recursive, fast, .gitignore-aware)
      fzf # fuzzy finder (piped into other tools or used standalone)
      zoxide # smarter cd (frecency-based, `z` alias)
      delta # git diff pager (side-by-side, syntax highlight)
      jq # JSON query and transform
      yq # YAML/TOML/XML query (jq-compatible syntax)
      btop # process/resource monitor (replaces htop)
      tokei # count lines of code by language
      difftastic # structural diff (understands syntax, not just lines)

      # Dev tools — language runtimes and package managers.
      # Node/pnpm here because some CLI tools (opencode, etc.) need them
      # without project-level nix shells.
      git-lfs # large file storage extension for git
      nodejs_22 # Node.js LTS
      pnpm # fast, disk-efficient Node package manager

      # Secret management — the SOPS/age toolchain for encrypting dotfile secrets.
      # These are also in the devShell but listed here so they're always available
      # without entering `nix develop`.
      sops # encrypts/decrypts YAML/JSON secrets
      age # encryption backend (replaces GPG for SOPS)
      ssh-to-age # derives age pubkey from SSH ed25519 key

      # Shell tooling — linters used by lefthook pre-commit hooks.
      shellcheck # static analysis for shell scripts
      shfmt # formatter for shell scripts

      # Nix tooling — meta-tools for working with the Nix ecosystem.
      alejandra # opinionated Nix formatter (used in pre-commit)
      statix # Nix linter — catches anti-patterns (used in pre-commit)
      deadnix # finds unused Nix expressions (dead code)
      nix-tree # visualise the derivation dependency tree
      nvd # diff between home-manager / NixOS generations
      nix-output-monitor # prettier `nix build` output
      nix-index # `nix-locate`: find which package provides a binary

      # Terminal multiplexer — persistent sessions, split panes.
      zellij

      # bat-extras — bat-powered wrappers for standard tools
      bat-extras.batman # man pages with syntax highlighting
      bat-extras.batgrep # ripgrep output through bat
      bat-extras.batdiff # diff output through bat

      # Nerd Fonts — required for starship icons, eza glyphs, git symbols.
      # Installed on the Linux/WSL side for native terminal emulators.
      # VSCode Remote (Windows) also needs the font on the Windows side:
      #   winget install -e --id DEVCOM.JetBrainsMonoNerdFont
      nerd-fonts.jetbrains-mono

      # Clipboard — Wayland clipboard integration.
      # Used by secret-tui's `c` key (copy secret to clipboard).
      wl-clipboard

      # Pre-commit / code quality — run by lefthook on every commit.
      lefthook # git hook runner (runs alejandra, statix, shellcheck, etc.)
      typos # spell checker for source files
      detect-secrets # scans for accidentally committed credentials
    ];

    # ── Shell aliases ──────────────────────────────────────────────────────
    # Declared here rather than in a sourced aliases.sh so they appear in
    # both bash and zsh without duplicating logic.
    shellAliases = {
      # home-manager shorthand — `hms` applies the current flake config.
      # --impure is required because home.nix reads builtins.currentSystem.
      hms = "home-manager switch --flake ~/.dotfiles#mhugo --impure --extra-experimental-features 'nix-command flakes'";

      # secret-tui — browse, reveal, and edit SOPS-encrypted secrets
      secrets = "secret-tui";

      # ls replacements — eza is flag-compatible enough for interactive use.
      # NOT aliasing grep→rg or find→fd: those tools have different argument
      # syntax; overriding them breaks scripts and unexpected muscle memory.
      # Use rg/fd directly by name.
      ls = "eza --group-directories-first";
      ll = "eza -la --group-directories-first --git";
      lt = "eza --tree --level=2 --group-directories-first";
      la = "eza -la --group-directories-first --git --all";

      # batman — man pages rendered with bat (syntax-highlighted, paginated)
      man = "batman";
    };
  };

  programs = {
    # Let home-manager manage its own config file (~/.config/home-manager/).
    home-manager.enable = true;

    # ── Bash ────────────────────────────────────────────────────────────────
    # Purpose: set DOTFILES_ROOT so shell/bash/bashrc can locate secrets,
    # then source bashrc to register the `load-ai-keys` alias.
    # direnv, starship, and zoxide hooks are injected automatically by their
    # programs.* blocks below — no need to eval them here.
    bash = {
      enable = true;
      initExtra = ''
        export DOTFILES_ROOT="${dotfilesRoot}"
        export HM_MANAGED=1

        # Load on-demand LLM key helper (load-ai-keys alias).
        # Sourced here instead of declared inline so the function body lives
        # in a versioned file (shell/bash/bashrc) not in a generated ~/.bashrc.
        [ -f "$DOTFILES_ROOT/shell/bash/bashrc" ] && source "$DOTFILES_ROOT/shell/bash/bashrc"
      '';
    };

    # ── Zsh ─────────────────────────────────────────────────────────────────
    # Sources the same bashrc — the load-ai-keys function uses only POSIX sh
    # syntax so it works in both bash and zsh.
    zsh = {
      enable = true;
      initContent = ''
        export DOTFILES_ROOT="${dotfilesRoot}"
        export HM_MANAGED=1

        [ -f "$DOTFILES_ROOT/shell/bash/bashrc" ] && source "$DOTFILES_ROOT/shell/bash/bashrc"
      '';
    };

    # ── Git ──────────────────────────────────────────────────────────────────
    # Purpose: canonical identity + delta pager + quality-of-life aliases.
    # delta replaces the default diff output with syntax-highlighted, side-by-
    # side views. navigate=true lets you jump between hunks with n/N in less.
    git = {
      enable = true;
      settings = {
        user = {
          name = "Mikael Hugo";
          email = "mikkihugo@users.noreply.github.com";
        };
        # /home/mhugo/code/flakecache is owned by root (nix build cache);
        # mark it safe so `git status` works inside it without sudo.
        safe.directory = "/home/mhugo/code/flakecache";
        init.defaultBranch = "main";
        pull.rebase = true;
        core.pager = "delta";
        interactive.diffFilter = "delta --color-only";
        delta = {
          navigate = true;
          light = false;
          syntax-theme = "Nord";
          line-numbers = true;
          side-by-side = false; # single-column is easier on narrow terminals
        };
        merge.conflictstyle = "diff3"; # shows base in conflicts — clearer resolution
        diff.colorMoved = "default";
        alias = {
          s = "status -sb";
          a = "add";
          c = "commit";
          co = "checkout";
          b = "branch";
          p = "push";
          pl = "pull --rebase";
          f = "fetch --all --prune";
          lg = "log --oneline --graph --decorate";
          ll = "log --graph --pretty=format:'%C(yellow)%h%Creset -%C(auto)%d%Creset %s %C(green)(%cr) %C(bold blue)<%an>%Creset'";
          d = "diff";
          dc = "diff --cached";
          ds = "diff --stat";
          sl = "stash list";
          sa = "stash apply";
          sp = "stash pop";
          undo = "reset --soft HEAD~1";
          pushit = "!git push -u origin $(git branch --show-current)";
          rebase-main = "!git rebase -i $(git merge-base HEAD main)";
        };
      };
    };

    # ── Jujutsu ──────────────────────────────────────────────────────────────
    # Purpose: jj is the primary VCS for the ace-coder project (git backend).
    # difft as diff tool gives structural diffs instead of line-by-line noise.
    jujutsu = {
      enable = true;
      settings = {
        user = {
          name = "Mikael Hugo";
          email = "mikkihugo@users.noreply.github.com";
        };
        ui = {
          pager = "less -FRX";
          default-command = "log"; # `jj` alone shows the commit graph
          diff-formatter = "difft";
        };
      };
    };

    # ── Direnv ───────────────────────────────────────────────────────────────
    # Purpose: automatically load the nix shell when cd-ing into a project.
    # nix-direnv caches the nix evaluation so `cd` is instant after the first
    # load — without it, every `cd` into a flake project takes 2-5 seconds.
    direnv = {
      enable = true;
      nix-direnv.enable = true;
    };

    # ── Starship prompt ───────────────────────────────────────────────────────
    # Purpose: informative, fast cross-shell prompt.
    # configPath points at the versioned TOML file rather than inlining the
    # config as Nix attrs — this avoids Nix escaping issues with starship's
    # format strings and keeps the config readable as TOML.
    starship = {
      enable = true;
      configPath = toString ../config/starship.toml;
    };

    # ── Zoxide ───────────────────────────────────────────────────────────────
    # Purpose: replace `cd` with frecency-based directory jumping.
    # `z foo` jumps to the most-visited directory matching "foo".
    # Both integrations are enabled so it works identically in bash and zsh.
    zoxide = {
      enable = true;
      enableBashIntegration = true;
      enableZshIntegration = true;
    };

    # ── GitHub CLI ───────────────────────────────────────────────────────────
    # Purpose: gh is used for PR review and repo management.
    # ssh protocol avoids HTTPS credential prompts; `gh pr checkout` is aliased
    # to `co` so checking out a PR by number is quick.
    gh = {
      enable = true;
      settings = {
        git_protocol = "ssh";
        prompt = "enabled";
        aliases = {
          co = "pr checkout";
        };
      };
    };
  };
}
