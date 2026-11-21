# home/modules/repository-operator.nix — the host entry point for the
# repository command surface.
#
# The Engine repository operator is ONE Rust binary, built once in Engine and
# consumed by every enrolled repository from that derivation. A repository
# declares how to consume it in `.purpose/repository-operator-target.v1.json`
# and projects it into its own flake output; some repositories still ship a
# legacy generated launcher under `bin/repo`.
#
# This shim is the host's PATH entry. It resolves the delegate from the
# CALLER's repository, never from a constant:
#
#   1. the repository's own launcher, when it ships an executable one;
#   2. otherwise the Engine operator, realized from that repository's own
#      flake output (the per-repository projection of the one derivation).
#
# The previous revision resolved it as
# `REPO_BIN="$(command -v repo || true)"` and fell back to
# `<engine>/bin/repo` when the result matched itself — which is always, since
# `command -v repo` inside this script returns this script. Every caller was
# therefore handed Engine's facade against a foreign tree; a session on
# 2026-09-12 was refused with WRONG_REPO and killed mid-flight.
#
# A repository that ships no launcher keeps no launcher: the operator IS the
# surface, and it resolves the repository and admits the target itself.
# Nothing found? REFUSE. Running the wrong repository's surface is worse than
# running none.
_: {
  home.file.".local/bin/repo" = {
    source = ./repository-operator/repo;
    executable = true;
    force = true;
  };
}
