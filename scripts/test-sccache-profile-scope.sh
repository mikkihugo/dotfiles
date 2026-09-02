#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
ace_repo="${ACE_REPO:-/home/mhugo/code/ace-coder}"
inspect_bunker=0
if [[ -d "$ace_repo/.git" || -d "$ace_repo/.jj" ]]; then
	inspect_bunker=1
else
	printf 'sccache profile scope: skipped mikki-bunker (ace-coder checkout absent at %s)\n' "$ace_repo"
fi

# The Nix expression is intentionally literal; it reads the root from the
# narrowly scoped child-process environment instead of interpolating Nix code.
# mikki-bunker imports ace-coder via git+file; evaluating it on a host without
# that checkout fails before the sccache assertions can run.
# shellcheck disable=SC2016
matrix="$(
	DOTFILES_TEST_ROOT="$root" DOTFILES_TEST_INSPECT_BUNKER="$inspect_bunker" nix eval --json --impure --expr '
  let
    flake = builtins.getFlake ("path:" + builtins.getEnv "DOTFILES_TEST_ROOT");
    inspectBunker = builtins.getEnv "DOTFILES_TEST_INSPECT_BUNKER" == "1";
    inspect = name:
      let cfg = flake.homeConfigurations.${name}.config;
      in {
        cargoConfig = cfg.home.file.".cargo/config.toml".text or null;
        sccacheDir = cfg.home.sessionVariables.SCCACHE_DIR or null;
        sccacheSocket = cfg.home.sessionVariables.SCCACHE_SERVER_UDS or null;
      };
    names = [
      "cc-se-sto-devbox-01"
      "mikki-laptop"
      "mhugo"
    ] ++ (if inspectBunker then [ "mikki-bunker" ] else []);
  in builtins.listToAttrs (map (name: { inherit name; value = inspect name; }) names)
'
)"

jq -e '
  .["cc-se-sto-devbox-01"] == {
    cargoConfig: "[build]\nrustc-wrapper = \"rustc-sccache-shim\"\n",
    sccacheDir: "/var/cache/sccache",
    sccacheSocket: "/run/sccache/server.sock"
  }
  and all([.["mikki-laptop"], .mhugo][];
    . == {cargoConfig: null, sccacheDir: null, sccacheSocket: null})
  and (
    (.["mikki-bunker"] | not)
    or (.["mikki-bunker"] == {cargoConfig: null, sccacheDir: null, sccacheSocket: null})
  )
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
