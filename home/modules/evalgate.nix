# evalgate — fleet lock gate (see tools/evalgate/README.md).
# Built with gomod2nix (ADR-0097 *2nix doctrine): per-dep derivations via the
# generated deps.nix. Regenerate after any go.mod change:
#   nix run github:nix-community/gomod2nix -- generate   (in tools/evalgate)
# Freshness falsifier: a dep bump without regenerating gomod2nix.toml must
# fail tools/evalgate/check-deps-fresh.sh (wired into repo test).
{pkgs, ...}: {
  home.packages = [
    (pkgs.buildGoApplication {
      pname = "evalgate";
      version = "0.1.0";
      src = ../../tools/evalgate;
      modules = ../../tools/evalgate/gomod2nix.toml;
      ldflags = ["-s" "-w"];
    })
  ];
}
