#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
profile="${HOME_MANAGER_PROFILE:-cc-se-sto-devbox-01}"
activation_path="$(
	nix build --no-link --print-out-paths \
		"path:${repo_root}#homeConfigurations.${profile}.activationPackage"
)"
shim="${activation_path}/home-files/.local/bin/sg"
session_vars="${activation_path}/home-path/etc/profile.d/hm-session-vars.sh"

test -x "$shim"
"$shim" --version | grep -F 'ast-grep'

test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT
managed_home="${test_dir}/home"
mkdir -p "${managed_home}/.local/bin"
ln -s "$shim" "${managed_home}/.local/bin/sg"

resolved_sg="$(
	HOME="$managed_home" PATH="/run/wrappers/bin:/run/current-system/sw/bin" \
		bash --noprofile --norc -c '
      unset __HM_SESS_VARS_SOURCED
      . "$1"
      command -v sg
    ' bash "$session_vars"
)"
test "$resolved_sg" = "${managed_home}/.local/bin/sg"

HOME="$managed_home" PATH="/run/wrappers/bin:/run/current-system/sw/bin" \
	bash --noprofile --norc -c '
    unset __HM_SESS_VARS_SOURCED
    . "$1"
    sg --version
  ' bash "$session_vars" | grep -F 'ast-grep'

printf 'const answer = 42;\n' >"${test_dir}/sample.js"
# shellcheck disable=SC2016 # ast-grep metavariables must remain literal.
"$shim" run --pattern 'const $NAME = $VALUE' --lang javascript \
	"${test_dir}/sample.js" | grep -F 'const answer = 42'

grep -Fx 'export LANG="C.UTF-8"' "$session_vars"
grep -Fx 'export LC_ALL="C.UTF-8"' "$session_vars"
