#!/usr/bin/env python3
import subprocess
import tempfile
import tomllib
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("codex-preferences")


class CodexPreferencesTest(unittest.TestCase):
    def test_apply_updates_shared_tui_status_line_and_preserves_other_config(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            shared = root / "shared.toml"
            live = root / "config.toml"
            shared.write_text(
                'model = "gpt-5.6-sol"\n'
                'model_reasoning_effort = "low"\n\n'
                '[tui]\n'
                'status_line = ["model-with-reasoning", "thread-id"]\n'
            )
            live.write_text(
                'model = "gpt-5.5"\n'
                'model_reasoning_effort = "medium"\n'
                'personality = "pragmatic"\n\n'
                '[projects."/home/mhugo"]\n'
                'trust_level = "trusted"\n\n'
                '[tui]\n'
                'status_line = ["model"]\n'
                'terminal_title = ["activity", "project-name"]\n'
                'status_line_use_colors = true\n'
            )

            subprocess.run(
                [str(SCRIPT), "apply", "--source", str(shared), "--target", str(live)],
                check=True,
            )

            rendered = live.read_text()
            parsed = tomllib.loads(rendered)
            self.assertEqual(parsed["model"], "gpt-5.6-sol")
            self.assertEqual(parsed["model_reasoning_effort"], "low")
            self.assertEqual(parsed["tui"]["status_line"], ["model-with-reasoning", "thread-id"])
            self.assertEqual(parsed["tui"]["terminal_title"], ["activity", "project-name"])
            self.assertTrue(parsed["tui"]["status_line_use_colors"])
            self.assertIn('[projects."/home/mhugo"]', rendered)
            self.assertIn('personality = "pragmatic"', rendered)


if __name__ == "__main__":
    unittest.main()
