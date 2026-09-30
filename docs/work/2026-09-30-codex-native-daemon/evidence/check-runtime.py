#!/usr/bin/env python3
"""Observe native Codex daemon ownership without changing runtime state."""
import json
import subprocess
import sys
from pathlib import Path


def command(*args):
    return subprocess.run(args, text=True, capture_output=True, check=True).stdout.strip()


version = json.loads(command("codex", "app-server", "daemon", "version"))
checks = {
    "running": version.get("status") == "running",
    "versions_agree": len({version.get(key) for key in (
        "cliVersion", "managedCodexVersion", "appServerVersion"
    )}) == 1,
}
units = {}
for unit in ("codex-managed-daemon.service", "codex-server-auto-update.timer",
             "codex-server-auto-update.service"):
    state = command("systemctl", "--user", "show", unit, "--property=ActiveState", "--value")
    units[unit] = state
    checks["retired:" + unit] = state not in ("active", "activating", "reloading", "deactivating")
    load = command("systemctl", "--user", "show", unit, "--property=LoadState", "--value")
    checks["unavailable:" + unit] = load == "not-found"

root = Path.home() / ".codex"
settings = json.loads((root / "app-server-daemon/settings.json").read_text())
checks["remote_control_enabled"] = settings.get("remoteControlEnabled") is True
selected = Path(version["managedCodexPath"]).resolve()
processes = []
for entry in Path("/proc").iterdir():
    if not entry.name.isdigit():
        continue
    try:
        args = (entry / "cmdline").read_bytes().split(b"\0")
        if b"app-server" in args and b"--managed-daemon" in args:
            processes.append({"pid": int(entry.name), "executable": str((entry / "exe").resolve())})
    except (OSError, RuntimeError):
        continue
checks["single_native_daemon"] = len(processes) == 1 and processes[0]["executable"] == str(selected)
checks["guardian_masked"] = command("systemctl", "--user", "show", "codex-guardian.timer",
                                   "--property=LoadState", "--value") == "masked"
result = {"ok": all(checks.values()), "version": version, "checks": checks,
          "legacy_units": units, "processes": processes}
print(json.dumps(result, indent=2))
sys.exit(0 if result["ok"] else 1)
