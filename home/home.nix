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
  hostname ? "",
  ...
}: let
  localeEnvironment = {
    LANG = "C.UTF-8";
    LC_ALL = "C.UTF-8";
  };
in {
  dotfiles.machine.tailnetHostname =
    if lib.toLower hostname == "mikki-bunker"
    then "bunker"
    else null;

  imports =
    [
      sops-nix.homeManagerModules.sops
      ./modules/machine-role.nix
      ./modules/activation.nix
      ./modules/packages.nix
      ./modules/shell.nix
      ./modules/git.nix
      ./modules/cursor-stable-shell.nix
      ./modules/git-auto-backup.nix
      ./modules/home-emergency-backup.nix
      ./modules/files.nix
      ./modules/build-cache-maintenance.nix
      ./modules/hermes-proxy.nix
      ./modules/hermes-tui.nix
      ./modules/ai-tools.nix
      ./modules/ops-tools.nix
      ./modules/nix-index.nix
      ./modules/dotfiles-auto-update.nix
      ./modules/mise-auto-update.nix
      ./modules/tailscale.nix
      ./modules/wezterm.nix
    ]
    # GPU/CUDA workers — Bunker only (x86_64 + explicit hostname guard).
    # targetSystem comes from extraSpecialArgs (not pkgs.stdenv) to avoid
    # infinite recursion when evaluating the imports list.
    ++ lib.optionals (targetSystem == "x86_64-linux" && lib.toLower hostname == "mikki-bunker") [
      ../services/remote-gpu-worker
    ];

  # Top-level SOPS key source so every host (including dev1) can decrypt,
  # not just hosts that trigger Hermes proxy modules.
  sops.age.keyFile = "/home/mhugo/.config/sops/age/keys.txt";
  sops.defaultSopsFile = ../secrets/api-keys.yaml;

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
      "$HOME/.local/bin" # pip/pipx, claude CLI, local tools
      "$HOME/.local/share/mise/shims" # mise-managed tools such as codex and copilot
      "$HOME/.npm-global/bin" # opencode and other npm globals
      "$HOME/.cargo/bin" # cargo-installed Rust binaries
      "$HOME/.amp/bin"
      # ~/.kimi-code/bin removed — kimi is managed by mise (npm:@moonshot-ai/kimi-code)
    ];

    # Environment variables exported into every session before shell init runs.
    sessionVariables =
      localeEnvironment
      // {
        # Route all nix CLI through the daemon. Without this, nix tries direct
        # /nix/store writes for flake-source coercion and fails on this
        # daemon-owned multi-user install (drwxrwxr-t root:nixbld).
        NIX_REMOTE = "daemon";
        # vega is a k3s agent — local /etc/rancher/k3s/k3s.yaml points at
        # 127.0.0.1:6443 which has no listener. The cluster API is fronted by
        # cluster.infra.centralcloud.com (5 control-plane nodes via DNS-RR);
        # ~/.kube/config already points at it.
        KUBECONFIG = "$HOME/.kube/config";
        NPM_CONFIG_PREFIX = "$HOME/.npm-global";
        SOPS_AGE_KEY_FILE = "$HOME/.config/sops/age/keys.txt";
        MINIMAX_API_HOST = "https://api.minimax.io";
        MISE_YES = "1";
        COLORTERM = "truecolor";
        RIPGREP_CONFIG_PATH = "$HOME/.config/ripgrep/config";
        BAT_CONFIG_PATH = "$HOME/.config/bat/config";
        CCACHE_DIR = "$HOME/.cache/ccache";
        CMAKE_C_COMPILER_LAUNCHER = "ccache";
        CMAKE_CXX_COMPILER_LAUNCHER = "ccache";
        LETTA_BASE_URL = "http://127.0.0.1:8283";
        # OpenBao CLI — served at kv.infra.centralcloud.com (public, Authentik
        # forward-auth on /ui, token auth on API). `bao login -method=oidc`
        # authenticates via Authentik (passkey/TOTP). bao appends /v1 so no
        # trailing slash.
        BAO_ADDR = "https://kv.infra.centralcloud.com";
      };
  };

  # GUI and background clients launched as user services do not inherit a
  # login shell. Keep their locale identical to managed interactive clients.
  systemd.user.sessionVariables = localeEnvironment;

  # home-manager manages its own config file (~/.config/home-manager/).
  programs.home-manager.enable = true;
}
