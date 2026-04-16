# home/home.nix — declarative user environment entry point
#
# Applies the full home-manager configuration via `hms` (alias in shell.nix).
#
# Structure (LazyVim-inspired — one file per concern, Nix merges them):
#   modules/activation.nix  — hms activation hooks (conflict cleanup, tool installs)
#   modules/packages.nix    — home.packages (CLI tools, runtimes, fonts)
#   modules/shell.nix       — bash, zsh, aliases, direnv, starship, zoxide
#   modules/git.nix         — git, jujutsu, gh
#   modules/files.nix       — home.file symlinks (configs for ripgrep, bat, VSCode…)
#
# Why home-manager instead of raw dotfile symlinks?
#   Atomic — either the whole generation activates or nothing changes.
#   Reproducible — same flake.lock = identical environment on any machine.
#   No drift — edits directly in $HOME are overwritten on the next `hms`.
{
  pkgs,
  lib,
  sops-nix,
  targetSystem ? pkgs.stdenv.hostPlatform.system,
  ...
}: {
  imports =
    [
      sops-nix.homeManagerModules.sops
      ./modules/activation.nix
      ./modules/packages.nix
      ./modules/shell.nix
      ./modules/git.nix
      ./modules/files.nix
      ./modules/openclaw.nix
      ./modules/dotfiles-auto-update.nix
    ]
    # GPU/CUDA embedding worker — x86_64 WSL2 desktop only.
    # targetSystem comes from extraSpecialArgs (not pkgs.stdenv) to avoid
    # infinite recursion when evaluating the imports list.
    ++ lib.optionals (targetSystem == "x86_64-linux") [
      ../services/ace-embedding-worker
    ];

  home = {
    username = "mhugo";
    homeDirectory = "/home/mhugo";

    # stateVersion pins the home-manager release that manages migration.
    # Do NOT change this after first activation — it controls format upgrades,
    # not the software versions (those come from nixpkgs).
    stateVersion = "25.11";

    # PATH additions — prepended before the system PATH in every session.
    sessionPath = [
      "$HOME/.bun/bin"
      "$HOME/.local/bin" # pip/pipx, claude CLI, secret-tui
      "$HOME/.npm-global/bin" # openclaw, opencode, and other npm globals
      "$HOME/.cargo/bin" # cargo-installed Rust binaries
      "$HOME/.amp/bin"
    ];

    # Environment variables exported into every session before shell init runs.
    sessionVariables = {
      NPM_CONFIG_PREFIX = "$HOME/.npm-global";
      SOPS_AGE_KEY_FILE = "$HOME/.config/sops/age/keys.txt";
      MINIMAX_API_HOST = "https://api.minimax.io";
      COLORTERM = "truecolor";
      RIPGREP_CONFIG_PATH = "$HOME/.config/ripgrep/config";
      BAT_CONFIG_PATH = "$HOME/.config/bat/config";
      LETTA_BASE_URL = "http://127.0.0.1:8283";
    };
  };

  # home-manager manages its own config file (~/.config/home-manager/).
  programs.home-manager.enable = true;
}
