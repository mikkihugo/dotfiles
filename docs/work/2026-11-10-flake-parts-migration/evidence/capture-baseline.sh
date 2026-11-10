#!/usr/bin/env bash
# Captures consumer-visible flake outputs for path-equality comparison across
# the flake-parts restructure. Usage: capture-baseline.sh <out.json>
#
# The three src-carrying lint checks (format/statix/deadnix) legitimately gain
# a new flake-source input path when files are added to the repo, so their
# full derivations are captured with the src store path normalized to
# <FLAKE_SRC>; every other output must be strictly store-path identical.
set -euo pipefail
cd /home/mhugo/.dotfiles
out="$1"

home_outpaths=$(nix eval --json .#homeConfigurations \
  --apply 'x: builtins.mapAttrs (n: v: v.activationPackage.outPath) x')

x86=$(nix eval --json .#packages.x86_64-linux.home-manager.outPath)
aa64=$(nix eval --json .#packages.aarch64-linux.home-manager.outPath)
x86shell=$(nix eval --json .#devShells.x86_64-linux.default.outPath)
aa64shell=$(nix eval --json .#devShells.aarch64-linux.default.outPath)
x86fmt=$(nix eval --json .#formatter.x86_64-linux.outPath)
aa64fmt=$(nix eval --json .#formatter.aarch64-linux.outPath)
x86checks=$(nix eval --json .#checks.x86_64-linux --apply 'x: builtins.attrNames x')
aa64checks=$(nix eval --json .#checks.aarch64-linux --apply 'x: builtins.attrNames x')
x86pin=$(nix eval --json .#checks.x86_64-linux.jujutsu-pin.outPath)
aa64pin=$(nix eval --json .#checks.aarch64-linux.jujutsu-pin.outPath)
x86vultr=$(nix eval --json .#checks.x86_64-linux.vultr-cli-pin.outPath)
aa64vultr=$(nix eval --json .#checks.aarch64-linux.vultr-cli-pin.outPath)

# Normalized derivations of the src-carrying lint checks, ordered
# format, statix-check, deadnix-check per system.
norm_drvs() {
  nix derivation show "$@" | jq '
    .derivations | [ to_entries[] | .value |
      (.env.src // "") as $src |
      walk(
        if type == "string" and $src != "" then
          gsub($src; "<FLAKE_SRC>")
        else . end
        # Nix 2.35 structured srcs entries fingerprint the copied source dir
        # as "<outer-hash>-<inner-hash>-source"; normalize that form too.
        | if type == "string" then
            gsub("^[0-9a-z]{32}-[0-9a-z]{32}-source$"; "<FLAKE_SRC>")
          else . end
      ) ]
    # The out path of the drv hashes the UN-normalized src, so it can never
    # match across trees; compare everything else and blank it.
    | map(.env.out = "<OUT>" | .outputs |= with_entries(.value.path = "<OUT>"))
    | sort_by(.name)
  '
}
x86lint=$(norm_drvs \
  .#checks.x86_64-linux.format \
  .#checks.x86_64-linux.statix-check \
  .#checks.x86_64-linux.deadnix-check)
aa64lint=$(norm_drvs \
  .#checks.aarch64-linux.format \
  .#checks.aarch64-linux.statix-check \
  .#checks.aarch64-linux.deadnix-check)

jq -n \
  --argjson home "$home_outpaths" \
  --argjson x86_hm "$x86" --argjson aa64_hm "$aa64" \
  --argjson x86_shell "$x86shell" --argjson aa64_shell "$aa64shell" \
  --argjson x86_fmt "$x86fmt" --argjson aa64_fmt "$aa64fmt" \
  --argjson x86_checks "$x86checks" --argjson aa64_checks "$aa64checks" \
  --argjson x86_pin "$x86pin" --argjson aa64_pin "$aa64pin" \
  --argjson x86_vultr "$x86vultr" --argjson aa64_vultr "$aa64vultr" \
  --argjson x86_lint "$x86lint" --argjson aa64_lint "$aa64lint" \
  '{
    homeConfigurations: $home,
    "packages.home-manager": {"x86_64-linux": $x86_hm, "aarch64-linux": $aa64_hm},
    "devShells.default": {"x86_64-linux": $x86_shell, "aarch64-linux": $aa64_shell},
    formatter: {"x86_64-linux": $x86_fmt, "aarch64-linux": $aa64_fmt},
    "checks.attrNames": {"x86_64-linux": $x86_checks, "aarch64-linux": $aa64_checks},
    "checks.pin-outPaths": {
      "jujutsu-pin": {"x86_64-linux": $x86_pin, "aarch64-linux": $aa64_pin},
      "vultr-cli-pin": {"x86_64-linux": $x86_vultr, "aarch64-linux": $aa64_vultr}
    },
    "checks.lintDrvsNormalized": {"x86_64-linux": $x86_lint, "aarch64-linux": $aa64_lint}
  }' > "$out"
echo "baseline written to $out"
