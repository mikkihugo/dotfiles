"""Narrow detect-secrets exemption for canonical Purpose work-packet digests."""

import json
import re
from pathlib import Path
from typing import Any


_PACKET_PATH = re.compile(
    r"(?:^|/)docs/work/[^/]+/(?:purpose\.contract|work\.spec|evidence\.bundle)\.json$"
)
_DIGEST_VALUE = re.compile(r"[0-9a-f]{64}\Z")
_DIGEST_KEYS = frozenset({"algorithm", "canonicalization", "value"})
_CANONICALIZATION_VALUES = frozenset({"engine-json-v1", "raw-bytes"})


def is_purpose_work_packet_digest(filename: str, secret: str) -> bool:
    """Filter only canonical SHA-256 digest values in the three Purpose packet files.

    detect-secrets calls this after an entropy detector flags a candidate.  The
    repository secret gate remains responsible for every other high-entropy
    value, including values in a packet file that are not structured digests.
    """
    if not _PACKET_PATH.search(filename.replace("\\", "/")):
        return False
    if not _DIGEST_VALUE.fullmatch(secret):
        return False

    try:
        document = json.loads(Path(filename).read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError):
        return False

    occurrences, canonical_digests = _count_digest_occurrences(document, secret)
    return canonical_digests > 0 and occurrences == canonical_digests


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
