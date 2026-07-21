#!/usr/bin/env bash
# shell/bash/otel-env.sh — export CentralCloud OTLP env for coding CLIs
#
# Prefer in-cluster otel-collector (no auth). Fall back to public
# otel-ingest.centralcloud.net with BasicAuth from OpenBao
# kv/tenants/shared/otel-ingest-client (same shape as llm-gateway-client).
#
# Sourced from shell/bash/bashrc after SOPS load. Idempotent and silent.
#
# Consumers: claude, codex, cursor-agent, droid/factory, kimi, qoder, goose,
# and any other process that honors OTEL_EXPORTER_OTLP_*.

_cc_otel_env_load() {
	# Respect an explicit operator override.
	if [ -n "${OTEL_EXPORTER_OTLP_ENDPOINT:-}" ] || [ -n "${CENTRALCLOUD_OTEL_SKIP:-}" ]; then
		return 0
	fi

	local collector_http="http://otel-collector.monitoring.svc.cluster.local:4318"
	local collector_grpc="http://otel-collector.monitoring.svc.cluster.local:4317"
	local public_http="https://otel-ingest.centralcloud.net"
	local endpoint="" protocol="" headers=""

	# Fast path: cluster collector HTTP (this host is usually on the mesh).
	if curl -skS --max-time 1 -o /dev/null -w '' \
		-X POST "${collector_http}/v1/traces" \
		-H 'Content-Type: application/x-protobuf' \
		--data-binary '' >/dev/null 2>&1; then
		endpoint="$collector_http"
		protocol="http/protobuf"
	elif curl -skS --max-time 1 -o /dev/null "${collector_grpc}" >/dev/null 2>&1; then
		endpoint="$collector_grpc"
		protocol="grpc"
	else
		# Public Edge Gateway → Envoy → Traefik BasicAuth → collector.
		local user pass
		user=""
		pass=""
		if command -v bao >/dev/null 2>&1; then
			user="$(
				BAO_ADDR="${BAO_ADDR:-https://kv.infra.centralcloud.com}" \
					bao kv get -field=username -mount=kv tenants/shared/otel-ingest-client 2>/dev/null || true
			)"
			pass="$(
				BAO_ADDR="${BAO_ADDR:-https://kv.infra.centralcloud.com}" \
					bao kv get -field=password -mount=kv tenants/shared/otel-ingest-client 2>/dev/null || true
			)"
			endpoint="$(
				BAO_ADDR="${BAO_ADDR:-https://kv.infra.centralcloud.com}" \
					bao kv get -field=endpoint -mount=kv tenants/shared/otel-ingest-client 2>/dev/null || true
			)"
			protocol="$(
				BAO_ADDR="${BAO_ADDR:-https://kv.infra.centralcloud.com}" \
					bao kv get -field=protocol -mount=kv tenants/shared/otel-ingest-client 2>/dev/null || true
			)"
		fi
		endpoint="${endpoint:-$public_http}"
		protocol="${protocol:-http/protobuf}"
		if [ -n "$user" ] && [ -n "$pass" ]; then
			headers="Authorization=Basic $(printf '%s:%s' "$user" "$pass" | base64 -w0 2>/dev/null || printf '%s:%s' "$user" "$pass" | base64)"
		fi
	fi

	[ -n "$endpoint" ] || return 0

	export OTEL_EXPORTER_OTLP_ENDPOINT="$endpoint"
	export OTEL_EXPORTER_OTLP_PROTOCOL="$protocol"
	export OTEL_TRACES_EXPORTER=otlp
	export OTEL_METRICS_EXPORTER=otlp
	export OTEL_LOGS_EXPORTER=otlp
	export OTEL_SERVICE_NAME="${OTEL_SERVICE_NAME:-centralcloud-devbox}"
	export OTEL_RESOURCE_ATTRIBUTES="${OTEL_RESOURCE_ATTRIBUTES:-deployment.environment=prod,service.namespace=devbox}"

	# Claude Code / Agent SDK
	export CLAUDE_CODE_ENABLE_TELEMETRY=1
	export CLAUDE_CODE_ENHANCED_TELEMETRY_BETA=1

	if [ -n "$headers" ]; then
		export OTEL_EXPORTER_OTLP_HEADERS="$headers"
	fi
}

_cc_otel_env_load
unset -f _cc_otel_env_load
