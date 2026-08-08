#!/usr/bin/env bash
# Prune Codex subagent rollouts. DRY RUN unless --apply is passed.
#
# Codex has NO retention for ~/.codex/sessions. Verified 2026-08-08 against the
# published config reference: history.persistence and history.max_bytes govern
# history.jsonl only, and `codex archive|delete` take a single session each.
# `codex doctor` reports the size and does nothing about it. On this host the
# tree reached 12.8 GB across 4.6k files, growing ~460 MB/day.
#
# Policy: delete only rollouts whose session_meta payload.source is a subagent
# (source is an object like {"subagent": ...}; real sessions have a plain string
# "cli" / "vscode" / "exec") AND whose mtime is older than AGE_DAYS. mtime, not
# creation date, so a recently resumed old session is kept.
#
# Measured 2026-08-08: subagent rollouts are ~66% of the tree by size, and a
# 7-day window reclaimed 6.08 GB across 2,860 files while every cli/vscode/exec
# session survived. A 30-day window reclaimed only 0.27 GB -- the data is young,
# so the window matters more than it looks.
set -euo pipefail

AGE_DAYS="${CODEX_ROLLOUT_GC_AGE_DAYS:-7}"
APPLY=0
[ "${1:-}" = "--apply" ] && APPLY=1

exec "${PYTHON:-python3}" - "$AGE_DAYS" "$APPLY" <<'PY'
import json, os, sys, time

age_days = int(sys.argv[1])
apply_changes = sys.argv[2] == "1"
root = os.path.expanduser("~/.codex/sessions")
cutoff = time.time() - age_days * 86400

victims, freed, total, total_bytes = [], 0, 0, 0
for dirpath, _dirs, files in os.walk(root):
    for name in files:
        if not name.endswith(".jsonl"):
            continue
        path = os.path.join(dirpath, name)
        try:
            st = os.stat(path)
        except OSError:
            continue
        total += 1
        total_bytes += st.st_size
        try:
            with open(path, encoding="utf-8", errors="replace") as fh:
                meta = json.loads(fh.readline())
            source = meta.get("payload", {}).get("source")
        except Exception:
            continue  # unreadable header: keep, never guess
        if isinstance(source, dict) and "subagent" in source and st.st_mtime < cutoff:
            victims.append(path)
            freed += st.st_size

print("scanned  %d rollouts, %.2f GB" % (total, total_bytes / 2**30))
print("policy   subagent AND mtime older than %d days" % age_days)
print("matched  %d rollouts, %.2f GB" % (len(victims), freed / 2**30))

if not apply_changes:
    print("\nDRY RUN. Re-run with --apply to delete.")
    raise SystemExit(0)

removed = errors = 0
for path in victims:
    try:
        os.remove(path)
        removed += 1
    except OSError:
        errors += 1
for dirpath, dirs, files in os.walk(root, topdown=False):
    if not dirs and not files:
        try:
            os.rmdir(dirpath)
        except OSError:
            pass
print("\ndeleted  %d rollouts, %.2f GB freed, %d errors" % (removed, freed / 2**30, errors))
PY
