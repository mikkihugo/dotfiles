#!/usr/bin/env bash
# config/kimi-code/init-otel.sh — shell-side OTel env bridge
#
# The OTel defaults themselves are operator-owned: they live in
# `/etc/otel/defaults.env` (NixOS-rendered by `hosts/_shared/otel-defaults.nix`
# in `/srv/infra`). Per-user shells and per-user systemd-launched children
# inherit them via `systemctl --user import-environment`, which the host
# NixOS module arranges. This wrapper exists only so a kimi-code process
# launched OUTSIDE systemd (a plain interactive shell, an SSH session, or a
# tmux server that pre-dates the login session) still picks them up.
#
# Sources the operator file if present; emits a one-shot warning once per
# shell session if absent so a missing host module is observable, then
# continues with whatever the operator may have set in the live environment
# (e.g. via `export OTEL_EXPORTER_OTLP_ENDPOINT=...` in a launcher script).

_DEFAULTS=/etc/otel/defaults.env

if [[ -r "$_DEFAULTS" ]]; then
	# shellcheck disable=SC1090
	source "$_DEFAULTS"
else
	printf 'kimi-code/init-otel.sh: %s not readable; using last-known-good defaults (apply the operator /srv/infra hosts/_shared/otel-defaults.nix module to retire this fallback)\n' "$_DEFAULTS" >&2

	: "${OTEL_SERVICE_NAME:=kimi-code}"
	export OTEL_SERVICE_NAME

	: "${OTEL_TRACES_EXPORTER:=otlp}"
	export OTEL_TRACES_EXPORTER

	: "${OTEL_EXPORTER_OTLP_ENDPOINT:=http://otel-collector.monitoring.svc.cluster.local:4317}"
	export OTEL_EXPORTER_OTLP_ENDPOINT

	: "${OTEL_EXPORTER_OTLP_PROTOCOL:=grpc}"
	export OTEL_EXPORTER_OTLP_PROTOCOL

	: "${OTEL_RESOURCE_ATTRIBUTES:=kimi.client.name=kimi-code,kimi.client.source=dotfiles,kimi.observability.tie=2026-09-11}"
	export OTEL_RESOURCE_ATTRIBUTES

	: "${OTEL_PROPAGATORS:=tracecontext,baggage}"
	export OTEL_PROPAGATORS

	: "${OTEL_BSP_SCHEDULE_DELAY:=2000}"
	export OTEL_BSP_SCHEDULE_DELAY

	: "${OTEL_BSP_EXPORT_TIMEOUT:=30000}"
	export OTEL_BSP_EXPORT_TIMEOUT

	: "${KIMI_OTEL_TIE_VERSION:=2026-09-11}"
	export KIMI_OTEL_TIE_VERSION
fi

# Per-user convenience that the operator default file does not own.
# The hook script lives at $HOME so each user account points at its own copy.
export KIMI_HOOK_SESSION_START="${KIMI_HOOK_SESSION_START:-${HOME}/.kimi-code/hooks/otel-resource-attrs.sh}"
