# Flake-level homeConfigurations. Home Manager needs its own overlayed
# nixpkgs import per system (flake/overlay.nix), so these stay at the flake
# level rather than in perSystem — one mkHome definition serves all four
# profiles on both architectures.
{
  inputs,
  withSystem,
  ...
}: let
  inherit
    (inputs)
    home-manager
    sops-nix
    llm-agents
    direnv-instant
    engine-nixpkgs-pin
    ;

  specialArgs = {
    inherit sops-nix llm-agents direnv-instant engine-nixpkgs-pin;
  };

  dotfilesOverlay = import ./overlay.nix {
    inherit (inputs) nixpkgs-unstable nixpkgs-jujutsu nixpkgs-direnv infra;
  };

  # Home Manager needs one pkgs per system. `withSystem` serves exactly
  # that: for systems the flake declares it returns the per-system results
  # (here only `pkgs`, shaped by per-system.nix's _module.args override);
  # for any other system it aborts, so a misconfigured consumer fails
  # loudly instead of importing an unconfigured nixpkgs.
  pkgsFor = system: withSystem system (args: args.pkgs);

  # Single home.nix works on all arches. targetSystem is passed as
  # specialArgs so imports can branch without referencing pkgs.
  mkHome = sys: hostname: let
    pkgs = (pkgsFor sys).extend dotfilesOverlay;
    toolchain = import ../home/lib/toolchain.nix pkgs;
    home = home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      extraSpecialArgs =
        specialArgs
        // {
          targetSystem = sys;
          inherit hostname toolchain;
        };
      modules = [
        direnv-instant.homeModules.direnv-instant
        ../home/home.nix
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
in {
  flake.homeConfigurations = {
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
}
