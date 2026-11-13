# Lane-audit toolchain — dev subflake.
#
# Purpose: the merge/resolve + workspace-audit tools that are not in the
# home profile, enterable ad hoc without a home-manager switch:
#
#   nix develop path:~/.dotfiles/flake/lane-audit
#   nix run path:~/.dotfiles/flake/lane-audit#weave -- --version
#
# Consumer: lane audits and jj conflict resolution (see
# ~/.agents/host/lane-audit-tools.md).
#
# The audit/recovery pipeline these tools implement (2026-11-13):
#
#   reposcan truth      -> stage-1 dirty/unpushed/stale scan (--no-telemetry)
#   fclones collapse    -> --isolate cross-tree dedupe of clone-equivalent lanes
#   difft variant       -> structural analysis of divergent file variants
#   newest-wins compose -> recover per surface from the NEWEST variant; older
#                          lanes fill gaps only (never overwrite newer wording)
#   mergiraf/weave-check-> compose merges with `jj resolve --tool mergiraf`,
#                          audit every resolution with `weave check`
#
# Hand-rolled diff evidence predates this pipeline; the pipeline is the
# authority. Lost-code rule: any lane with unpushed work is pushed/salvaged
# BEFORE its disposition is executed.
#
# The nixpkgs pin is the same rev the Engine flake uses for its
# `nixpkgs-jujutsu` input (weave 0.5.4 lives there; nixos-26.05 lags).
# Bump by editing this rev and `nix flake update` in this directory.
{
  description = "Lane-audit and merge-resolve toolchain (weave, mergiraf, zoekt, ctags, gita)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/6510408d147d8c5e6d76043e899e9251756f6a75";
  };

  outputs = {nixpkgs, ...}: let
    systems = ["x86_64-linux" "aarch64-linux"];
    forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    # Built from source (not in nixpkgs). Shared by packages and devShells.
    mkReposcan = pkgs:
      pkgs.buildGoModule {
        pname = "reposcan";
        version = "0-unstable-2026-11-03";
        src = pkgs.fetchFromGitHub {
          owner = "mabd-dev";
          repo = "reposcan";
          rev = "f7ac61db0c6b2538595a7013e8f8e32d0c6626e2"; # pragma: allowlist secret
          hash = "sha256-DhLcdeJiabaZyCRPnT1SOH3AaSuN0dqYBawhl34G3hE="; # pragma: allowlist secret
        };
        vendorHash = "sha256-tY37EyPoquYPR5h2yO762oAE24y6n9dqSmBQ77AW/fA="; # pragma: allowlist secret
        # golang.design/x/clipboard (TUI feature) compiles clipboard_linux.c
        # against X11 headers.
        buildInputs = [pkgs.libx11];
        # Upstream tests validate their default scan root (= $HOME), which does
        # not exist in the build sandbox.
        preCheck = "export HOME=$TMPDIR";
        meta.mainProgram = "reposcan";
      };
  in {
    packages = forAllSystems (pkgs: {
      inherit (pkgs) weave mergiraf zoekt universal-ctags gita lazyjj jj-fzf;
      reposcan = mkReposcan pkgs;
      default = pkgs.weave;
    });

    devShells = forAllSystems (pkgs: {
      default = pkgs.mkShell {
        packages = with pkgs; [
          weave # jj N-way/union merge tool (config.toml merge-tools.weave)
          mergiraf # syntax-aware 3-way merge driver (0.20 here; profile may lag)
          zoekt # zoekt-git-index + zoekt-webserver, stage-5 cross-workspace search
          universal-ctags # symbol index feeder for zoekt
          gita # batch multi-repo status (stage-1 candidate; gfold breaks on jj)
          lazyjj # jj TUI for lane/log/bookmark inspection (operator review)
          jj-fzf # fzf lane/revset picker for navigating the worktree pools
          (mkReposcan pkgs) # stage-1 dirty/unpushed/stale scanner, git+jj aware (run with --no-telemetry)
        ];
      };
    });
  };
}
