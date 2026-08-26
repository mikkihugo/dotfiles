#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

# The Nix expression is intentionally literal; it reads the root from the
# narrowly scoped child-process environment instead of interpolating Nix code.
# shellcheck disable=SC2016
matrix="$(DOTFILES_TEST_ROOT="$root" nix eval --json --impure --expr '
  let
    flake = builtins.getFlake ("path:" + builtins.getEnv "DOTFILES_TEST_ROOT");
    inspect = name:
      let cfg = flake.homeConfigurations.${name}.config;
      in {
        cargoConfig = cfg.home.file.".cargo/config.toml".text or null;
        sccacheDir = cfg.home.sessionVariables.SCCACHE_DIR or null;
        sccacheSocket = cfg.home.sessionVariables.SCCACHE_SERVER_UDS or null;
      };
  in builtins.listToAttrs (map (name: { inherit name; value = inspect name; }) [
    "cc-se-sto-devbox-01"
    "mikki-laptop"
    "mikki-bunker"
    "mhugo"
  ])
')"

jq -e '
  .["cc-se-sto-devbox-01"] == {
    cargoConfig: "[build]\nrustc-wrapper = \"rustc-sccache-shim\"\n",
    sccacheDir: "/var/cache/sccache",
    sccacheSocket: "/run/sccache/server.sock"
  }
  and all([.["mikki-laptop"], .["mikki-bunker"], .mhugo][];
    . == {cargoConfig: null, sccacheDir: null, sccacheSocket: null})
' <<<"$matrix" >/dev/null || {
	jq '{
    "cc-se-sto-devbox-01": .["cc-se-sto-devbox-01"],
    "mikki-laptop": .["mikki-laptop"],
    "mikki-bunker": .["mikki-bunker"],
    "mhugo": .mhugo
  }' <<<"$matrix" >&2
	printf 'sccache profile scope contract failed\n' >&2
	exit 1
}

printf 'sccache profile scope contract: ok\n'
