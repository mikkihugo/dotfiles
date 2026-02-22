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

  # ── Shell ─────────────────────────────────────────────────────────────────
  programs.bash = {
    enable = true;
    initExtra = ''
      export DOTFILES_ROOT="${dotfilesRoot}"

      # Source dotfiles shell stack
      [ -f "$DOTFILES_ROOT/shell/shared/env.sh" ]     && source "$DOTFILES_ROOT/shell/shared/env.sh"
      [ -f "$DOTFILES_ROOT/shell/bash/bashrc" ]        && source "$DOTFILES_ROOT/shell/bash/bashrc"
      [ -f "$DOTFILES_ROOT/shell/shared/aliases.sh" ]  && source "$DOTFILES_ROOT/shell/shared/aliases.sh"
      [ -f "$DOTFILES_ROOT/shell/shared/tooling.sh" ]  && DOTFILES_SHELL=bash source "$DOTFILES_ROOT/shell/shared/tooling.sh"
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
    # Config picked up from ~/.config/starship.toml if present
  };

  # ── Zoxide (better cd) ───────────────────────────────────────────────────
  programs.zoxide = {
    enable = true;
    enableBashIntegration = true;
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
