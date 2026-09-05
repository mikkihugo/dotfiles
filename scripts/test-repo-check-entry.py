#!/usr/bin/env python3
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]

class CheckEntryTest(unittest.TestCase):
    def test_nix_entry_is_bounded_and_rejects_wrong_environments(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "bin").mkdir()
            (root / "scripts").mkdir()
            shutil.copy2(ROOT / "bin/repo", root / "bin/repo")
            guard = ROOT / "scripts/repo-check-nix.sh"
            if guard.exists():
                shutil.copy2(guard, root / "scripts/repo-check-nix.sh")
            full = root / "scripts/repo-check.sh"
            full.write_text("#!/usr/bin/env bash\nprintf invoked > \"$FULL_MARKER\"\n")
            full.chmod(0o755)
            # Host startup hooks must not replace this fixture's controlled PATH.
            env = dict(os.environ, BASH_ENV="", PATH=str(root / "bin") + os.pathsep + os.environ["PATH"],
                       FULL_MARKER=str(root / "full"), DIRENV_DIR="-" + str(root))
            for shell, fallback, directory, expected in [
                ("", "", str(root), False),
                ("impure", "1", str(root), False),
                ("impure", "", "/foreign", False),
                ("impure", "", str(root), True),
                ("pure", "", str(root), True),
            ]:
                with self.subTest(shell=shell, fallback=fallback, directory=directory):
                    result = subprocess.run([str(root / "bin/repo"), "check", "nix"], cwd=root,
                        env=dict(env, IN_NIX_SHELL=shell, NIX_DIRENV_DID_FALLBACK=fallback,
                                 DIRENV_DIR="-" + directory), capture_output=True, text=True)
                    self.assertEqual(result.returncode == 0, expected, result.stderr)
                    self.assertFalse((root / "full").exists(), "startup invoked the full gate")

    def test_invalid_check_arguments_never_start_full_gate(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "bin").mkdir()
            (root / "scripts").mkdir()
            shutil.copy2(ROOT / "bin/repo", root / "bin/repo")
            shutil.copy2(ROOT / "scripts/repo-check.sh", root / "scripts/repo-check.sh")
            probe = root / "scripts/current-home-profile"
            probe.write_text("#!/usr/bin/env bash\nprintf invoked > \"$FULL_MARKER\"\nprintf profile\n")
            probe.chmod(0o755)
            for args in ([""], ["", "unexpected"], ["unknown"], ["codex-preferences", "extra"], ["check-entry", "extra"]):
                with self.subTest(args=args):
                    marker = root / "full"
                    marker.unlink(missing_ok=True)
                    result = subprocess.run([str(root / "bin/repo"), "check", *args],
                        env=dict(os.environ, BASH_ENV="", FULL_MARKER=str(marker)), capture_output=True, text=True)
                    self.assertEqual(result.returncode, 2, result.stderr)
                    self.assertFalse(marker.exists(), "invalid arguments entered full gate")

if __name__ == "__main__":
    unittest.main()
