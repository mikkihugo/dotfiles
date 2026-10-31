# flake.nix — dotfiles entry point
#
# Purpose:
#   Single source of truth for the entire user environment. Profiles:
#
#   homeConfigurations."mikki-bunker"  — x86_64 WSL2 desktop
#   homeConfigurations."mikki-laptop"  — aarch64 laptop
#   homeConfigurations."cc-se-sto-devbox-01" — x86_64 fleet devbox
#   homeConfigurations."mhugo"         — generic x86_64 fallback
#
#   devShells.default  — lightweight shell for dotfiles maintenance.
#
{
  description = "mhugo dotfiles — home-manager + SOPS (multi-arch)";

  nixConfig = {
    extra-substituters = [
      "https://cache.flakecache.com/default"
      "https://nix-community.cachix.org"
      "https://cache.numtide.com"
    ];
    extra-trusted-public-keys = [
      "default:ESyvaQTiq681JA0iaH5tsQWS+R5qqJUVdVY1OXbi9to="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
    ];
    accept-flake-config = true;
    fallback = true;
    connect-timeout = 5;
  };

  inputs = {
    # NixOS 26.05 release branch: stable base for the user environment.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    # Fleet-canonical nixpkgs rev (Rust toolchain packages, Engine/jcode alignment).
    # Bump only in Engine nix/toolchains/nixpkgs-pin; consumers follow nixpkgs.
    engine-nixpkgs-pin.url = "git+ssh://git@git.centralcloud.net:2222/singularity/singularity-engine?dir=nix/toolchains/nixpkgs-pin";

    # Unstable provides selected tools that lag in nixos-26.05: mise and
    # ast-grep. Drop each override when the stable input meets its contract.
    # jujutsu is not on this input. A channel update must not move it.
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Exact jujutsu 0.46.0. nixos-26.05 still ships 0.41.0. This rev is the
    # nixpkgs commit whose pkgs/by-name/ju/jujutsu/package.nix sets
    # version = "0.46.0" (the first release that colocates a non-default
    # workspace as a Git worktree). Bump the URL on purpose.
    nixpkgs-jujutsu = {
      url = "github:NixOS/nixpkgs/6510408d147d8c5e6d76043e899e9251756f6a75";
      flake = false;
    };

    # direnv 2.38.2 (published 2026-10-10). nixos-26.05 ships 2.37.1 and the
    # nixpkgs-unstable pin (6510408d147d, 2026-10-10 01:01Z) predates the
    # 2.38.2 packaging later that day. This rev is the nixos-unstable channel
    # commit that packages 2.38.2. Bump the URL on purpose.
    nixpkgs-direnv = {
      url = "github:NixOS/nixpkgs/3ec636362e1816bc2f0888fa0fa2c69f1bc9e504";
      flake = false;
    };

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

    # Non-blocking interactive direnv hooks. Keep this as an explicit input
    # until the pinned nixpkgs release exports the package.
    direnv-instant = {
      url = "github:Mic92/direnv-instant/1.3.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    nixpkgs,
    nixpkgs-unstable,
    nixpkgs-jujutsu,
    nixpkgs-direnv,
    engine-nixpkgs-pin,
    home-manager,
    sops-nix,
    flake-utils,
    llm-agents,
    direnv-instant,
    ...
  }: let
    direnvExportShellGuard = ./config/direnv/direnv-export-shell-guard.nix;
    specialArgs = {
      inherit sops-nix llm-agents direnv-instant engine-nixpkgs-pin;
    };

    # Single nixpkgs per system, shared across the outputs below. Re-using
    # this binding instead of re-importing inside the `formatter` and
    # `checks` blocks keeps the closure shareable (substituters cache the
    # same store path for the same args) and avoids the per-system evaluation
    # cost of two `import nixpkgs` calls.
    pkgsFor = system:
      import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };

    # Single home.nix works on all arches. targetSystem is passed as
    # specialArgs so imports can branch without referencing pkgs.
    mkHome = sys: hostname: let
      home = home-manager.lib.homeManagerConfiguration {
        pkgs = import nixpkgs {
          system = sys;
          config.allowUnfree = true;
          overlays = [
            # jujutsu 0.46.0 comes from the exact nixpkgs-jujutsu input.
            # 26.05 still ships 0.41.0. Do not take it from nixpkgs-unstable.
            #
            # mise 2026.10.3: pull from nixpkgs-unstable for newer version
            # (26.05 has 2026.5.12, unstable has 2026.10.3)
            #
            # ripgrep 15.2.0: pull from nixpkgs-unstable for the .jj VCS
            # detection + gitignore-across-dirs fixes (#3212/#3320/#3376).
            # 26.05 has 15.1.0, where cwd-based rg inside jj lanes
            # intermittently returns exit 1 / zero results (verified on
            # cc-se-sto-devbox-01 2026-10-27, reproducible 10/10).
            #
            # direnv 2.38.2 + export-shell guard (AIP-193-style CLI errors).
            (_final: prev: let
              direnvBase = (import nixpkgs-direnv {system = sys;}).direnv;
            in {
              ast-grep = nixpkgs-unstable.legacyPackages.${sys}.ast-grep;
              inherit (nixpkgs-unstable.legacyPackages.${sys}) ripgrep;
              direnv = prev.callPackage direnvExportShellGuard {
                direnv = direnvBase;
              };
              inherit (import nixpkgs-jujutsu {system = sys;}) jujutsu;
              inherit (nixpkgs-unstable.legacyPackages.${sys}) mise;
              nix-index = prev.nix-index.overrideAttrs (old: {
                buildCommand =
                  old.buildCommand
                  + ''
                    command_not_found=$out/etc/profile.d/command-not-found.sh
                    command_not_found_source=$(readlink -f "$command_not_found")
                    rm -f "$command_not_found"
                    cp "$command_not_found_source" "$command_not_found"
                    chmod u+w "$command_not_found"
                    substituteInPlace "$command_not_found" \
                      --replace-fail "nix profile install" "nix profile add"
                  '';
              });
            })
          ];
        };
        extraSpecialArgs =
          specialArgs
          // {
            targetSystem = sys;
            inherit hostname;
          };
        modules = [
          direnv-instant.homeModules.direnv-instant
          ./home/home.nix
        ];
      };
    in
      home
      // {
        # Home Manager upstream still emits the deprecated Nix 2.34 alias.
        # Patch only the generated activation entrypoint until upstream #9598
        # replaces `profile install` with `profile add`.
        activationPackage = home.activationPackage.overrideAttrs (old: {
          buildCommand =
            old.buildCommand
            + ''
              substituteInPlace $out/activate \
                --replace-fail "profile install" "profile add"
            '';
        });
      };
  in
    {
      homeConfigurations = {
        # mikki-bunker: x86_64 WSL2 desktop.
        "mikki-bunker" = mkHome "x86_64-linux" "mikki-bunker";
        # mikki-laptop: aarch64 portable machine.
        "mikki-laptop" = mkHome "aarch64-linux" "mikki-laptop";
        # CentralCloud development host: x86_64 without the bunker GPU role.
        "cc-se-sto-devbox-01" = mkHome "x86_64-linux" "cc-se-sto-devbox-01";
        # Generic username fallback. Named machines use their explicit profile,
        # so pure evaluation never depends on evaluator state and an unknown
        # host cannot accidentally enable the bunker GPU role.
        "mhugo" = mkHome "x86_64-linux" "";
      };

      # `nix fmt` runs alejandra on every .nix file in the repo.
      formatter =
        nixpkgs.lib.genAttrs ["x86_64-linux" "aarch64-linux"]
        (sys: (pkgsFor sys).alejandra);

      # `nix flake check` runs the same lint chain the pre-commit hook
      # enforces. Canonical Nix shape: each check is a NAMED derivation
      # under `checks.<system>` (not a single derivation per system;
      # that's the schema trap because an unnamed `checks.<sys> =
      # derivation;` is read as a derivation whose `.outPath` is then
      # checked as if it were itself a derivation).
      checks =
        nixpkgs.lib.genAttrs ["x86_64-linux" "aarch64-linux"]
        (sys: let
          pkgs = pkgsFor sys;
        in {
          format =
            pkgs.runCommand "dotfiles-format-check-${sys}" {
              src = ./.;
              buildInputs = [pkgs.alejandra];
            } ''
              cd "$src"
              alejandra --check .
              touch $out
            '';
          statix-check =
            pkgs.runCommand "dotfiles-statix-check-${sys}" {
              src = ./.;
              buildInputs = [pkgs.statix];
            } ''
              cd "$src"
              statix check .
              touch $out
            '';
          deadnix-check =
            pkgs.runCommand "dotfiles-deadnix-check-${sys}" {
              src = ./.;
              buildInputs = [pkgs.deadnix];
            } ''
              cd "$src"
              # 1.3 dropped --no-unused/--error. --fail matches lefthook.
              deadnix --fail .
              touch $out
            '';
          jujutsu-pin = let
            pinned = import nixpkgs-jujutsu {system = sys;};
          in
            pkgs.runCommand "dotfiles-jujutsu-pin-${sys}" {
              inherit (pinned.jujutsu) version;
            } ''
              test "$version" = 0.46.0
              printf '%s\n' "$version" > "$out"
            '';
        });
    }
    // flake-utils.lib.eachDefaultSystem (sys: let
      # Re-use the shared `pkgsFor` binding so this block's derivations
      # are path-equal to the `formatter` / `checks` ones above. Without
      # this, each system would have two nixpkgs instances differing only
      # by file id, which breaks `nix path-info --requisites` deduplication
      # for any consumer of multiple outputs.
      maintenance-pkgs = pkgsFor sys;
    in {
      # Bootstrap runner from the same locked Home Manager input used to build
      # the profiles. `nix run path:.#home-manager -- switch ...` therefore
      # cannot drift to a mutable Home Manager branch.
      packages.home-manager = home-manager.packages.${sys}.home-manager;

      # `nix develop` — for editing secrets and running dotfiles linters.
      # Not the daily shell (home-manager provides that); this shell is
      # only needed when working on the dotfiles repo itself.
      devShells.default = maintenance-pkgs.mkShell {
        packages = with maintenance-pkgs; [
          go # build and validate local Go tools
          cargo # build and validate local Rust tools
          nodejs # run Node contract tests from the canonical repo check
          python3 # nixpkgs interpreter for repo-check Python tests (not mise)
          nix-fast-build # parallel activation evaluation/build for `repo check`
          gnumake # native builds in the maintenance shell
          pkg-config # native dependency discovery for rust crates when needed
          sops # encrypt/decrypt secrets/api-keys.yaml
          age # age key generation and encryption backend
          ssh-to-age # derive age public key from SSH ed25519 key
          shellcheck # lint shell scripts
          shfmt # format shell scripts
        ];

        shellHook = ''
          export DOTFILES_ROOT="$(pwd -P)"
          export PATH="$DOTFILES_ROOT/bin:$PATH"
          # Contract tests scope this immutable Git path to child processes
          # that need native Git while keeping the agent-facing facade intact.
          export SE_GIT_BIN="${maintenance-pkgs.git}/bin/git"
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
