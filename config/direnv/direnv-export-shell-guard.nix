# Wrap upstream direnv so bare `direnv export` fails with actionable CLI errors.
# Vendored from centralcloud/infra hosts/_shared (keep in sync on guard changes).
{
  lib,
  writeShellScriptBin,
  direnv,
}: let
  guard = lib.cleanSource ./direnv-export-shell-guard.sh;
in
  writeShellScriptBin "direnv" ''
    # shellcheck source=/dev/null
    source ${guard}
    direnv_export_shell_guard "$@" || exit $?
    exec ${direnv}/bin/direnv "$@"
  ''
