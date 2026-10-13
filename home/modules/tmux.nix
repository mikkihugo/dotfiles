# home/modules/tmux.nix — tmux defaults for zsh + starship sessions
#
# Pairs with programs.zsh (login shell in new panes) and direnv-instant
# (async direnv inside tmux). SSH attach prompt lives in shell.nix shellInit.
#
# Mouse stays on for wheel history, pane select, and resize. Cursor chat can
# ingest SGR mouse bytes if the terminal pane is focused while you compose;
# focus the composer or prefix-m toggle mouse off briefly (see extraConfig).
{pkgs, ...}: {
  programs.tmux = {
    enable = true;
    escapeTime = 0;
    historyLimit = 100000;
    keyMode = "vi";
    mouse = true;
    terminal = "tmux-256color";
    baseIndex = 1;

    plugins = with pkgs.tmuxPlugins; [
      sensible
      yank
      prefix-highlight
    ];

    extraConfig = ''
      set -g default-shell "${pkgs.zsh}/bin/zsh"
      set -g default-command "${pkgs.zsh}/bin/zsh -l"

      set -g pane-base-index 1
      set -g renumber-windows on

      set -g set-clipboard on
      setw -g mode-keys vi
      setw -g monitor-activity on
      set -g visual-activity off
      set -g status-position top
      set -g focus-events on

      # Prefix-m: toggle mouse (scroll/pane ops vs quiet typing in IDE chat).
      bind m set -g mouse ! \; display-message "mouse #{?mouse,on,off}"

      # Splits open in the current path (Engine lanes, infra, dotfiles).
      bind | split-window -h -c "#{pane_current_path}"
      bind - split-window -v -c "#{pane_current_path}"
      bind '"' split-window -h -c "#{pane_current_path}"
      bind % split-window -v -c "#{pane_current_path}"

      bind r source-file ~/.config/tmux/tmux.conf \; display-message "tmux reloaded"

      # Prefix: Ctrl-a (GNU screen style); prefix-highlight still shows when active.
      unbind C-b
      set -g prefix C-a
      bind C-a send-prefix
    '';
  };
}
