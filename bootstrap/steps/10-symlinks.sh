#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"/../.. && pwd)"
PROFILE=${1:?profile required}
MANIFEST="$ROOT_DIR/profiles/$PROFILE/links.json"

if [[ ! -f "$MANIFEST" ]]; then
  echo "Missing manifest: $MANIFEST" >&2
  exit 1
fi

BACKUP_DIR="${DOTFILES_BACKUP_DIR:-$HOME/.dotfiles-backup-$(date +%Y%m%d-%H%M%S)}"
export DOTFILES_BACKUP_DIR="$BACKUP_DIR"
mkdir -p "$BACKUP_DIR"

python3 - "$ROOT_DIR" "$MANIFEST" <<'PY'
import json
import os
import shutil
import sys
from pathlib import Path

root = Path(sys.argv[1]).resolve()
manifest = Path(sys.argv[2]).resolve()
home = Path.home()
backup_dir = Path(os.environ["DOTFILES_BACKUP_DIR"]).resolve()

data = json.loads(manifest.read_text())
links = data.get("links", {})

for raw_target, raw_source in links.items():
    target = Path(os.path.expandvars(raw_target)).expanduser()
    source = (root / raw_source).resolve()

    if not source.exists():
        raise FileNotFoundError(f"Source missing: {source}")

    target.parent.mkdir(parents=True, exist_ok=True)

    needs_link = True
    if target.exists() or target.is_symlink():
        try:
            if target.samefile(source):
                needs_link = False
        except FileNotFoundError:
            pass

        if needs_link:
            try:
                rel = target.relative_to(home)
                backup_path = backup_dir / rel
            except ValueError:
                backup_path = backup_dir / target.name

            backup_path.parent.mkdir(parents=True, exist_ok=True)
            if backup_path.exists():
                backup_path.unlink()
            target.rename(backup_path)

    if needs_link:
        if target.exists() or target.is_symlink():
            if target.is_dir() and not target.is_symlink():
                shutil.rmtree(target)
            else:
                target.unlink()
        target.symlink_to(source)
        print(f"linked {target} -> {source}")
PY
