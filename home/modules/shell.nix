# home/modules/shell.nix — interactive shell configuration
#
# Covers: bash, zsh, aliases, direnv, starship prompt, zoxide.
# The shared `shellInit` string is injected into both bash and zsh so
# there's a single source of truth for the runtime init sequence.
_: let
  dotfilesRoot = "$HOME/.dotfiles";

  # Injected into both bash initExtra and zsh initContent.
  # Activates mise/SOPS/direnv at shell startup; reads Letta API key from file.
  shellInit = ''
    export DOTFILES_ROOT="${dotfilesRoot}"
    export HM_MANAGED=1

    # home-manager only sources hm-session-vars.sh from ~/.profile (login shells).
    # WSL/terminal-emulator bash starts as a non-login interactive shell, so PATH
    # entries from home.sessionPath (~/.bun/bin, ~/.npm-global/bin, ~/.cargo/bin,
    # etc.) never get added. Source it here so codex/gemini/opencode
    # resolve in interactive shells.
    unset __HM_SESS_VARS_SOURCED
    [ -f "$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh" ] \
      && . "$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh"

    # Activate mise, load SOPS secrets, handle non-interactive direnv,
    # and source runtime shell hooks. See shell/bash/bashrc for details.
    [ -f "$DOTFILES_ROOT/shell/bash/bashrc" ] && source "$DOTFILES_ROOT/shell/bash/bashrc"
    type _load_sops_secrets >/dev/null 2>&1 && _load_sops_secrets >/dev/null 2>&1 || true

    # Letta API key from file (LETTA_BASE_URL is in home.sessionVariables).
    if [ -f "$HOME/.letta/api_key" ]; then
      export LETTA_API_KEY="$(cat "$HOME/.letta/api_key")"
    fi

    # On SSH login, show detached tmux sessions that can be resumed.
    if [ "''${TMUX_LOGIN_PROMPT:-}" = "1" ] && [ -n "''${SSH_CONNECTION:-}" ] && [ -z "''${TMUX:-}" ] && [ -t 1 ] && command -v tmux >/dev/null 2>&1; then
      _tmux_detached="$(
        tmux list-sessions -F '#{session_attached}	#{session_name}	#{session_windows}	#{session_created_string}' 2>/dev/null \
          | awk -F '	' '$1 == 0 { printf "  %s (%s windows, created %s)\n", $2, $3, $4 }'
      )"
      if [ -n "$_tmux_detached" ]; then
        printf 'Detached tmux sessions:\n%s\n' "$_tmux_detached"
        printf 'Enter an existing session to attach, a new name to create, or empty to skip.\n'
        if [ -r /dev/tty ]; then
          printf 'tmux session: ' > /dev/tty
          IFS= read -r _tmux_attach < /dev/tty || _tmux_attach=
          if [ -n "$_tmux_attach" ]; then
            exec tmux new-session -A -s "$_tmux_attach"
          fi
          unset _tmux_attach
        fi
      fi
      unset _tmux_detached
    fi

  '';
