#!/bin/bash
# Daily openclaw workspace backup → Hetzner Storage Box.
#
# Deployed to: ai.hugo.dk:/usr/local/bin/openclaw-backup.sh (cron @ 02:30 UTC).
# Requires: /root/.ssh/personal_admin_id_ed25519 + ~/.ssh/config host alias
# "storagebox" pointing at u579183.your-storagebox.de:23.
set -euo pipefail
DATE=$(date +%F)
TMP=$(mktemp /tmp/openclaw-backup.XXXXXX.tar.gz)
REMOTE="backups/ai.hugo.dk/openclaw/${DATE}.tar.gz"
trap 'rm -f "$TMP"' EXIT
docker exec openclaw tar --ignore-failed-read -czf - -C /home/node/.openclaw . >"$TMP" 2>/dev/null || true
[ -s "$TMP" ] || {
	echo "ERROR: empty tarball" >&2
	exit 1
}
sftp -b - storagebox <<EOF
put $TMP $REMOTE
EOF
echo "uploaded $(du -h "$TMP" | cut -f1) → $REMOTE"
