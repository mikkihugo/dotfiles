# Fleet language attrs aligned with singularity-engine/nix/toolchains/versions.json.
# Use these names in HM modules instead of pkgs.python3 / pkgs.go so nixos-26.05
# defaults (python 3.13, go 1.26) cannot drift under a generation bump.
pkgs: {
  inherit (pkgs) nodejs_26 pnpm_12 bun;
  python = pkgs.python314;
  pythonWithYaml = pkgs.python314.withPackages (ps: [ps.pyyaml]);
  go = pkgs.go_1_27;
  # nixpkgs 26.05 exposes only `bun` (no bun_1_3 suffix). opencode-swarm requires >=1.3.13.
}
