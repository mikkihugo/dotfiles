# agent-direnv-prewarm.sh — keep whitelisted agent roots' direnv envs prewarmed
#
# Purpose: agent shells (Kimi/Claude/Codex Bash tool) cannot run the
# direnv-instant interactive hook, so every agent `direnv export` queues on the
# repo's singleflight/nix eval. This script pre-runs the export for each
# configured root (through the normal, queued path — once per interval, not per
# agent call) and stores the exported env where agents can instant-eval it.
#
# Contract:
# - For each root: run `direnv export` in a fresh bash, capture stdout to the
#   snapshot; failures leave the previous snapshot untouched and record one
#   stderr note (never delete).
# - Snapshot layout: ~/.cache/agent-direnv/<sha256(rootpath)>/{env,fingerprint}
# - fingerprint: newline-joined mtimes+sizes of .envrc, flake.nix, flake.lock
#   (whichever exist) captured AT SNAPSHOT TIME; `direnv-agent` compares before
#   trusting the snapshot.
# - Batch priority: niced, ionice -c3 (agent batch class).
# Consumer: direnv-agent (wrapper), agent shells on this host.
# Falsifier: a stale/failed snapshot must never be served as fresh; the
# fingerprint comparison or, failing that, the fallback re-eval proves it.

set -u

STATE_DIR="${AGENT_DIRENV_STATE:-$HOME/.cache/agent-direnv}"
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

  # Contention-tolerant export: the repo singleflight returns quickly under
  # fleet load; retry inside the cycle's time budget. CRITICAL: capture the
  # export script itself on stdout — do NOT `eval` it inside the capture
  # (eval makes the env shell-state, never stdout; the first live cycle
  # 2026-10-27 11:33 swallowed every "successful" export exactly that way).
  out=""
  cycle_start=$(date +%s)
  while :; do
    out=$(timeout 120 bash -c "cd -- '$root' && DIRENV_LOG_FORMAT= direnv export bash" 2>/dev/null) || out=""
    [ -n "$out" ] && break
    [ $(( $(date +%s) - cycle_start )) -ge 420 ] && break
    sleep 60
  done
  [ -n "$out" ] || { echo "prewarm: export failed for $root after retries; keeping existing snapshot" >&2; continue; }
  after=$(fingerprint "$root" || true)

  mkdir -p "$dir" "$new_dir"
  printf '%s\n' "$out" > "$new_dir/env"
  { printf '%s\n' "$root"; printf '%s\n' "$after"; date -u +%FT%TZ; } > "$new_dir/fingerprint"
  mv -fT "$new_dir" "$dir"
  echo "prewarm: refreshed $root -> $dir/env ($(printf '%s' "$out" | wc -c) bytes)"
done