in {
  home.file = {
    ".local/bin/home-manager" = {
      executable = true;
      force = true;
      text = ''
        #!/usr/bin/env bash
        set -euo pipefail

        real_home_manager="$HOME/.nix-profile/bin/home-manager"
        if [[ ! -x "$real_home_manager" ]]; then
          real_home_manager="/nix/var/nix/profiles/default/bin/home-manager"
        fi
        if [[ ! -x "$real_home_manager" ]]; then
          real_home_manager="/run/current-system/sw/bin/home-manager"
        fi

        if [[ "''${1:-}" == "switch" ]]; then
          shift
          exec "$real_home_manager" switch \
            --flake "$HOME/.dotfiles#$("$HOME/.dotfiles/scripts/current-home-profile")" \
            --extra-experimental-features 'nix-command flakes' \
            "$@"
        fi

        exec "$real_home_manager" "$@"
      '';
    };

    ".local/bin/receipts-browser" = {
      executable = true;
      force = true;
      text = ''
        #!/usr/bin/env bash
        set -euo pipefail

        profile_dir="''${RECEIPTS_CHROME_PROFILE:-$HOME/.local/share/receipts-browser/chrome-profile}"
        default_url="''${RECEIPTS_BROWSER_URL:-about:blank}"

        case "''${1:-}" in
          --help|-h)
            cat <<'USAGE'
        Usage: receipts-browser [url]

        Opens Chrome/Chromium with a dedicated persistent profile for receipt
        portals such as Mynt and supplier dashboards. Log in manually inside this
        browser; cookies, passkeys, and normal browser state remain in this
        dedicated profile. This launcher does not enable Chrome remote debugging.

        Environment:
          RECEIPTS_CHROME_PROFILE  Override the profile directory.
          RECEIPTS_BROWSER_URL     Override the default URL.
        USAGE
            exit 0
            ;;
          --profile-dir)
            printf '%s\n' "$profile_dir"
            exit 0
            ;;
        esac

        chrome=""
        for candidate in google-chrome-stable google-chrome chromium chromium-browser; do
          if command -v "$candidate" >/dev/null 2>&1; then
            chrome="$(command -v "$candidate")"
            break
          fi
        done

        if [[ -z "$chrome" ]]; then
          echo "receipts-browser: Chrome/Chromium not found on PATH" >&2
          exit 127
        fi

        mkdir -p "$profile_dir"

        exec "$chrome" \
          --user-data-dir="$profile_dir" \
          --no-first-run \
          --no-default-browser-check \
          --class=ReceiptsBrowser \
          --new-window \
          "''${1:-$default_url}"
      '';
    };

    ".local/bin/mynt-receipts" = {
      executable = true;
      force = true;
      text = ''
        #!/usr/bin/env bash
        set -euo pipefail

        if [[ "''${1:-}" == "--help" || "''${1:-}" == "-h" ]]; then
          cat <<'USAGE'
        Usage: mynt-receipts [url]

        Opens Mynt in the dedicated receipts browser profile. Use
        receipts-browser [url] for other receipt portals that should share the
        same authenticated receipt-viewing profile.
        USAGE
          exit 0
        fi

        exec "$HOME/.local/bin/receipts-browser" "''${1:-https://app.mynt.com/}"
      '';
    };

    ".local/bin/receipts-browser-api" = {
      executable = true;
      force = true;
      text = ''
        #!/usr/bin/env bash
        set -euo pipefail

        profile_dir="''${RECEIPTS_CHROME_PROFILE:-$HOME/.local/share/receipts-browser/chrome-profile}"
        default_url="''${RECEIPTS_BROWSER_URL:-https://app.mynt.com/}"
        port="''${RECEIPTS_CDP_PORT:-9223}"

        case "''${1:-}" in
          --help|-h)
            cat <<'USAGE'
        Usage: receipts-browser-api [url]

        Opens the dedicated receipts browser profile with Chrome DevTools Protocol
        bound to 127.0.0.1 only. Use this for manual login followed by local API
        discovery or receipt export helpers. Do not expose the port over the LAN.

        Environment:
          RECEIPTS_CHROME_PROFILE  Override the profile directory.
          RECEIPTS_BROWSER_URL     Override the default URL.
          RECEIPTS_CDP_PORT        Override the local CDP port, default 9223.
        USAGE
            exit 0
            ;;
          --profile-dir)
            printf '%s\n' "$profile_dir"
            exit 0
            ;;
          --cdp-url)
            printf 'http://127.0.0.1:%s\n' "$port"
            exit 0
            ;;
        esac

        chrome=""
        for candidate in google-chrome-stable google-chrome chromium chromium-browser; do
          if command -v "$candidate" >/dev/null 2>&1; then
            chrome="$(command -v "$candidate")"
            break
          fi
        done

        if [[ -z "$chrome" ]]; then
          echo "receipts-browser-api: Chrome/Chromium not found on PATH" >&2
          exit 127
        fi

        mkdir -p "$profile_dir"

        exec "$chrome" \
          --user-data-dir="$profile_dir" \
          --no-first-run \
          --no-default-browser-check \
          --remote-debugging-address=127.0.0.1 \
          --remote-debugging-port="$port" \
          --class=ReceiptsBrowserApi \
          --new-window \
          "''${1:-$default_url}"
      '';
    };

    ".local/bin/mynt-receipts-api" = {
      executable = true;
      force = true;
      text = ''
        #!/usr/bin/env bash
        set -euo pipefail
        exec "$HOME/.local/bin/receipts-browser-api" "''${1:-https://app.mynt.com/}"
      '';
    };
  };

  # Claude Code is Nix-managed via the sadjow/claude-code-nix overlay
  # (pkgs.claude-code in ai-tools.nix → ~/.nix-profile/bin/claude). The native
  # runtime self-updater is disabled (read-only store); freshness comes from
  # `nix flake update` on the claude-code input, automated by dotfiles-auto-update.
  # bypassPermissions is set globally via ~/.claude/settings.json — no wrapper needed.

  home.shellAliases = {
    # home-manager: resolve the explicit host profile from the current hostname.
    hms = "home-manager switch";

    # Promote the currently committed ACE revision into the dotfiles flake input.
    promote-ace-coder = "~/.dotfiles/scripts/promote-ace-coder-input";

    # Secrets management
    secrets = "~/.dotfiles/scripts/secrets-edit";

    # Promote live Codex client model/reasoning choices into dotfiles.
    codex-save-prefs = "~/.dotfiles/scripts/codex-preferences save";

    # Cluster: fetch the k3s kubeconfig from rigel for off-cluster kubectl
    fetch-kubeconfig = "~/.dotfiles/scripts/fetch-kubeconfig";
    k = "kubectl";
    kctx = "kubectx";
    kns = "kubens";
    kgp = "kubectl get pods";
    kgs = "kubectl get services";

    #ls replacements via eza. NOT aliasing grep→rg or find→fd — different
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

      # home-manager's own .bashrc template puts a bare
      # `[[ $- == *i* ]] || return` right after bashrcExtra, so
      # `source ~/.bashrc` always exits 1 in a non-interactive shell —
      # even though that's normal, by-design behavior (interactive-only
      # setup should skip). Non-interactive callers that chain on the
      # exit code (coder/codex's sandbox wrapper runs
      # `source ~/.bashrc && (cmd)`) treat that as a fatal error and
      # never run the actual command: every tool call failed instantly
      # with exit 1 and no output, regardless of which command was
      # requested (see /home/mhugo/code coder/codex investigation,
      # 2026-07-12). bashrcExtra runs *before* that guard, so handle the
      # non-interactive case here and return 0 explicitly before
      # home-manager's own guard is ever reached. This also makes the
      # non-interactive direnv-export/secrets-loading logic in
      # shell/bash/bashrc actually reachable, which it previously wasn't
      # (it lived in initExtra, past the guard, so it was dead code for
      # any non-interactive shell despite explicitly checking for one).
      bashrcExtra = ''
        if [[ $- != *i* ]]; then
          export DOTFILES_ROOT="${dotfilesRoot}"
          export HM_MANAGED=1
          [ -f "$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh" ] \
            && . "$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh"
          [ -f "$DOTFILES_ROOT/shell/bash/bashrc" ] && . "$DOTFILES_ROOT/shell/bash/bashrc"
          return 0
        fi
      '';
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
      config = {
        global.warn_timeout = "5m";
        whitelist = {
          prefix = ["/home/mhugo/code/"];
          exact = ["/home/mhugo/.dotfiles/.envrc"];
        };
      };
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
