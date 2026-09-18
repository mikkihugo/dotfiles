#!@bash@
# shellcheck shell=bash disable=SC1008,SC2239
set -euo pipefail

hook=/home/mhugo/.local/share/purpose-tool/hooks/session-start.mjs
[[ ! -f "$hook" ]] && exit 0
exec @node@ "$hook"
