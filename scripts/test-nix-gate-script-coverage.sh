#!/usr/bin/env bash
# Contract: every non-nix script that home/modules/*.nix pulls into the
# activation package via a `${../../scripts/NAME}` interpolation must make
# scripts/repo-check.sh run the home-manager build gate.
#
# Why this exists: the gate's allow-list used to be hand-enumerated
# (^scripts/codex-preferences$|^scripts/merge-authorized-keys$). When
# home/modules/jcode-providers.nix began referencing scripts/jcode-preferences,
# that script fell outside the list, so a commit touching only it changed the
# activation package while `repo check` skipped the build entirely — a green
# check on a change that might not evaluate.
#
# Falsifier: add a `${../../scripts/whatever}` reference to any home module
# without teaching the gate about it; this test must fail.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
dirty_fixture="$root/config/.repo-check-dirty-regression-${BASHPID}"
trap 'rm -f -- "$dirty_fixture"' EXIT

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
	# The derived list is the primary way a scripts/ path is covered: the
	# structural regex matches *.nix, flake.lock and ^secrets/, never
	# ^scripts/.
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

# The full reference derivation must exist, be non-empty, and distinguish
# referenced from unreferenced config files — that distinction IS the
# optimization (docs that no module references must not run the build).
all_referenced="$(nix_gate_referenced_files)"
if [[ -z "$all_referenced" ]]; then
	echo "FAIL: nix_gate_referenced_files produced an empty set — the gate would fail open on every check" >&2
	failures=$((failures + 1))
elif ! printf '%s\n' "$all_referenced" | grep -Fxq "config/agents/purpose-backbone.md"; then
	# readFile'd by jcode-providers.nix; markdown, but referenced — must be covered
	echo "FAIL: derivation missed config/agents/purpose-backbone.md (builtins.readFile reference)" >&2
	failures=$((failures + 1))
elif printf '%s\n' "$all_referenced" | grep -Fxq "config/code/AGENTS.md"; then
	# The 2026-11-10 case: a doc no module references must NOT be covered
	echo "FAIL: derivation over-matched config/code/AGENTS.md — unreferenced docs would run the build gate" >&2
	failures=$((failures + 1))
else
	echo "ok   reference derivation distinguishes referenced from unreferenced config files"
fi
# Directory interpolation: home/modules references ./borg/ as a directory;
# the gate must cover changes under it.
if ! printf '%s\n' "$all_referenced" | grep -qx "home/modules/borg"; then
	if [[ ! -d "$root/home/modules/borg" ]]; then
		echo "ok   no directory interpolation present (borg reference gone)"
	else
		echo "FAIL: directory interpolation home/modules/borg not derived" >&2
		failures=$((failures + 1))
	fi
fi

# Skip case: an untracked doc that no module references must NOT request the
# build. This is the regression guard for the optimization itself.
touch "$dirty_fixture"
if nix_gate_needs_build; then
	echo "FAIL: unreferenced config doc triggered the nix build gate" >&2
	failures=$((failures + 1))
else
	echo "ok   unreferenced config doc skips the gate"
fi
rm -f -- "$dirty_fixture"

# Regression: a dirty REFERENCED file must still request the build even when
# the committed diff alone contains no relevant path. Uses config/ripgreprc
# (interpolated by home/modules/files.nix); content is backed up and restored.
if ! printf '%s\n' "$all_referenced" | grep -Fxq "config/ripgreprc"; then
	echo "FAIL: config/ripgreprc is no longer derived as referenced — this regression cannot run" >&2
	failures=$((failures + 1))
else
	ripgreprc_backup="$(mktemp)"
	cp "$root/config/ripgreprc" "$ripgreprc_backup"
	trap 'rm -f -- "$dirty_fixture" "$ripgreprc_backup"; cp "$ripgreprc_backup" "$root/config/ripgreprc" 2>/dev/null || true' EXIT
	printf '# nix-gate dirty regression (restored by test)\n' >>"$root/config/ripgreprc"
	if ! nix_gate_needs_build; then
		echo "FAIL: dirty referenced file skipped the nix build gate" >&2
		failures=$((failures + 1))
	else
		echo "ok   dirty referenced file requests the build"
	fi
	cp "$ripgreprc_backup" "$root/config/ripgreprc"
	if ! git -C "$root" diff --quiet -- config/ripgreprc; then
		echo "FAIL: ripgreprc restore failed — tree left dirty" >&2
		failures=$((failures + 1))
	fi
fi

if ((failures > 0)); then
	echo "$failures nix-gate coverage failure(s)" >&2
	exit 1
fi
echo "nix gate covers every module-referenced script"
