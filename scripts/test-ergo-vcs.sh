#!/usr/bin/env bash
# Purpose: pin the repository's single VCS surface. The Bash facade
#   (`scripts/repo-vcs.sh` and its contract battery) is retired: the native
#   operator (`ergo`) is the only VCS surface this repository exposes.
# Consumer: scripts/repo-check.sh (the dotfiles publish gate).
# Failure boundary: a retired facade or a second VCS spelling creeps back into
#   a consumer file, two surfaces drift, and an agent picks the wrong one.
# Falsifier: re-add `scripts/repo-vcs.sh`, or point a consumer file at
#   `repo vcs` / `repo lane` / `bin/repo` again, and this must fail.
#
# Hermetic and offline by construction: it reads repository files and greps
# them. No network, no `nix build`, no Forgejo, no OpenBao, no credentials.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

failures=0
fail() {
	printf 'FAIL: %s\n' "$1" >&2
	failures=$((failures + 1))
}
ok() {
	printf 'ok   %s\n' "$1"
}

marker="$root/.purpose/repository-operator-target.v1.json"

# (a) Exactly ONE VCS surface exists: the Bash facade is gone.
for retired in scripts/repo-vcs.sh scripts/test-repo-vcs.sh; do
	if [[ -e "$root/$retired" ]]; then
		fail "$retired still exists; the native operator is the only VCS surface"
	else
		ok "$retired is gone"
	fi
done

# (b) The repository declares the native operator target marker, and it names
#     the jj-native backend.
if [[ ! -f "$marker" ]]; then
	fail "$marker is missing; the repository must declare its operator target"
else
	ok "$marker exists"
	backend="$(sed -n 's/.*"backend"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$marker" | head -1)"
	if [[ "$backend" == "jj-native" ]]; then
		ok "operator target declares backend jj-native"
	else
		fail "operator target declares backend '${backend:-<none>}', expected jj-native"
	fi
fi

# (c) The flake publishes the operator as `packages.<system>.ergo` for the host
#     system. The attribute is built by flake-utils `eachDefaultSystem`, so the
#     per-system shape is asserted inside that block.
host_system="$(uname -m)-linux"
case "$(uname -s)" in
Darwin) host_system="$(uname -m)-darwin" ;;
esac
if grep -Eq 'packages[[:space:]]*=[[:space:]]*\{' "$root/flake.nix" &&
	grep -Eq 'ergo[[:space:]]*=[[:space:]]*singularity-engine\.packages\.\$\{sys\}\.ergo;' "$root/flake.nix"; then
	ok "flake publishes the operator as packages.<system>.ergo"
else
	fail "flake does not publish the operator as packages.<system>.ergo"
fi
if grep -Eq 'eachDefaultSystem' "$root/flake.nix"; then
	ok "flake publishes the operator for every default system (host: $host_system)"
else
	fail "flake does not publish the operator through eachDefaultSystem"
fi

# (d) The marker declares the operator command contract digest, pinned to a
#     sha256 of 64 lowercase hex characters.
digest="$(sed -n 's/.*"command_contract_digest"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$marker" | head -1)"
if [[ "$digest" =~ ^sha256:[0-9a-f]{64}$ ]]; then
	ok "operator target declares a sha256 command contract digest"
else
	fail "operator target command contract digest '${digest:-<none>}' is not sha256:<64 lowercase hex>"
fi

# (e) No consumer file still references the retired facade. `docs/work/**` is
#     historical evidence bundles — they record what was true when the work
#     happened and are never edited to match the current surface.
#
#     Two narrow exceptions, each a reference to the retired name that is not
#     an instruction to use it:
#       - `docs/adr/005-*.md` — a historical ADR; it records the decision that
#         produced the current surface, so it is evidence, not a consumer.
#       - `home/modules/repository-operator.nix` — the activation that RETIRES
#         the host `~/.local/bin/repo` shim names that path on purpose, and
#         its header comment explains the bug that retirement fixed.
retired_pattern='repo-vcs\.sh|repo vcs |repo lane |bin/repo'
offenders="$(
	grep -rnE "$retired_pattern" "$root" \
		--exclude-dir=.git \
		--exclude-dir=.jj \
		--exclude-dir=archive \
		--exclude-dir=work \
		--exclude='test-ergo-vcs.sh' \
		2>/dev/null |
		grep -v "/docs/work/" |
		grep -v "/docs/adr/005-devshell-shell-variable-collisions.md:" |
		grep -v "/home/modules/repository-operator.nix:" || true
)"
if [[ -n "$offenders" ]]; then
	fail "files still reference the retired VCS facade:"
	printf '%s\n' "$offenders" | sed 's/^/    /' >&2
else
	ok "no consumer file references the retired VCS facade"
fi

if ((failures > 0)); then
	printf 'ergo VCS surface contract failure(s): %d\n' "$failures" >&2
	exit 1
fi
printf 'PASS: the native ergo operator is the only VCS surface\n'
