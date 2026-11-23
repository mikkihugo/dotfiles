#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

if grep -Eq '(^|[[:space:]])export[[:space:]]+(SCCACHE_|RUSTC_(WORKSPACE_)?WRAPPER)' "$root/shell/bash/bashrc"; then
	printf 'shell must not export sccache or Rust compiler wrapper variables\n' >&2
	exit 1
fi

# The Nix expression is intentionally literal; it reads the root from the
# narrowly scoped child-process environment instead of interpolating Nix code.
# shellcheck disable=SC2016
# shellcheck source=scripts/org2nix.sh
source "$root/scripts/org2nix.sh"
matrix="$(DOTFILES_TEST_ROOT="$root" org2nix eval --json --impure --expr '
  let
    flake = builtins.getFlake ("path:" + builtins.getEnv "DOTFILES_TEST_ROOT");
    inspect = name:
      let cfg = flake.homeConfigurations.${name}.config;
      in {
        cargoConfig = cfg.home.file.".cargo/config.toml".text or null;
        sccachePackages = builtins.filter (pkg: (pkg.pname or (builtins.parseDrvName pkg.name).name) == "sccache") cfg.home.packages;
        wrapperVariables = builtins.filter (name: name == "RUSTC_WRAPPER" || name == "RUSTC_WORKSPACE_WRAPPER" || builtins.match "SCCACHE_.*" name != null) (builtins.attrNames cfg.home.sessionVariables);
      };
  in builtins.listToAttrs (map (name: { inherit name; value = inspect name; }) [
    "cc-se-sto-devbox-01"
    "mikki-laptop"
    "mikki-bunker"
    "mhugo"
  ])
')"

# Home Manager must neither install sccache nor configure compiler wrappers.
jq -e 'all(.[]; . == {cargoConfig: null, sccachePackages: [], wrapperVariables: []})' <<<"$matrix" >/dev/null || {
	jq '{
    "cc-se-sto-devbox-01": .["cc-se-sto-devbox-01"],
    "mikki-laptop": .["mikki-laptop"],
    "mikki-bunker": .["mikki-bunker"],
    "mhugo": .mhugo
  }' <<<"$matrix" >&2
	printf 'sccache must not be configured by home-manager\n' >&2
	exit 1
}

printf 'sccache profile scope contract: ok\n'
