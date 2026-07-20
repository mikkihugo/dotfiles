# flake.nix — dotfiles entry point
#
# Purpose:
#   Single source of truth for the entire user environment. Profiles:
#
#   homeConfigurations."mikki-bunker"  — x86_64 WSL2 desktop (GPU worker, CUDA)
#   homeConfigurations."mikki-laptop"  — aarch64 laptop (no GPU, no CUDA)
#   homeConfigurations."cc-se-sto-devbox-01" — x86_64 fleet devbox (no GPU role)
#   homeConfigurations."mhugo"         — generic x86_64 fallback (no GPU role)
#
#   devShells.default  — lightweight shell for dotfiles maintenance.
#
{
  description = "mhugo dotfiles — home-manager + SOPS (multi-arch)";

  nixConfig = {
    extra-substituters = [
      "https://cache.flakecache.com/default"
      "https://cuda-maintainers.cachix.org"
      "https://nix-community.cachix.org"
      "https://cache.numtide.com"
      "https://claude-code.cachix.org"
    ];
    extra-trusted-public-keys = [
      "default:ESyvaQTiq681JA0iaH5tsQWS+R5qqJUVdVY1OXbi9to="
      "cuda-maintainers.cachix.org-1:0dq3bujKpuEPMCX6U4WylrUDZ9JyUG0VpVZa7CNfq5E="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
      "claude-code.cachix.org-1:YeXf2aNu7UTX8Vwrze0za1WEDS+4DuI2kVeWEE4fsRk="
    ];
    accept-flake-config = true;
    fallback = true;
    connect-timeout = 5;
  };

  inputs = {
    # NixOS 26.05 release branch: stable base for the user environment.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    # Home Manager release branch follows the matching nixpkgs release.
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # sops-nix: home-manager module that can decrypt SOPS secrets at
    # activation time and expose them as files/env vars. Wired into
    # extraSpecialArgs so home.nix can opt in when needed.
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # flake-utils: builds the devShell for all default systems without
    # copy-pasting the per-system boilerplate.
    flake-utils.url = "github:numtide/flake-utils";

    # llm-agents: daily-updated Nix packages for AI coding agents (codex,
    # gemini-cli, opencode, amp, goose-cli, cursor-agent, droid, …).
    # Intentionally NOT following our nixpkgs — cache hits depend on the exact
    # store paths numtide built; overriding nixpkgs invalidates all of them.
    llm-agents.url = "github:numtide/llm-agents.nix";

    # claude-code: Anthropic's official native binary, repackaged with hourly
    # upstream CI bumps and a Cachix binary cache (claude-code.cachix.org).
    # Provides pkgs.claude-code via overlays.default. Same rationale as
    # llm-agents — NOT following our nixpkgs, or we'd miss the prebuilt cache.
    # Freshness comes from `nix flake update` (handled by dotfiles-auto-update),
    # not a runtime self-updater (the Nix store is read-only; it sets
    # DISABLE_AUTOUPDATER=1). Replaces the former mise-managed install.
    claude-code.url = "github:sadjow/claude-code-nix";

    # ace-coder: pinned clean source for the CUDA worker package and HM module.
    # Use a committed git revision from the local repo, not the live dirty tree,
    # so worker builds remain cacheable and reproducible.
    # Pinned to 9b6e50329 — last rev that builds cleanly under -D dead_code.
    # HEAD of main (017e53d44) orphaned 5 load_* functions in remote-worker
    # without cfg-gating them, failing the Nix build. The running worker
    # self-updates via WSS from llm-gateway, so the Nix-built binary is only
    # a first-boot seed — pinning an older rev does not affect runtime.
    ace-coder.url = "git+file:///home/mhugo/code/ace-coder?rev=58b7a904030dfd06e139aafc2222c1ea1331746c";

    # hermes-agent: self-improving agent.
    # Flake exposes packages.<system>.default wrapping the `hermes` binary.
    hermes-agent = {
      url = "github:NousResearch/hermes-agent";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    inference-fabric = {
      url = "git+ssh://git@git.infra.centralcloud.com:2222/singularity/inference-fabric.git?ref=main";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    nixpkgs,
    home-manager,
    sops-nix,
    flake-utils,
    ace-coder,
    hermes-agent,
    llm-agents,
    claude-code,
    inference-fabric,
    ...
  }: let
    specialArgs = {inherit sops-nix ace-coder hermes-agent llm-agents inference-fabric;};

    # Single home.nix works on all arches — GPU service is gated by lib.optionals.
    # targetSystem is passed as specialArgs so imports can branch without
    # referencing pkgs (which would cause infinite recursion in imports).
    mkHome = sys: hostname:
      home-manager.lib.homeManagerConfiguration {
        pkgs = import nixpkgs {
          system = sys;
          config.allowUnfree = true;
          # mise pinned ahead of nixos-26.05; drop once the channel catches up.
          # claude-code overlay: pkgs.claude-code = sadjow's hourly-fresh native binary.
          overlays = [
            (import ./overlays/mise.nix)
            claude-code.overlays.default
          ];
        };
        extraSpecialArgs =
          specialArgs
          // {
            targetSystem = sys;
            inherit hostname;
          };
        modules = [./home/home.nix];
      };
  in
    {
      homeConfigurations = {
        # mikki-bunker: x86_64 WSL2 desktop (GPU + embedding worker enabled).
        "mikki-bunker" = mkHome "x86_64-linux" "mikki-bunker";
        # mikki-laptop: aarch64 portable machine (GPU worker skipped automatically).
        "mikki-laptop" = mkHome "aarch64-linux" "mikki-laptop";
        # CentralCloud development host: x86_64 without the bunker GPU role.
        "cc-se-sto-devbox-01" = mkHome "x86_64-linux" "cc-se-sto-devbox-01";
        # Generic username fallback. Named machines use their explicit profile,
        # so pure evaluation never depends on evaluator state and an unknown
        # host cannot accidentally enable the bunker GPU role.
        "mhugo" = mkHome "x86_64-linux" "";
      };
    }
    // flake-utils.lib.eachDefaultSystem (sys: let
      maintenance-pkgs = import nixpkgs {
        system = sys;
        config.allowUnfree = true;
        overlays = [(import ./overlays/mise.nix)];
      };
    in {
      # `nix develop` — for editing secrets and running dotfiles linters.
      # Not the daily shell (home-manager provides that); this shell is
      # only needed when working on the dotfiles repo itself.
      devShells.default = maintenance-pkgs.mkShell {
        packages = with maintenance-pkgs; [
          go # build and validate local Go tools
          cargo # build and validate local Rust tools
          nodejs # run Node contract tests from the canonical repo check
          python3 # run Python preference/configuration contract tests
          just # operator entrypoints for dotfiles maintenance tasks
          nix-fast-build # parallel activation evaluation/build for `just check`
          mise # run/update mise-managed tools from the maintenance shell
          gnumake # required by mise/python-build when tracking python@latest
          pkg-config # native dependency discovery for rust crates when needed
          openssl # CPython ssl/hashlib modules for mise/python-build
          zlib # CPython zlib module; ensurepip needs this to unpack pip wheels
          bzip2 # CPython bz2 module
          xz # CPython lzma module
          zstd # CPython zstd module
          libffi # CPython ctypes module
          readline # CPython readline module
          sqlite # CPython sqlite3 module
          ncurses # CPython curses/readline terminal support
          gdbm # CPython dbm module
          tk # CPython tkinter module
          sops # encrypt/decrypt secrets/api-keys.yaml
          age # age key generation and encryption backend
          ssh-to-age # derive age public key from SSH ed25519 key
          shellcheck # lint shell scripts
          shfmt # format shell scripts
        ];

        shellHook = ''
          export DOTFILES_ROOT="$(pwd -P)"
          export PATH="$DOTFILES_ROOT/bin:$PATH"
          export SOPS_AGE_KEY_FILE="$HOME/.config/sops/age/keys.txt"
          mkdir -p "$(dirname "$SOPS_AGE_KEY_FILE")"

          echo "dotfiles maintenance shell (${sys})"
          echo "  secrets-view  — decrypt and print api-keys.yaml"
          echo "  secrets-edit  — open api-keys.yaml in \$EDITOR via sops"
          echo "  age-keygen    — print age pubkey derived from SSH key"

          # Convenience aliases for the secrets workflow.
          # sops set/unset must be used for in-place edits (never redirect stdout
          # back to the same file — sops overwrites it atomically).
          alias age-keygen="ssh-to-age -i ~/.ssh/id_ed25519.pub"
          alias secrets-edit="sops secrets/api-keys.yaml"
          alias secrets-view="sops -d secrets/api-keys.yaml"
        '';
      };
    });
}
