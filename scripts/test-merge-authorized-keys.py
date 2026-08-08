#!/usr/bin/env python3
"""Contract tests for scripts/merge-authorized-keys.

The merge runs during home-manager activation against the live
~/.ssh/authorized_keys of a host whose sshd has StrictModes yes. The two
properties that matter are that it never revokes a key it did not declare, and
that repeated activations do not duplicate lines.
"""
import base64
import os
import stat
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent / "merge-authorized-keys"


def blob(key_type: str, filler: bytes, keylen: int = 32) -> str:
    """Build a correctly framed public-key blob from a deterministic filler.

    Built at runtime rather than pasted as base64 literals so the test does not
    ship high-entropy strings that detect-secrets must be taught to ignore.
    Only blob equality matters to the merge, but real SSH framing keeps the
    fixtures parsable by ssh-keygen if a future check wants that.
    """
    def field(raw: bytes) -> bytes:
        return struct.pack(">I", len(raw)) + raw

    return base64.b64encode(
        field(key_type.encode()) + field((filler * keylen)[:keylen])
    ).decode()


# Distinct blobs. Only equality matters to the merge.
BLOB_A = blob("ssh-ed25519", b"A")
BLOB_B = blob("ssh-ed25519", b"B")
BLOB_C = blob("ssh-ed25519", b"C")
BLOB_SK = blob("sk-ecdsa-sha2-nistp256@openssh.com", b"S")

failures = []


def check(label, cond, detail=""):
    if cond:
        print(f"ok   {label}")
    else:
        print(f"FAIL {label} {detail}", file=sys.stderr)
        failures.append(label)


def run(declared, target):
    return subprocess.run(
        [sys.executable, str(SCRIPT), "--declared", str(declared), "--target", str(target)],
        capture_output=True,
        text=True,
    )


def blobs_of(path):
    out = []
    for line in Path(path).read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split()
        for i, part in enumerate(parts):
            if part.startswith(("ssh-", "ecdsa-", "sk-")):
                out.append(parts[i + 1])
                break
    return out


def case(name):
    tmp = Path(tempfile.mkdtemp(prefix="merge-keys-"))
    return tmp / "declared.pub", tmp / "authorized_keys", name


# 1. Adds a declared key that is absent, leaves the rest untouched.
declared, target, _ = case("add")
declared.write_text(f"ssh-ed25519 {BLOB_A} #ssh.id - @mhugo\nssh-ed25519 {BLOB_C} #ssh.id - @mhugo\n")
target.write_text(f"ssh-ed25519 {BLOB_A} existing-comment\nssh-ed25519 {BLOB_B} unpublished-key\n")
r = run(declared, target)
check("exit 0 on add", r.returncode == 0, r.stderr)
after = blobs_of(target)
check("adds only the missing declared key (2 -> 3)", len(after) == 3, after)
check("declared key now present", BLOB_C in after)
check("undeclared pre-existing key kept", BLOB_B in after)

# 2. Idempotent: a second run changes nothing.
before = target.read_text()
r = run(declared, target)
check("exit 0 on rerun", r.returncode == 0, r.stderr)
check("second run is a no-op (byte-identical)", target.read_text() == before)
check("no duplicate lines after rerun", len(blobs_of(target)) == 3, blobs_of(target))

# 3. Same key with a different comment is not re-added.
declared, target, _ = case("comment")
declared.write_text(f"ssh-ed25519 {BLOB_A} #SSH ID - @mhugo\n")
target.write_text(f"ssh-ed25519 {BLOB_A}\n")
run(declared, target)
check("comment difference does not create a duplicate", len(blobs_of(target)) == 1, blobs_of(target))

# 4. Never removes: hardware token and options-prefixed lines survive.
declared, target, _ = case("preserve")
declared.write_text(f"ssh-ed25519 {BLOB_C} #ssh.id - @mhugo\n")
target.write_text(
    f'sk-ecdsa-sha2-nistp256@openssh.com {BLOB_SK} hardware-token\n'
    f'restrict,command="/bin/true" ssh-ed25519 {BLOB_B} options-line\n'
)
run(declared, target)
kept = blobs_of(target)
check("hardware sk key preserved", BLOB_SK in kept, kept)
check("options-prefixed key preserved", BLOB_B in kept, kept)
check("declared key appended alongside (2 -> 3)", len(kept) == 3, kept)

# 5. Options-prefixed line is matched on its blob, not re-added.
declared.write_text(f"ssh-ed25519 {BLOB_B} #ssh.id - @mhugo\n")
run(declared, target)
check("options-prefixed key matched, not duplicated", blobs_of(target).count(BLOB_B) == 1)

# 6. Result is 0600 even if the file started world-readable.
declared, target, _ = case("perms")
declared.write_text(f"ssh-ed25519 {BLOB_A} #ssh.id - @mhugo\n")
target.write_text("")
os.chmod(target, 0o644)
run(declared, target)
mode = stat.S_IMODE(target.stat().st_mode)
check("target left at 0600", mode == 0o600, oct(mode))

# 7. Missing target is created rather than crashing.
declared, target, _ = case("create")
declared.write_text(f"ssh-ed25519 {BLOB_A} #ssh.id - @mhugo\n")
r = run(declared, target)
check("exit 0 when target absent", r.returncode == 0, r.stderr)
check("target created with the declared key", target.exists() and blobs_of(target) == [BLOB_A])
check(
    "created target is 0600",
    target.exists() and stat.S_IMODE(target.stat().st_mode) == 0o600,
)

# 8. A missing declared file is a warning, not an activation failure.
declared, target, _ = case("nodeclared")
target.write_text(f"ssh-ed25519 {BLOB_B} keep-me\n")
r = run(declared, target)
check("exit 0 when declared file absent", r.returncode == 0, r.stderr)
check("target untouched when declared file absent", blobs_of(target) == [BLOB_B])

if failures:
    print(f"\n{len(failures)} check(s) failed: {failures}", file=sys.stderr)
    sys.exit(1)
print("\nall merge-authorized-keys checks passed")
