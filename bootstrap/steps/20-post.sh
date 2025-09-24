#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"/../.. && pwd)"

if [[ -x "$ROOT_DIR/tasks/run" ]]; then
  "$ROOT_DIR/tasks/run" doctor || true
fi
