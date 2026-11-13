#!/usr/bin/env bash
# OpenCode serve with fleet OTLP auth for opencode-swarm observability.export.
# Credentials: OpenBao kv/tenants/shared/otel-ingest-client (rendered by sync script).
set -euo pipefail

OTEL_ENV="${HOME}/.config/centralcloud/otel-ingest.env"
SYNC="${HOME}/.dotfiles/scripts/sync-opencode-swarm-otel-from-bao.sh"

refresh_otel_from_bao() {
	[ -f "$SYNC" ] || return 1
	"$SYNC" >/dev/null 2>&1
}

if ! refresh_otel_from_bao; then
	if ! bao token lookup >/dev/null 2>&1; then
		bao-login --force >/dev/null 2>&1 || true
	fi
	refresh_otel_from_bao || true
fi

if [ -f "$OTEL_ENV" ]; then
	set -a
	# shellcheck disable=SC1090
	. "$OTEL_ENV"
	set +a
	# OpenCode / SDK read OTEL_EXPORTER_OTLP_ENDPOINT; sync file sets the traces URL.
	if [ -n "${OTEL_EXPORTER_OTLP_TRACES_ENDPOINT:-}" ]; then
		export OTEL_EXPORTER_OTLP_ENDPOINT="${OTEL_EXPORTER_OTLP_TRACES_ENDPOINT%/v1/traces}"
	fi
else
	echo "serve-with-otel: could not load ${OTEL_ENV} from OpenBao (run bao-login, then retry)" >&2
fi

LOCK_DIR="${XDG_RUNTIME_DIR:-/tmp}"
LOCK_FILE="${LOCK_DIR}/opencode-serve.lock"
mkdir -p "$LOCK_DIR"

pnpm_opencode="${HOME}/.local/share/pnpm/bin/opencode"
if [ ! -x "$pnpm_opencode" ]; then
	echo "serve-with-otel: pnpm-managed opencode not found at ${pnpm_opencode}" >&2
	exit 127
fi

EVALGATE_ERR=$(mktemp)
trap 'rm -f "$EVALGATE_ERR"' EXIT
set +e
evalgate -lock "$LOCK_FILE" -wait 1s -hold 15m run -- "$pnpm_opencode" "$@" 2>"$EVALGATE_ERR"
status=$?
set -e
if [ "$status" -eq 75 ]; then
	echo "serve-with-otel: another opencode serve --service holds ${LOCK_FILE}; not starting a duplicate" >&2
	cat "$EVALGATE_ERR" >&2
else
	cat "$EVALGATE_ERR" >&2
fi
exit "$status"
