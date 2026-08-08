#!/usr/bin/env bash
# Contract: every non-nix script that home/modules/*.nix pulls into the
# activation package via a `${../../scripts/NAME}` interpolation must make
# scripts/repo-check.sh run the home-manager build gate.
#
# Why this exists: the gate's allow-list used to be hand-enumerated
# (^scripts/codex-preferences$|^scripts/merge-authorized-keys$). When
# home/modules/jcode-providers.nix began referencing scripts/jcode-preferences,
# that script fell outside the list, so a commit touching only it changed the
# activation package while `just check` skipped the build entirely — a green
# check on a change that might not evaluate.
#
# Falsifier: add a `${../../scripts/whatever}` reference to any home module
# without teaching the gate about it; this test must fail.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

# Reuse the gate's own derivation and pattern so the test cannot drift from it.
# repo-check.sh is function-only when sourced (its main runs under a
# BASH_SOURCE == $0 guard), so this does not re-enter the whole check.
# shellcheck source=/dev/null
source "$root/scripts/repo-check.sh"

failures=0

# Derive the expected set INDEPENDENTLY of the gate. Iterating the gate's own
# nix_gate_referenced_scripts would be tautological: a derivation that silently
# stops matching some scripts would then satisfy the test with a shrunken list.
# Verified: narrowing the gate's grep to codex-preferences only made an earlier
# version of this test pass with one entry.
expected="$(grep -rhoE '\.\./\.\./scripts/[A-Za-z0-9_.-]+' "$root/home/modules" 2>/dev/null |
	sed -E 's#^\.\./\.\./##' | sort -u)"
if [[ -z "$expected" ]]; then
	echo "FAIL: no ../../scripts/ references found under home/modules — this test's own scan is broken" >&2
	exit 1
fi

# What the gate actually claims to cover.
referenced="$(nix_gate_referenced_scripts)"

# The gate must not cover fewer scripts than exist.
missing_from_gate="$(comm -23 <(printf '%s\n' "$expected") <(printf '%s\n' "$referenced" | sort -u))"
if [[ -n "$missing_from_gate" ]]; then
	while IFS= read -r m; do
		[[ -n "$m" ]] || continue
		printf 'FAIL: the gate does not derive %s, which home/modules references\n' "$m" >&2
		failures=$((failures + 1))
	done <<<"$missing_from_gate"
fi

while IFS= read -r script; do
	[[ -n "$script" ]] || continue
	if [[ ! -e "$root/$script" ]]; then
		echo "FAIL: home/modules references $script but it does not exist" >&2
		failures=$((failures + 1))
		continue
	fi
	# The derived list is the only thing that can cover a scripts/ path: the
	# broad nix_gate_path_re matches ^home/, ^config/, ^secrets/ and *.nix, never
	# ^scripts/. So there is no second way for one of these to be covered.
	if printf '%s\n' "$referenced" | grep -Fxq "$script"; then
		echo "ok   $script (derived)"
	else
		echo "FAIL: $script is referenced by a home module but would not trigger the nix build gate" >&2
		failures=$((failures + 1))
	fi
done <<<"$expected"

# Guard the derivation itself: a script that is NOT referenced must not be
# claimed as covered, or the gate would build on every unrelated script edit.
if printf '%s\n' "$referenced" | grep -Fxq "scripts/repo-check.sh"; then
	echo "FAIL: derivation over-matched — repo-check.sh is not a module-referenced script" >&2
	failures=$((failures + 1))
fi

if ((failures > 0)); then
	echo "$failures nix-gate coverage failure(s)" >&2
	exit 1
fi
echo "nix gate covers every module-referenced script"
