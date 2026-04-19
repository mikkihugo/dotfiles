#!/bin/bash
# Wrapper that sources env (never checked in with secrets) and runs the ingester.
# Expected env vars (provide via /etc/default/mikki-ingest or systemd EnvironmentFile):
#   MAIL_USER=mikki@hugo.dk
#   MAILBOX=INBOX
#   DB_URL=postgresql://USER:PASSWORD@HOST:PORT/DB
#   DOVECOT_CONTAINER=mailcowdockerized-dovecot-mailcow-1
set -a
# shellcheck source=/dev/null
[ -f /etc/default/mikki-ingest ] && . /etc/default/mikki-ingest
set +a
: "${MAIL_USER:?MAIL_USER not set}"
: "${DB_URL:?DB_URL not set}"
: "${DOVECOT_CONTAINER:?DOVECOT_CONTAINER not set}"
exec python3 -u /srv/dovecot-ingest-mikki.py
