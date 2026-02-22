{ pkgs, ... }:

let
  dotfilesRoot = "$HOME/.dotfiles";
in
{
  home.username = "mhugo";
  home.homeDirectory = "/home/mhugo";
  home.stateVersion = "24.11";

  # Let home-manager manage itself
  programs.home-manager.enable = true;

  # ── Packages ─────────────────────────────────────────────────────────────
  home.packages = with pkgs; [
    # Modern CLI replacements (used by aliases.sh)
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
    starship
    shellcheck
    shfmt
  ];

  # ── Bash ──────────────────────────────────────────────────────────────────
  programs.bash = {
    enable = true;
    initExtra = ''
      export DOTFILES_ROOT="${dotfilesRoot}"
      export HM_MANAGED=1

      # Source dotfiles shell stack
      # direnv/starship/zoxide hooks are injected by home-manager above this block
      [ -f "$DOTFILES_ROOT/shell/shared/env.sh" ]     && source "$DOTFILES_ROOT/shell/shared/env.sh"
      [ -f "$DOTFILES_ROOT/shell/bash/bashrc" ]        && source "$DOTFILES_ROOT/shell/bash/bashrc"
      [ -f "$DOTFILES_ROOT/shell/shared/aliases.sh" ]  && source "$DOTFILES_ROOT/shell/shared/aliases.sh"
      [ -f "$DOTFILES_ROOT/shell/shared/ai-tools.sh" ] && source "$DOTFILES_ROOT/shell/shared/ai-tools.sh"
    '';
  };

  # ── Zsh ───────────────────────────────────────────────────────────────────
  programs.zsh = {
    enable = true;
    initContent = ''
      export DOTFILES_ROOT="${dotfilesRoot}"
      export HM_MANAGED=1

      # direnv/starship/zoxide hooks are injected by home-manager above this block
      # zshrc internally sources env.sh, aliases.sh, and tooling.sh (guarded by HM_MANAGED)
      [ -f "$DOTFILES_ROOT/shell/zsh/zshrc" ]          && source "$DOTFILES_ROOT/shell/zsh/zshrc"
      [ -f "$DOTFILES_ROOT/shell/shared/ai-tools.sh" ] && source "$DOTFILES_ROOT/shell/shared/ai-tools.sh"
    '';
  };

  # ── Git ───────────────────────────────────────────────────────────────────
  programs.git = {
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
        s    = "status -sb";
        a    = "add";
        c    = "commit";
        co   = "checkout";
        b    = "branch";
        p    = "push";
        pl   = "pull --rebase";
        f    = "fetch --all --prune";
        lg   = "log --oneline --graph --decorate";
        ll   = "log --graph --pretty=format:'%C(yellow)%h%Creset -%C(auto)%d%Creset %s %C(green)(%cr) %C(bold blue)<%an>%Creset'";
        d    = "diff";
        dc   = "diff --cached";
        ds   = "diff --stat";
        sl   = "stash list";
        sa   = "stash apply";
        sp   = "stash pop";
        undo = "reset --soft HEAD~1";
        pushit = "!git push -u origin $(git branch --show-current)";
        rebase-main = "!git rebase -i $(git merge-base HEAD main)";
      };
    };
  };

  # ── Jujutsu ───────────────────────────────────────────────────────────────
  programs.jujutsu = {
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

  # ── Direnv ────────────────────────────────────────────────────────────────
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  # ── Starship prompt ───────────────────────────────────────────────────────
  programs.starship = {
    enable = true;
  };

  # ── Zoxide (better cd) ───────────────────────────────────────────────────
  programs.zoxide = {
    enable = true;
    enableBashIntegration = true;
    enableZshIntegration = true;
  };

  # ── GitHub CLI ───────────────────────────────────────────────────────────
  programs.gh = {
    enable = true;
    settings = {
      git_protocol = "ssh";
      prompt = "enabled";
      aliases = {
        co = "pr checkout";
      };
    };
  };
}
