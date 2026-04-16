# home/modules/shell.nix — interactive shell configuration
#
# Covers: bash, zsh, aliases, direnv, starship prompt, zoxide.
# The shared `shellInit` string is injected into both bash and zsh so
# there's a single source of truth for the runtime init sequence.
{
  pkgs,
  lib,
  ...
}: let
  dotfilesRoot = "$HOME/.dotfiles";

  # Injected into both bash initExtra and zsh initContent.
  # Activates mise/SOPS/direnv at shell startup; reads Letta API key from file.
  shellInit = ''
    export DOTFILES_ROOT="${dotfilesRoot}"
    export HM_MANAGED=1

    # Activate mise, load SOPS secrets, handle non-interactive direnv,
    # and source third-party completions. See shell/bash/bashrc for details.
    [ -f "$DOTFILES_ROOT/shell/bash/bashrc" ] && source "$DOTFILES_ROOT/shell/bash/bashrc"
    type _load_sops_secrets >/dev/null 2>&1 && _load_sops_secrets >/dev/null 2>&1 || true

    # Letta API key from file (LETTA_BASE_URL is in home.sessionVariables).
    if [ -f "$HOME/.letta/api_key" ]; then
      export LETTA_API_KEY="$(cat "$HOME/.letta/api_key")"
    fi
  '';
in {
  home.shellAliases = {
    # home-manager: apply the current flake config on any arch.
    # `mhugo` profile uses builtins.currentSystem — works on both machines.
    # --impure is required because flake.nix reads builtins.currentSystem.
    hms = "home-manager switch --flake ~/.dotfiles#mhugo --impure";

    # Promote the currently committed ACE revision into the dotfiles flake input.
    promote-ace-coder = "~/.dotfiles/scripts/promote-ace-coder-input";

    # Secrets management
    secrets = "~/.dotfiles/scripts/secrets-edit";
    secrets-tui = "secret-tui";

    # Register this machine as an openclaw node (run once after hms on a new machine).
    openclaw-setup = "openclaw node install --host ai.hugo.dk --port 443 --tls --display-name Laptop && openclaw node restart";

    # ls replacements via eza. NOT aliasing grep→rg or find→fd — different
    # argument syntax would break scripts that rely on them.
    ls = "eza --group-directories-first";
    ll = "eza -la --group-directories-first --git";
    lt = "eza --tree --level=2 --group-directories-first";
    la = "eza -la --group-directories-first --git --all";

    # bat-powered man pages
    man = "batman";
  };

  programs = {
    bash = {
      enable = true;
      initExtra = shellInit;
    };

    # zsh uses initContent (home-manager 24.11+); same init sequence as bash.
    zsh = {
      enable = true;
      initContent = shellInit;
    };

    # direnv: auto-load nix devShell when cd-ing into a project.
    # nix-direnv caches the nix eval so `cd` is instant after the first load.
    direnv = {
      enable = true;
      nix-direnv.enable = true;
    };

    # Starship: cross-shell prompt. Config lives in config/starship.toml to
    # avoid Nix escaping issues with starship's format strings.
    starship = {
      enable = true;
      configPath = toString ../../config/starship.toml;
    };

    # Zoxide: frecency-based `cd` replacement. `z foo` jumps to the most-visited
    # directory matching "foo". Enabled for both shells.
    zoxide = {
      enable = true;
      enableBashIntegration = true;
      enableZshIntegration = true;
    };
  };
}
