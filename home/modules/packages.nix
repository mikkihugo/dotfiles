# home/modules/packages.nix — user profile packages
#
# Installed into the user profile (available on PATH without a shell hook).
# Grouped by role — remove a whole group if a machine doesn't need it.
{pkgs, ...}: {
  home.packages = with pkgs; [
    # Networking — resilient remote shell.
    mosh # UDP-based ssh replacement, survives roaming/sleep, local echo

    # Modern CLI replacements — faster, friendlier alternatives to coreutils.
    # Aliases (ls→eza, man→batman) are declared in shell.nix shellAliases.
    eza # ls replacement (tree view, git status, icons)
    bat # cat replacement (syntax highlight, paging)
    fd # find replacement (respects .gitignore, faster)
    ripgrep # grep replacement (recursive, fast, .gitignore-aware)
    fzf # fuzzy finder (piped into other tools or used standalone)
    zoxide # smarter cd (frecency-based, `z` alias)
    delta # git diff pager (side-by-side, syntax highlight)
    jq # JSON query and transform
    yq-go # Mike Farah yq v4; repo validators rely on eval/ea and -o=json
    btop # process/resource monitor (replaces htop)
    tokei # count lines of code by language
    difftastic # structural diff (understands syntax, not just lines)

    # bat-extras — bat-powered wrappers for standard tools
    bat-extras.batman # man pages with syntax highlighting
    bat-extras.batgrep # ripgrep output through bat
    bat-extras.batdiff # diff output through bat

    # Dev tools — language runtimes and package managers available globally.
    # (project-level runtimes live in per-repo flake devShells via direnv)
    bun # JavaScript runtime/package manager for local tool builds
    ccache # C/C++ compiler cache; CMake launcher env is set in home.nix
    mise # polyglot runtime/tool manager; installs live under ~/.local/share/mise
    tea # Forgejo/Gitea CLI client
    git-lfs # large file storage extension for git
    gcc # provides `cc` for local source builds during HM activation
    go # build local Go tools
    pnpm # fast, disk-efficient Node package manager
    sccache # Rust compiler cache; Cargo wrapper is managed in files.nix
    uv # Python package/runner — provides `uvx` required by the Serena MCP plugin

    # Secret management — SOPS/age toolchain for encrypting dotfile secrets.
    # Also in devShell but listed here so they're always available without
    # entering `nix develop`.
    sops # encrypts/decrypts YAML/JSON secrets
    age # encryption backend (replaces GPG for SOPS)
    ssh-to-age # derives age pubkey from SSH ed25519 key
    openbao # `bao` CLI — talks to kv.infra.centralcloud.com (Authentik-gated /ui) via BAO_ADDR
    # Shell tooling — linters used by lefthook pre-commit hooks.
    shellcheck # static analysis for shell scripts
    shfmt # formatter for shell scripts

    # Nix tooling — meta-tools for working with the Nix ecosystem.
    nixd # Nix language server (autocomplete, diagnostics in editors)
    alejandra # opinionated Nix formatter (used in pre-commit)
    statix # Nix linter — catches anti-patterns (used in pre-commit)
    deadnix # finds unused Nix expressions (dead code)
    nix-tree # visualise the derivation dependency tree
    nvd # diff between home-manager / NixOS generations
    nix-output-monitor # prettier `nix build` output
    nix-index # `nix-locate`: find which package provides a binary
    kubectl # Kubernetes CLI for Flux/k3s validation and ops

    # Nerd Fonts — required for starship icons, eza glyphs, git symbols.
    # WSL2/VSCode Remote: also install on the Windows side for the terminal font:
    #   winget install -e --id DEVCOM.JetBrainsMonoNerdFont
    nerd-fonts.jetbrains-mono

    # Clipboard — Wayland clipboard integration.
    wl-clipboard

    # Pre-commit / code quality — run by lefthook on every commit.
    lefthook # git hook runner (runs alejandra, statix, shellcheck, etc.)
    typos # spell checker for source files
    detect-secrets # scans for accidentally committed credentials
  ];
}
