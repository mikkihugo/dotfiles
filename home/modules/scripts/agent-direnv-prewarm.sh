# agent-direnv-prewarm.sh — keep whitelisted agent roots' direnv envs prewarmed
#
# Purpose: agent shells (Kimi/Claude/Codex Bash tool) cannot run the
# direnv-instant interactive hook, so every agent `direnv export` queues on the
# repo's singleflight/nix eval. This script pre-runs the export for each
# configured root — but ONLY for roots whose snapshot is stale. Triggers:
# (a) direnv-agent kicks this service on demand when it serves a stale snapshot,
# (b) systemd path units fire on .envrc/flake.nix/flake.lock changes,
# (c) a daily janitor timer backstop. There is no fixed high-frequency timer.
#
# Contract:
# - For each root: fingerprint-compare first — unchanged, fresh snapshots skip
#   entirely (no eval, no queue).
# - Run `direnv export` in a fresh bash, capture the export SCRIPT to the
#   snapshot (never eval-inside-capture: env becomes shell state, stdout stays
#   empty — the 2026-10-27 11:33 cycle swallowed every success that way);
#   failures leave the previous snapshot untouched.
# - Snapshot layout: ~/.cache/agent-direnv/<sha256(rootpath)>/{env,fingerprint}
# - fingerprint: newline-joined name+mtime+size of .envrc, flake.nix, flake.lock
#   captured at snapshot time; `direnv-agent` compares before trusting.
# - Batch priority: niced, ionice -c3 (agent batch class).
# Consumer: direnv-agent (wrapper), agent shells on this host.
# Falsifier: a stale/failed snapshot must never be served as fresh; the
# fingerprint comparison or, failing that, the fallback re-eval proves it.

set -u

STATE_DIR="${AGENT_DIRENV_STATE:-$HOME/.cache/agent-direnv}"
SNAPSHOT_MAX_AGE_S=86400
ROOTS=(
  "/home/mhugo/code/jcode"
  "/home/mhugo/code/singularity-engine"
  "/srv/infra"
)

fingerprint() {
  local root="$1"
  for f in .envrc flake.nix flake.lock; do
    [ -e "$root/$f" ] && printf '%s %s\n' "$f" "$(stat -c '%Y %s' "$root/$f")"
  done
}

for root in "${ROOTS[@]}"; do
  [ -d "$root" ] || { echo "prewarm: skip missing root $root" >&2; continue; }
  hash=$(printf '%s' "$root" | sha256sum | cut -d' ' -f1)
  dir="$STATE_DIR/$hash"
  new_dir="$dir.new.$$"

  # Skip-if-fresh: fingerprint match + non-empty env + younger than the cap.
  current_fp=$(fingerprint "$root" || true)
  if [ -s "$dir/env" ] && [ "$current_fp" = "$(tail -n +2 "$dir/fingerprint" 2>/dev/null || true)" ]; then
    gen_at=$(tail -n +3 "$dir/fingerprint" 2>/dev/null | date -u -f - +%s 2>/dev/null || echo 0)
    [ "$gen_at" -lt $(( $(date -u +%s) - SNAPSHOT_MAX_AGE_S )) ] || { echo "prewarm: $root fresh; skip"; continue; }
  fi

  # Export capture: retry under singleflight contention within the budget.
  # Capture the export SCRIPT on stdout — never eval-inside-capture (env
  # becomes shell state; stdout stays empty; the 2026-10-27 11:33 cycle
  # swallowed every success exactly that way).
  out=""
  cycle_start=$(date +%s)
  while :; do
    out=$(timeout 180 bash -c "cd -- '$root' && DIRENV_LOG_FORMAT= direnv export bash" 2>/dev/null) || out=""
    [ -n "$out" ] && break
    [ $(( $(date +%s) - cycle_start )) -ge 420 ] && break
    sleep 30
  done
  [ -n "$out" ] || { echo "prewarm: export failed for $root after retries; keeping existing snapshot" >&2; continue; }
  after=$(current_fp)

  mkdir -p "$dir" "$new_dir"
  printf '%s\n' "$out" > "$new_dir/env"
  { printf '%s\n' "$root"; printf '%s\n' "$after"; date -u +%FT%TZ; } > "$new_dir/fingerprint"
  mv -fT "$new_dir" "$dir"
  echo "prewarm: refreshed $root -> $dir/env ($(printf '%s' "$out" | wc -c) bytes)"
done