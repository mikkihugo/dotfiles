# Flake module wiring for all dotfiles outputs. Imported by flake.nix via
# flake-parts (imports = [./flake]); each output family lives in its own
# file so an edit to one family never touches another's module.
{inputs, ...}: {
  systems = ["aarch64-linux" "x86_64-linux"];

  # Per-system outputs (formatter, checks, packages, devShells) plus the
  # shared per-system nixpkgs configuration.
  perSystem.imports = [
    ./per-system.nix
    ({system, ...}: {
      # One configured nixpkgs import per system (allowUnfree, no dotfiles
      # overlay), shared by the maintenance outputs and — via withSystem in
      # home-configurations.nix — the home configurations. A second import
      # differing only by file id would break `nix path-info --requisites`
      # deduplication for consumers of both output families.
      _module.args.pkgs = import inputs.nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
      # flake=false inputs have no per-system projection (inputs' refuses
      # them), so the jujutsu pin check receives the pinned source explicitly.
      _module.args.nixpkgs-jujutsu-src = inputs.nixpkgs-jujutsu;
    })
  ];

  # Flake-level outputs (homeConfigurations).
  imports = [./home-configurations.nix];
}
