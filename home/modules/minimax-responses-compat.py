#!/usr/bin/env python3
"""Small OpenAI Responses compatibility proxy for MiniMax -> Grok.

MiniMax emits service_tier="standard" and null annotations in Responses
payloads. Grok's strict Responses schema accepts default/auto/flex/scale/priority
and expects annotations to be an array. Other reasoning/tool fields pass through
unchanged.
"""

import http.client
import json
import logging
import os
import ssl
import tomllib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit
import re


UPSTREAM = os.environ.get("MINIMAX_RESPONSES_UPSTREAM", "https://api.minimax.io/v1")
LISTEN_HOST = os.environ.get("MINIMAX_RESPONSES_LISTEN_HOST", "127.0.0.1")
LISTEN_PORT = int(os.environ.get("MINIMAX_RESPONSES_LISTEN_PORT", "18787"))


def models_v2_payload():
    """Return the minimal catalog Grok probes before using Responses."""
    return {
        "object": "list",
        "data": [
            {
                "id": "minimax-m3-responses",
                "object": "model",
                "created": 0,
                "owned_by": "minimax",
            }
        ],
    }


def normalize_payload(value):
    if isinstance(value, dict):
        normalized = {
            key: "default" if key == "service_tier" and item == "standard" else normalize_payload(item)
            for key, item in value.items()
        }
        if "annotations" in normalized and normalized["annotations"] is None:
            normalized["annotations"] = []
        if isinstance(normalized.get("usage"), dict):
            output_details = normalized["usage"].setdefault("output_tokens_details", {})
            if isinstance(output_details, dict):
                output_details.setdefault("reasoning_tokens", 0)
        return normalized
    if isinstance(value, list):
        return [normalize_payload(item) for item in value]
    return value


def normalize_request_payload(value):
    """Repair Grok's replayed tool correlation before MiniMax validates it.

    Grok preserves historical function calls with provider call IDs, but its
    replayed outputs may use unrelated ``grok-call-N`` IDs.  Responses
    requires each output's ``call_id`` to match the corresponding
    ``function_call``.  Keep valid IDs, give blank/duplicate calls stable
    local IDs, and map the known replay form by function-call order.
    """
    if not isinstance(value, dict) or not isinstance(value.get("input"), list):
        return value

    normalized = dict(value)
    items = [dict(item) if isinstance(item, dict) else item for item in value["input"]]
    calls = []
    seen = set()
    for item in items:
        if not isinstance(item, dict) or item.get("type") != "function_call":
            continue
        original = item.get("call_id")
        canonical = str(original).strip() if original is not None else ""
        if not canonical:
            canonical = f"grok-replay-call-{len(calls)}"
        elif canonical in seen:
            suffix = 2
            candidate = f"{canonical}-{suffix}"
            while candidate in seen:
                suffix += 1
                candidate = f"{canonical}-{suffix}"
            canonical = candidate
        item["call_id"] = canonical
        calls.append(canonical)
        seen.add(canonical)

    next_unmatched = 0
    for item in items:
        if not isinstance(item, dict) or item.get("type") != "function_call_output":
            continue
        output_id = item.get("call_id")
        if output_id in calls:
            continue
        mapped = None
        match = re.fullmatch(r"grok-call-(\d+)", str(output_id or ""))
        if match:
            index = int(match.group(1)) - 1
            if 0 <= index < len(calls):
                mapped = calls[index]
        if mapped is None:
            while next_unmatched < len(calls) and any(
                prior.get("call_id") == calls[next_unmatched]
                for prior in items
                if isinstance(prior, dict) and prior.get("type") == "function_call_output"
            ):
                next_unmatched += 1
            if next_unmatched < len(calls):
                mapped = calls[next_unmatched]
                next_unmatched += 1
        if mapped is not None:
            item["call_id"] = mapped

    normalized["input"] = items
    return normalized


def request_tool_metadata(value):
    """Return bounded, non-content metadata for diagnosing upstream rejects."""
    if not isinstance(value, dict) or not isinstance(value.get("input"), list):
        return []
    return [
        {
            key: item[key]
            for key in ("type", "id", "call_id", "name")
            if key in item
        }
        for item in value["input"]
        if isinstance(item, dict) and item.get("type") in {"function_call", "function_call_output"}
    ][:200]


def strip_minimax_reasoning_items(value):
    """Drop reasoning output items before Grok parses the payload.

    MiniMax emits Responses ``reasoning`` items whose content is
    ``{"type": "reasoning_text", "text": ...}`` with no ``signature``.  Grok's
    strict Responses schema rejects such items with ``serialization error:
    missing field `signature```, so any MiniMax turn that thinks fails to
    deserialize (observed 2026-09-21: every reasoning-producing turn of the
    leader's minimax-m3-responses profile failed; text-only turns passed).
    MiniMax accepts multi-turn replay without the prior reasoning items, so
    dropping them loses only the not-replayed thinking visibility.
    """
    if isinstance(value, dict):
        output = value.get("output")
        if isinstance(output, list):
            filtered = [item for item in output if not (isinstance(item, dict) and item.get("type") == "reasoning")]
            if len(filtered) != len(output):
                value = dict(value)
                value["output"] = filtered
        return value
    return value


def normalize_sse_line(line):
    newline = ""
    if line.endswith("\r\n"):
        line, newline = line[:-2], "\r\n"
    elif line.endswith("\n") or line.endswith("\r"):
        newline = line[-1]
        line = line[:-1]
    if not line.startswith("data:"):
        return line + newline
    data = line[5:]
    prefix = "data:"
    if data.startswith(" "):
        prefix += " "
        data = data[1:]
    if data == "[DONE]":
        return line + newline
    try:
        payload = json.loads(data)
    except json.JSONDecodeError:
        return line + newline
    event_type = payload.get("type") if isinstance(payload, dict) else None
    if event_type in {"response.reasoning_text.delta", "response.reasoning_text.done"}:
        return None
    return prefix + json.dumps(normalize_payload(payload), separators=(",", ":")) + newline


