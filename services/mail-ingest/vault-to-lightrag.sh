#!/bin/bash
# Part 21: Vault → LightRAG real-time sync via inotify.
# Deployed to ai.hugo.dk:/srv/vault-to-lightrag.sh, launched via systemd.
set -euo pipefail

VAULT_HOST_DIR=${VAULT_HOST_DIR:-/opt/openclaw/data/workspace/vault}
LIGHTRAG_URL=${LIGHTRAG_URL:-http://127.0.0.1:9621}
LIGHTRAG_API_KEY_FILE=${LIGHTRAG_API_KEY_FILE:-/srv/lightrag/.env}
LIGHTRAG_API_KEY=$(grep '^LIGHTRAG_API_KEY=' "$LIGHTRAG_API_KEY_FILE" | cut -d= -f2)

log() { printf '%s [%s] %s\n' "$(date -u +%FT%TZ)" "vault-sync" "$*"; }

push() {
	local path="$1"
	[[ -f "$path" ]] || return 0
	[[ "$path" =~ \.md$ || "$path" =~ \.txt$ ]] || return 0
	local rel="${path#"${VAULT_HOST_DIR}"/}"
	local size
	size=$(stat -c%s "$path")
	((size < 16 || size > 200000)) && {
		log "skip $rel size=$size"
		return 0
	}
	log "push $rel"
	jq -n --arg text "$(cat "$path")" --arg source "vault/$rel" '{text:$text,file_source:$source}' |
		curl -sS --max-time 60 -X POST \
			-H "X-API-Key: $LIGHTRAG_API_KEY" \
			-H "Content-Type: application/json" \
			-d @- "$LIGHTRAG_URL/documents/text" >/dev/null || log "push-fail $rel"
}

log "start watching $VAULT_HOST_DIR"
# Seed with any existing files (idempotent — LightRAG dedupes by content hash)
find "$VAULT_HOST_DIR" -type f \( -name '*.md' -o -name '*.txt' \) -print0 |
	while IFS= read -r -d '' f; do push "$f"; done

# Then watch for changes
inotifywait -m -r -e close_write -e moved_to --format '%w%f' "$VAULT_HOST_DIR" |
	while IFS= read -r path; do push "$path"; done
