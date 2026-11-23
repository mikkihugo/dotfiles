# home/modules/repository-operator.nix — the host entry point for the
# repository command surface.
#
# The Engine repository operator is ONE Rust binary, built once in Engine and
# consumed by every enrolled repository from that derivation. A repository
# declares how to consume it in `.purpose/repository-operator-target.v1.json`
# and projects it into its own flake output.
#
# `~/.local/bin/ergo` is a small Go launcher (tools/ergo-launcher). It
# resolves the delegate from the CALLER's repository and execs it:
#
#   1. the operator the checkout's direnv exported
#      (REPOSITORY_OPERATOR_BIN, or REPOSITORY_MANAGER_BIN until the rename
#      lands everywhere);
#   2. otherwise the store path cached for (repository root, flake.lock
#      digest), reused while it still exists;
#   3. otherwise one build of that repository's own operator output, cached.
#
# The previous revision resolved the delegate with
# `nix eval --raw path:$root#packages.<system>` — a full flake evaluation
# whose attribute listing it then matched against — followed by
# `nix build path:$root#<attr>`. BOTH ran on every single call, so every
# agent that invoked the host entry point started a Nix client, and under
# store contention the evaluation lock turned those calls into multi-hour
# hangs. The launcher never lists attributes and never builds on `--help`.
#
# The previous revision also resolved the delegate as
# `REPO_BIN="$(command -v repo || true)"` and fell back to
# `<engine>/bin/repo` when the result matched itself — which is always, since
# `command -v repo` inside this script returns this script. Every caller was
# therefore handed Engine's facade against a foreign tree; a session on
# 2026-09-12 was refused with WRONG_REPO and killed mid-flight. The launcher
# skips an export that points at itself.
#
# A repository that ships no launcher keeps no launcher: the operator IS the
# surface, and it resolves the repository and admits the target itself.
# Nothing found? REFUSE. Running the wrong repository's surface is worse than
# running none.
{
  config,
  ergoLauncher,
  ...
}: {
  # The operator binary, correct in EVERY repository shell on this host.
  #
  # It points at the host entry, not at `lib.getExe ergo`. Both name the same
  # operator, but the store path would put singularity-engine.packages.ergo
  # into the home profile closure, so every `hms` had to realize a full Rust
  # operator build before it could activate (measured 40+ minutes under fleet
  # load). The entry is a small binary, so the closure stays free of the
  # operator and the delegate is resolved lazily, once per repository.
  #
  # A shell that pins a specific operator (infra's .envrc, from its pinned
  # Engine input) still shadows this with its own concrete store path; that is
  # the more specific setting and it stays correct.
  home.sessionVariables.REPOSITORY_OPERATOR_BIN = "${config.home.homeDirectory}/.local/bin/ergo";
  #
  # `ergo` is the operator's name and the host entry's name. There is no
  # `repo` host entry: the operator renamed the surface, and a second name
  # for the same binary is a second thing to keep in sync.
  home.file.".local/bin/ergo" = {
    source = "${ergoLauncher}/bin/ergo-launcher";
    executable = true;
    force = true;
  };
}