def upstream_target(path):
    parsed = urlsplit(UPSTREAM)
    base = parsed.path.rstrip("/")
    request_path = path if path.startswith("/") else f"/{path}"
    # Grok's configured base URL includes /v1, while BaseHTTPRequestHandler
    # receives the complete /v1/... request path. Avoid duplicating the prefix.
    has_base = bool(base) and (request_path == base or request_path.startswith(f"{base}/"))
    suffix = request_path[len(base) :] if has_base else request_path
    return parsed, f"{base}{suffix}"


def local_minimax_authorization():
    """Use Grok's local profile key when the leader omits one in OIDC mode."""
    config_path = Path.home() / ".grok" / "config.toml"
    try:
        config = tomllib.loads(config_path.read_text())
        key = config["model"]["minimax-m3-responses"].get("api_key")
    except (OSError, KeyError, TypeError, tomllib.TOMLDecodeError):
        key = None
    return f"Bearer {key}" if key else None


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def do_GET(self):
        if self.path.rstrip("/") == "/v1/models-v2":
            raw = json.dumps(models_v2_payload(), separators=(",", ":")).encode()
            self.send_response(200, "OK")
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(raw)))
            self.end_headers()
            self.wfile.write(raw)
            self.wfile.flush()
            logging.info("served local Grok model catalog /v1/models-v2")
            return
        self.proxy(b"")

    def do_POST(self):
        length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(length) if length else b""
        request = None
        if self.path.rstrip("/").endswith("/v1/responses"):
            try:
                request = json.loads(body)
                repaired = normalize_request_payload(request)
                if repaired != request:
                    body = json.dumps(repaired, separators=(",", ":")).encode()
                    logging.info("repaired replayed Responses tool correlation ids")
                    request = repaired
            except (UnicodeDecodeError, json.JSONDecodeError):
                pass
        self.proxy(body, request)

    def proxy(self, body, request=None):
        parsed, path = upstream_target(self.path)
        headers = {
            key: value
            for key, value in self.headers.items()
            if key.lower() not in {"host", "content-length", "connection", "accept-encoding"}
        }
        # This endpoint is dedicated to MiniMax. Grok's OIDC bearer is not a
        # MiniMax API key, so replace it whenever the local profile key exists.
        authorization = local_minimax_authorization()
        for key in list(headers):
            if key.lower() == "authorization":
                del headers[key]
        if authorization:
            headers["Authorization"] = authorization
        headers["Accept-Encoding"] = "identity"
        conn_cls = http.client.HTTPSConnection if parsed.scheme == "https" else http.client.HTTPConnection
        kwargs = {"timeout": 300}
        if parsed.scheme == "https":
            kwargs["context"] = ssl.create_default_context()
        conn = conn_cls(parsed.netloc, **kwargs)
        try:
            logging.info("proxying %s %s body_bytes=%d headers=%s", self.command, self.path, len(body), sorted(headers))
            conn.request(self.command, path, body=body, headers=headers)
            response = conn.getresponse()
            content_type = response.getheader("Content-Type", "")
            streaming = content_type.startswith("text/event-stream")
            out_headers = {
                key: value
                for key, value in response.getheaders()
                if key.lower() not in {"content-length", "transfer-encoding", "connection", "content-encoding"}
            }
            self.send_response(response.status, response.reason)
            for key, value in out_headers.items():
                self.send_header(key, value)
            if streaming:
                self.send_header("Transfer-Encoding", "chunked")
            else:
                raw = response.read()
                if response.status >= 400:
                    logging.warning("MiniMax upstream %s: %s", response.status, raw[:2000].decode("utf-8", "replace"))
                    if request is not None:
                        logging.warning("rejected Responses tool metadata=%s", request_tool_metadata(request))
                try:
                    raw = json.dumps(strip_minimax_reasoning_items(normalize_payload(json.loads(raw)))).encode()
                except (UnicodeDecodeError, json.JSONDecodeError):
                    pass
                self.send_header("Content-Length", str(len(raw)))
            self.end_headers()
            if streaming:
                self.stream_sse(response)
            else:
                self.wfile.write(raw)
                self.wfile.flush()
        finally:
            conn.close()

    def stream_sse(self, response):
        pending = ""
        while True:
            chunk = response.read(65536)
            if not chunk:
                break
            pending += chunk.decode("utf-8", errors="replace")
            lines = pending.splitlines(keepends=True)
            if lines and not lines[-1].endswith(("\n", "\r")):
                pending = lines.pop()
            else:
                pending = ""
            for line in lines:
                normalized = normalize_sse_line(line)
                if normalized is None:
                    continue
                self.write_chunk(normalized.encode())
        if pending:
            normalized = normalize_sse_line(pending)
            if normalized is not None:
                self.write_chunk(normalized.encode())
        self.wfile.write(b"0\r\n\r\n")
        self.wfile.flush()

    def write_chunk(self, data):
        self.wfile.write(f"{len(data):x}\r\n".encode() + data + b"\r\n")
        self.wfile.flush()

    def log_message(self, fmt, *args):
        logging.info("%s - %s", self.address_string(), fmt % args)


if __name__ == "__main__":
    logging.basicConfig(level=os.environ.get("LOG_LEVEL", "INFO"))
    server = ThreadingHTTPServer((LISTEN_HOST, LISTEN_PORT), Handler)
    logging.info("MiniMax Responses compatibility proxy listening on %s:%s -> %s", LISTEN_HOST, LISTEN_PORT, UPSTREAM)
    server.serve_forever()
