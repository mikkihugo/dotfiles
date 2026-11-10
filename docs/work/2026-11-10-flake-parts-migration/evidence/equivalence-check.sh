#!/usr/bin/env bash
# T1 contract test: structural assertion (flake-parts present, flake-utils gone)
# + full consumer-output equivalence vs baseline-outputs.json.
# Exits non-zero on the pre-change flake (structural part) and on any
# post-change output path mismatch.
set -euo pipefail
cd /home/mhugo/.dotfiles
evdir=docs/work/2026-11-10-flake-parts-migration/evidence

fail=0

# --- Structural assertions (fail first on the pre-change flake) ---
root_fu=$(jq -r '.nodes.root.inputs["flake-utils"] // empty' flake.lock)
if [ -n "$root_fu" ] || grep -qE 'flake-utils\.url|eachDefaultSystem' flake.nix; then
  echo "FAIL: flake-utils still referenced by root flake"
  fail=1
fi
fp_node=$(jq -r '.nodes.root.inputs["flake-parts"] // empty' flake.lock)
if [ -z "$fp_node" ]; then
  echo "FAIL: root flake has no flake-parts input"
  fail=1
else
  follows=$(jq -rc --arg n "$fp_node" '.nodes[$n].inputs["nixpkgs-lib"] // "none"' flake.lock)
  if [ "$follows" != '"nixpkgs"' ] && [ "$follows" != '["nixpkgs"]' ]; then
    echo "FAIL: root flake-parts nixpkgs-lib input follows '$follows', expected '\"nixpkgs\"'"
    fail=1
  fi
fi
if ! grep -q 'flake-parts.lib.mkFlake' flake.nix; then
  echo "FAIL: flake.nix does not use flake-parts.lib.mkFlake"
  fail=1
fi

# --- Modular layout assertions (R3) ---
for f in flake/default.nix flake/per-system.nix flake/home-configurations.nix flake/overlay.nix; do
  if [ ! -f "$f" ]; then
    echo "FAIL: missing module file $f"
    fail=1
  fi
done
if ! grep -q 'imports = \[./flake\]' flake.nix; then
  echo "FAIL: flake.nix does not import ./flake"
  fail=1
fi
if grep -qE 'eachDefaultSystem|genAttrs' flake.nix; then
  echo "FAIL: flake.nix still contains inline per-system wiring"
  fail=1
fi
systems=$(nix eval --json .#devShells --apply 'x: builtins.attrNames x' 2>/dev/null || echo '[]')
if [ "$systems" != '["aarch64-linux","x86_64-linux"]' ] && [ "$systems" != '["x86_64-linux","aarch64-linux"]' ]; then
  echo "FAIL: unexpected flake-parts systems list: $systems"
  fail=1
fi

# --- Output equivalence vs baseline ---
bash "$evdir/capture-baseline.sh" "$evdir/post-outputs.json"

# Tree-insensitive outputs must match the PRE-CHANGE baseline byte for
# byte. homeConfigurations embed the flake source tree by design (the
# repo's home modules reference tree paths), so ANY file addition moves
# their outPaths; they are proven against the same-tree old-mechanism
# reference instead (see reference-mkhome.nix).
diffout=$(diff -u <(jq -S 'del(.homeConfigurations)' "$evdir/baseline-outputs.json") \
  <(jq -S 'del(.homeConfigurations)' "$evdir/post-outputs.json") || true)
if [ -n "$diffout" ]; then
  echo "FAIL: non-home output paths diverge from baseline:"
  echo "$diffout"
  fail=1
fi

ref=$(nix eval --json --impure --expr "import $evdir/reference-mkhome.nix" 2>"$evdir/reference-mkhome.stderr")
flakehomes=$(nix eval --json .#homeConfigurations --apply 'x: builtins.mapAttrs (n: v: v.activationPackage.outPath) x')
homediFF=$(diff -u <(echo "$ref" | jq -S .) <(echo "$flakehomes" | jq -S .) || true)
if [ -n "$homediFF" ]; then
  echo "FAIL: homeConfigurations diverge from same-tree old-mechanism reference:"
  echo "$homediFF"
  fail=1
fi

if [ "$fail" -eq 0 ]; then
  echo "PASS: flake-parts wiring in place; all consumer outputs store-path-identical to baseline"
fi
exit "$fail"
