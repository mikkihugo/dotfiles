#!/bin/bash
# Daily datanode-db PostgreSQL backup → Hetzner Storage Box.
#
# Deployed to: wf.portal.centralcloud.com:/usr/local/bin/datanode-db-backup.sh (cron @ 03:30 UTC).
# Requires: /root/.ssh/personal_admin_id_ed25519 + ~/.ssh/config host alias
# "storagebox" pointing at u579183.your-storagebox.de:23.
set -euo pipefail
DATE=$(date +%F)
TMP=$(mktemp /tmp/datanode-db-backup.XXXXXX.sql.gz)
REMOTE="backups/wf.portal/datanode-db/${DATE}.sql.gz"
trap 'rm -f "$TMP"' EXIT
docker exec datanode-db pg_dump -U openclaw -Fc openclaw | gzip >"$TMP"
[ -s "$TMP" ] || {
	echo "ERROR: empty dump" >&2
	exit 1
}
sftp -b - storagebox <<EOF
put $TMP $REMOTE
EOF
echo "uploaded $(du -h "$TMP" | cut -f1) → $REMOTE"
