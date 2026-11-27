#!/usr/bin/env bash
# Exercise the entrypoint ordering and failure propagation without evaluating a checkout.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd -P)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-source-entry.XXXXXX")
mkdir -p "$tmp/helper/bin" "$tmp/bin"
cat > "$tmp/helper/bin/ergo-flake-source" <<'HELPER'
#!/usr/bin/env bash
printf 'filter %s\n' "$1" >> "$TRACE"
[[ ${FAIL_STAGE:-} != filter ]] || exit 42
printf 'path:/nix/store/fixture-filtered-source\n'
HELPER
chmod +x "$tmp/helper/bin/ergo-flake-source"
cat > "$tmp/bin/direnv" <<'DIRENV'
#!/usr/bin/env bash
exit 0
DIRENV
chmod +x "$tmp/bin/direnv"
run_entry() {
  TRACE="$tmp/trace" HELPER="$tmp/helper" FAIL_STAGE="${1:-}" PATH="$tmp/bin:$PATH" bash -c '
    watch_file() { :; }
    source_env() { :; }
    nix() { printf "build %s\n" "$*" >> "$TRACE"; [[ $FAIL_STAGE != build ]] || return 41; printf "%s\n" "$HELPER"; }
    use() { printf "use %s\n" "$*" >> "$TRACE"; [[ $FAIL_STAGE != use ]] || return 43; }
    source "$1"
  ' _ "$root/.envrc"
}
: > "$tmp/trace"
run_entry
mapfile -t trace < "$tmp/trace"
[[ ${#trace[@]} == 3 && ${trace[0]} == 'build build --impure --no-link --print-out-paths --file tools/flake-source-helper/default.nix' && ${trace[1]} == 'filter '* && ${trace[2]} == 'use flake path:/nix/store/fixture-filtered-source' ]]
for stage in build filter use; do
  : > "$tmp/trace"
  if run_entry "$stage"; then echo "expected $stage failure" >&2; exit 1; fi
  if [[ $stage != use ]] && grep -q '^use ' "$tmp/trace"; then echo "evaluated after $stage failure" >&2; exit 1; fi
done
