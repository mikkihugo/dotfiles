{pkgs, ...}: let
  dotfilesRoot = "$HOME/.dotfiles";
in {
  home = {
    username = "mhugo";
    homeDirectory = "/home/mhugo";
    stateVersion = "24.11";

    # ── Session variables ────────────────────────────────────────────────────
    sessionVariables = {
      SOPS_AGE_KEY_FILE = "$HOME/.config/sops/age/keys.txt";
    };

    # ── Packages ─────────────────────────────────────────────────────────────
    packages = with pkgs; [
      # Modern CLI replacements
      eza
      bat
      fd
      ripgrep
      fzf
      zoxide
      delta
      jq
      yq
      btop
      tokei
      difftastic

      # Dev tools
      git-lfs
      nodejs_22
      pnpm

      # Secret management
      sops
      age
      ssh-to-age

      # Shell
      shellcheck
      shfmt

      # Nix tooling
      alejandra # Nix formatter
      statix # Nix linter (anti-patterns)
      deadnix # Nix dead code finder
      nix-tree # Visualize derivation dependency tree
      nvd # Diff between home-manager/NixOS generations
      nix-output-monitor # Nicer nix build output
      nix-index # nix-locate: find which package provides a binary

      # Terminal multiplexer
      zellij

      # Clipboard (Wayland)
      wl-clipboard

      # Pre-commit / code quality
      lefthook # Git hook runner (needed globally for any repo using it)
      typos # Spell checker
      detect-secrets # Secret scanner
    ];
  };

  programs = {
    # Let home-manager manage itself
    home-manager.enable = true;

    # ── Bash ─────────────────────────────────────────────────────────────────
    bash = {
      enable = true;
      initExtra = ''
        export DOTFILES_ROOT="${dotfilesRoot}"
        export HM_MANAGED=1

        # Load on-demand LLM key helper (load-ai-keys alias)
        [ -f "$DOTFILES_ROOT/shell/bash/bashrc" ] && source "$DOTFILES_ROOT/shell/bash/bashrc"
      '';
    };

    # ── Zsh ──────────────────────────────────────────────────────────────────
    zsh = {
      enable = true;
      initContent = ''
        export DOTFILES_ROOT="${dotfilesRoot}"
        export HM_MANAGED=1

        # Load on-demand LLM key helper (load-ai-keys alias)
        [ -f "$DOTFILES_ROOT/shell/bash/bashrc" ] && source "$DOTFILES_ROOT/shell/bash/bashrc"
      '';
    };

    # ── Git ───────────────────────────────────────────────────────────────────
    git = {
      enable = true;
      settings = {
        user = {
          name = "Mikael Hugo";
          email = "mikkihugo@users.noreply.github.com";
        };
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
          side-by-side = false;
        };
        merge.conflictstyle = "diff3";
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
    jujutsu = {
      enable = true;
      settings = {
        user = {
          name = "Mikael Hugo";
          email = "mikkihugo@users.noreply.github.com";
        };
        ui = {
          pager = "less -FRX";
          default-command = "log";
          diff.tool = "difft";
        };
      };
    };

    # ── Direnv ───────────────────────────────────────────────────────────────
    direnv = {
      enable = true;
      nix-direnv.enable = true;
    };

    # ── Starship prompt ───────────────────────────────────────────────────────
    starship = {
      enable = true;
      configPath = toString ../config/starship.toml;
    };

    # ── Zoxide (better cd) ───────────────────────────────────────────────────
    zoxide = {
      enable = true;
      enableBashIntegration = true;
      enableZshIntegration = true;
    };

    # ── GitHub CLI ───────────────────────────────────────────────────────────
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
