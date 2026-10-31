#!/usr/bin/env python3
"""Verify the live Factory Droid Remote Control service without exposing keys."""

from __future__ import annotations

import argparse
import json
import os
import signal
import stat
import subprocess
import sys
import time
from pathlib import Path

SERVICE = "droid-remote-control.service"
PROVIDER_SERVICE = "droid-provider-config.service"
ENV_FILE = Path.home() / ".config" / "factory" / "droid.env"
DROID = Path.home() / ".local" / "bin" / "droid"
COMPUTER_NAME = "cc-se-sto-devbox-01"
PROVIDER_KEYS = ("MINIMAX_API_KEY", "KIMI_API_KEY", "OLLAMA_API_KEY")


def run(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(args, check=False, capture_output=True, text=True)


def service_property(unit: str, name: str) -> str:
    result = run("systemctl", "--user", "show", unit, f"--property={name}", "--value")
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or f"cannot read {unit} {name}")
    return result.stdout.strip()


def process_environment(pid: int) -> dict[str, bytes]:
    try:
        entries = Path(f"/proc/{pid}/environ").read_bytes().split(b"\0")
    except (FileNotFoundError, PermissionError):
        return {}
    environment: dict[str, bytes] = {}
    for entry in entries:
        if b"=" in entry:
            key, value = entry.split(b"=", 1)
            environment[key.decode("utf-8", "replace")] = value
    return environment


def process_command(pid: int) -> str:
    try:
        return Path(f"/proc/{pid}/cmdline").read_bytes().replace(b"\0", b" ").decode(
            "utf-8", "replace"
        )
    except (FileNotFoundError, PermissionError):
        return ""


def descendants(pid: int) -> list[int]:
    result: list[int] = []
    stack = [pid]
    while stack:
        current = stack.pop()
        try:
            children = Path(f"/proc/{current}/task/{current}/children").read_text()
        except (FileNotFoundError, PermissionError):
            continue
        for child in children.split():
            child_pid = int(child)
            result.append(child_pid)
            stack.append(child_pid)
    return result


def native_daemon_pid(main_pid: int) -> int | None:
    for pid in descendants(main_pid):
        command = process_command(pid)
        if "@factory/cli" in command and "droid daemon --remote-control" in command:
            return pid
    return None


def env_file_keys() -> set[str]:
    keys: set[str] = set()
    for line in ENV_FILE.read_text().splitlines():
        if "=" in line:
            keys.add(line.split("=", 1)[0])
    return keys


def verify_provider_environment(main_pid: int) -> dict[str, bool]:
    file_keys = env_file_keys()
    main_environment = process_environment(main_pid)
    native_pid = native_daemon_pid(main_pid)
    native_environment = process_environment(native_pid) if native_pid else {}
    return {
        key: key in file_keys
        and key in main_environment
        and bool(native_environment.get(key))
        for key in PROVIDER_KEYS
    }


def verify_restart() -> dict[str, object]:
    before_restarts = int(service_property(SERVICE, "NRestarts") or "0")
    before_pid = service_property(SERVICE, "MainPID")
    native_pid = native_daemon_pid(int(before_pid))
    if native_pid is None:
        raise RuntimeError("native Droid daemon child was not found")

    os.kill(native_pid, signal.SIGTERM)
    deadline = time.monotonic() + 20
    while time.monotonic() < deadline:
        active = service_property(SERVICE, "ActiveState")
        restarts = int(service_property(SERVICE, "NRestarts") or "0")
        main_pid = service_property(SERVICE, "MainPID")
        if active == "active" and restarts > before_restarts and main_pid != before_pid:
            return {
                "proven": True,
                "restarts_before": before_restarts,
                "restarts_after": restarts,
                "main_pid_before": before_pid,
                "main_pid_after": main_pid,
            }
        time.sleep(0.5)

    return {
        "proven": False,
        "restarts_before": before_restarts,
        "restarts_after": int(service_property(SERVICE, "NRestarts") or "0"),
        "main_pid_before": before_pid,
        "main_pid_after": service_property(SERVICE, "MainPID"),
        "active_state": service_property(SERVICE, "ActiveState"),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--restart",
        action="store_true",
        help="terminate the native Droid daemon once and require systemd to restart it",
    )
    args = parser.parse_args()

    failures: list[str] = []
    provider_state = service_property(PROVIDER_SERVICE, "ActiveState")
    active_state = service_property(SERVICE, "ActiveState")
    sub_state = service_property(SERVICE, "SubState")
    enabled = run("systemctl", "--user", "is-enabled", SERVICE).stdout.strip()
    main_pid = service_property(SERVICE, "MainPID")
    mode = stat.S_IMODE(ENV_FILE.stat().st_mode)
    file_keys = env_file_keys()
    provider_environment = verify_provider_environment(int(main_pid))
    computers = run(str(DROID), "computer", "list").stdout

    if provider_state != "active":
        failures.append(f"provider service is {provider_state}, expected active")
    if active_state != "active" or sub_state != "running":
        failures.append(
            f"remote-control service is {active_state}/{sub_state}, expected active/running"
        )
    if enabled != "enabled":
        failures.append(f"remote-control service is {enabled}, expected enabled")
    if mode != 0o600:
        failures.append(f"provider env mode is {oct(mode)}, expected 0o600")
    missing_file_keys = sorted(set(PROVIDER_KEYS) - file_keys)
    if missing_file_keys:
        failures.append(f"provider env is missing key names: {missing_file_keys}")
    missing_process_keys = sorted(
        key for key, present in provider_environment.items() if not present
    )
    if missing_process_keys:
        failures.append(
            f"Droid process is missing provider variables: {missing_process_keys}"
        )
    if f"{COMPUTER_NAME}\t" not in computers:
        failures.append(f"computer list does not contain {COMPUTER_NAME}")

    restart_result: dict[str, object] | None = None
    if args.restart:
        restart_result = verify_restart()
        if not restart_result["proven"]:
            failures.append("native daemon termination did not trigger a systemd restart")

    report = {
        "provider_service_state": provider_state,
        "service_state": active_state,
        "service_substate": sub_state,
        "service_enabled": enabled,
        "main_pid": main_pid,
        "provider_env_mode": oct(mode),
        "provider_env_key_names": sorted(file_keys),
        "provider_environment_present": provider_environment,
        "computer_registered": f"{COMPUTER_NAME}\t" in computers,
        "restart": restart_result,
        "failures": failures,
    }
    print(json.dumps(report, indent=2, sort_keys=True))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
