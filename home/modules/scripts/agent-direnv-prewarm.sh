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
EXPORT_TIMEOUT_S="${AGENT_DIRENV_EXPORT_TIMEOUT_S:-600}"
EXPORT_BUDGET_S="${AGENT_DIRENV_EXPORT_BUDGET_S:-1200}"
EVAL_LOCK="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/codex-fleet-nix-evaluation.lock"
ROOTS=(
  "/home/mhugo/code/jcode"
  "/home/mhugo/code/singularity-engine"
  "/srv/infra"
)

# Single-line fingerprint: entries space-joined, no trailing newline. Both
# producer and consumer must build the string identically (or via $( ) so
# trailing-newline stripping cannot diverge them).
fingerprint() {
  local root="$1"
  local out=""
  for f in .envrc flake.nix flake.lock; do
    [ -e "$root/$f" ] && out="$out$(printf '%s %s ' "$f" "$(stat -c '%Y %s' "$root/$f")")"
  done
  printf '%s' "$out"
}

for root in "${ROOTS[@]}"; do
  [ -d "$root" ] || { echo "prewarm: skip missing root $root" >&2; continue; }
  hash=$(printf '%s' "$root" | sha256sum | cut -d' ' -f1)
  dir="$STATE_DIR/$hash"
  new_dir="$dir.new.$$"

  # Skip-if-fresh: fingerprint match + non-empty env + younger than the cap.
  current_fp=$(fingerprint "$root" || true)
  if [ -s "$dir/env" ] && [ "$current_fp" = "$(sed '1d;$d' "$dir/fingerprint" 2>/dev/null || true)" ]; then
    gen_at=$(tail -n 1 "$dir/fingerprint" 2>/dev/null || echo 0)
    gen_epoch=$(date -u -d "$gen_at" +%s 2>/dev/null || echo 0)
    [ "$gen_epoch" -lt $(( $(date -u +%s) - SNAPSHOT_MAX_AGE_S )) ] || { echo "prewarm: $root fresh; skip"; continue; }
  fi

  fleet_helper="${HOME}/.dotfiles/shell/bash/agent-direnv-fleet-v2-apply.sh"
  if [ -f "$fleet_helper" ]; then
    # shellcheck source=/dev/null
    . "$fleet_helper"
    if agent_direnv_fleet_v2_write_snapshot "$root" "$new_dir"; then
      rm -rf "$dir"
      mv "$new_dir" "$dir"
      echo "prewarm: hydrated $root from fleet v2 -> $dir/env ($(wc -c <"$dir/env") bytes)"
      continue
    fi
    rm -rf "$new_dir"
    new_dir="$dir.new.$$"
  fi

  # Export capture: retry under singleflight contention within the budget.
  # Capture the export SCRIPT on stdout — never eval-inside-capture (env
  # becomes shell state; stdout stays empty; the 2026-10-27 11:33 cycle
  # swallowed every success exactly that way).
  out=""
  cycle_start=$(date +%s)
  attempt=0
  while :; do
    attempt=$((attempt + 1))
    elapsed=$(( $(date +%s) - cycle_start ))
    echo "prewarm: export attempt $attempt for $root (${elapsed}s / ${EXPORT_BUDGET_S}s budget); waiting for eval lock (up to ${EXPORT_TIMEOUT_S}s)..." >&2
    stderr_file="$(mktemp "${TMPDIR:-/tmp}/agent-direnv-prewarm.XXXXXX")"
    out=$(
      flock -w "$EXPORT_TIMEOUT_S" "$EVAL_LOCK" \
        timeout "$EXPORT_TIMEOUT_S" bash -c "cd -- '$root' && DIRENV_LOG_FORMAT= direnv export bash" 2>"$stderr_file"
    ) || out=""
    if [ -s "$stderr_file" ]; then
      sed 's/^/prewarm: direnv: /' "$stderr_file" >&2
    fi
    rm -f "$stderr_file"
    [ -n "$out" ] && break
    [ "$elapsed" -ge "$EXPORT_BUDGET_S" ] && break
    echo "prewarm: export produced no script for $root; retry in 30s (lock contention or nix still evaluating)" >&2
    sleep 30
  done
  [ -n "$out" ] || { echo "prewarm: export failed for $root after retries; keeping existing snapshot" >&2; continue; }
  after=$(fingerprint "$root" || true)

  mkdir -p "$new_dir"
  printf '%s\n' "$out" > "$new_dir/env"
  { printf '%s\n' "$root"; printf '%s\n' "$after"; date -u +%FT%TZ; } > "$new_dir/fingerprint"
  rm -rf "$dir"
  mv "$new_dir" "$dir"
  echo "prewarm: refreshed $root -> $dir/env ($(printf '%s' "$out" | wc -c) bytes)"
done