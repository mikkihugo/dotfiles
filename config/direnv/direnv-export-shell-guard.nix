# Wrap upstream direnv so bare `direnv export` fails with actionable CLI errors.
#
# Vendored from centralcloud/infra hosts/_shared/direnv-export-shell-guard.nix.
# scripts/test-infra-guard-drift.sh fails the publish gate when infra's
# canonical copy changes.
#
# Why vendored instead of consumed as a flake input: a `path:/srv/infra`
# input made every dotfiles build evaluate infra's entire flake (all outputs,
# `checks` included) and copy its 253k-file tree into the store, so an
# in-flight edit in another repo broke publication here.
#
# The wrapper's store path carries a version (direnv-<version>) so it matches
# the naming every other package in the fleet PATH uses. The binary itself
# stays named `direnv`, because that name is the CLI contract:
# programs.direnv resolves the executable through `lib.getExe cfg.package`,
# which reads meta.mainProgram, and the shell guard is called as `direnv`.
#
# Why this matters: a plain writeShellScriptBin names its output after the
# script alone (`...-direnv`), so a store-path naming assertion for
# `-direnv-` could never pass while the guard existed. Versioning the output
# fixes the contract without loosening it, and without renaming the
# executable every caller uses.
#
# The version is a parameter, not `direnv.version`: the guard is installed by
# an overlay that can wrap an already-guarded package, and writeTextFile
# output carries no `version` attribute. Reading `direnv.version` there fails
# with "attribute 'version' missing" while evaluating the host config. The
# default reads the wrapped package's version when it has one, and otherwise
# derives it from the wrapped store path name.
#
# The shebang is mandatory, not decoration. writeTextFile writes the text
# verbatim and adds no `#!` line, where writeShellScriptBin used to prepend
# one. direnv-instant execs `direnv` with a bare execve and has no shell
# fallback, so a shebang-less wrapper fails with ENOEXEC ("Exec format
# error") wherever the system PATH resolves it before the Nix store copy.
{
  lib,
  bash,
  writeTextFile,
  direnv,
  direnvVersion ? null,
}: let
  guard = lib.cleanSource ./direnv-export-shell-guard.sh;

  # The wrapped package's version, however it is spelled.
  #
  # `direnv.version` is absent when the wrapped package is itself a
  # writeTextFile wrapper. Its store path then ends in `-direnv-<version>`,
  # so the version is recoverable from the name.
  storePathVersion = let
    base = baseNameOf (lib.getName direnv);
    match = builtins.match ".*-direnv-([0-9].*)" base;
  in
    if match == null
    then "unversioned"
    else builtins.head match;

  wrappedVersion =
    if direnvVersion != null
    then direnvVersion
    else direnv.version or storePathVersion;

  version =
    if wrappedVersion == ""
    then "unversioned"
    else wrappedVersion;
in
  writeTextFile {
    name = "direnv-${version}";
    executable = true;
    destination = "/bin/direnv";
    text = ''
      #!${lib.getExe bash}
      # shellcheck source=/dev/null
      source ${guard}
      direnv_export_shell_guard "$@" || exit $?
      exec ${direnv}/bin/direnv "$@"
    '';
    meta.mainProgram = "direnv";
  }
