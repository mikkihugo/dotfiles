"""Narrow detect-secrets exemption for canonical Purpose work-packet digests."""

import json
import re
from pathlib import Path
from typing import Any


_DIGEST_PACKET_PATH = re.compile(
    r"(?:^|/)docs/work/[^/]+/(?:purpose\.contract|work\.spec|evidence\.bundle)\.json$"
)
_SNAPSHOT_PATH = re.compile(r"(?:^|/)docs/work/[^/]+/current-spec\.snapshot\.json$")
_EVIDENCE_PROOF_PATH = re.compile(
    r"(?:^|/)docs/work/[^/]+/evidence/(?:red|green)(?:-[a-z0-9._-]+)?-proof\.json$"
)
_DIGEST_VALUE = re.compile(r"[0-9a-f]{64}\Z")
_REVISION_VALUE = re.compile(r"[0-9a-f]{40}\Z")
_DIGEST_KEYS = frozenset({"algorithm", "canonicalization", "value"})
_CANONICALIZATION_VALUES = frozenset({"engine-json-v1", "raw-bytes"})


class _DuplicateJsonKey(ValueError):
    """Raised when a JSON object would lose data during normal decoding."""


def _reject_duplicate_json_keys(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    """Build an object only when every source key has one unambiguous value."""
    document: dict[str, Any] = {}
    for key, value in pairs:
        if key in document:
            raise _DuplicateJsonKey(key)
        document[key] = value
    return document


def is_purpose_work_packet_digest(filename: str, secret: str) -> bool:
    """Filter only canonical Purpose digest and source-revision metadata.

    detect-secrets calls this after an entropy detector flags a candidate.  The
    repository secret gate remains responsible for every other high-entropy
    value, including values in a packet file that are not structured digest or
    source-revision metadata.
    """
    normalized_filename = filename.replace("\\", "/")

    try:
        document = json.loads(
            Path(filename).read_text(encoding="utf-8"),
            object_pairs_hook=_reject_duplicate_json_keys,
        )
    except (OSError, UnicodeDecodeError, json.JSONDecodeError, _DuplicateJsonKey):
        return False

    if _DIGEST_PACKET_PATH.search(normalized_filename) and _DIGEST_VALUE.fullmatch(secret):
        occurrences, canonical_digests = _count_digest_occurrences(document, secret)
        return canonical_digests > 0 and occurrences == canonical_digests

    if (
        (_SNAPSHOT_PATH.search(normalized_filename) or _EVIDENCE_PROOF_PATH.search(normalized_filename))
        and _REVISION_VALUE.fullmatch(secret)
    ):
        occurrences, canonical_revisions = _count_source_revision_occurrences(document, secret)
        return canonical_revisions > 0 and occurrences == canonical_revisions

    return False


def _count_digest_occurrences(value: Any, secret: str) -> tuple[int, int]:
    """Count candidate strings and exact permitted digest objects in a packet."""
    if isinstance(value, dict):
        canonical_digest = int(
            set(value) == _DIGEST_KEYS
            and value.get("algorithm") == "sha256"
            and value.get("canonicalization") in _CANONICALIZATION_VALUES
            and value.get("value") == secret
        )
        child_counts = [_count_digest_occurrences(child, secret) for child in value.values()]
        return (
            sum(key == secret for key in value) + sum(occurrences for occurrences, _ in child_counts),
            canonical_digest + sum(digests for _, digests in child_counts),
        )
    if isinstance(value, list):
        child_counts = [_count_digest_occurrences(child, secret) for child in value]
        return (
            sum(occurrences for occurrences, _ in child_counts),
            sum(digests for _, digests in child_counts),
        )
    return (int(value == secret), 0)


def _count_source_revision_occurrences(value: Any, secret: str) -> tuple[int, int]:
    """Admit one exact top-level source revision and no other occurrence.

    A proof document may contain arbitrary nested evidence.  Limiting the
    exemption to its top-level ``source`` record prevents a nested lookalike
    from becoming an entropy-filter bypass.
    """
    occurrences = _count_string_occurrences(value, secret)
    if not isinstance(value, dict):
        return (occurrences, 0)

    source = value.get("source")
    if not isinstance(source, dict):
        return (occurrences, 0)

    snapshot_source = (
        set(source) == {"uri", "revision"}
        and isinstance(source.get("uri"), str)
        and source["uri"].startswith("repository://")
        and source.get("revision") == secret
    )
    proof_source = (
        set(source) == {"path", "revision", "role"}
        and all(isinstance(source.get(key), str) for key in ("path", "role"))
        and source.get("revision") == secret
    )
    return (occurrences, int(snapshot_source or proof_source))


def _count_string_occurrences(value: Any, secret: str) -> int:
    """Count every candidate occurrence so duplicate values remain detectable."""
    if isinstance(value, dict):
        return sum(key == secret for key in value) + sum(
            _count_string_occurrences(child, secret) for child in value.values()
        )
    if isinstance(value, list):
        return sum(_count_string_occurrences(child, secret) for child in value)
    return int(value == secret)
