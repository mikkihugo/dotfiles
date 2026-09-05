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
                'model_provider = "openai"\n'
                'model_reasoning_effort = "low"\n'
                'web_search = "disabled"\n\n'
                '[tui]\n'
                'status_line = ["model-with-reasoning", "thread-id"]\n'
            )
            live.write_text(
                'model = "gpt-5.5"\n'
                'model_provider = "llm-gateway"\n'
                'model_reasoning_effort = "medium"\n'
                'web_search = "live"\n'
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
            self.assertEqual(parsed["model_provider"], "openai")
            self.assertEqual(parsed["model_reasoning_effort"], "low")
            self.assertEqual(parsed["web_search"], "disabled")
            self.assertEqual(parsed["tui"]["status_line"], ["model-with-reasoning", "thread-id"])
            self.assertEqual(parsed["tui"]["terminal_title"], ["activity", "project-name"])
            self.assertTrue(parsed["tui"]["status_line_use_colors"])
            self.assertIn('[projects."/home/mhugo"]', rendered)
            self.assertIn('personality = "pragmatic"', rendered)


    def test_managed_defaults_match_operator_settings(self):
        for name in ("config.toml", "shared-preferences.toml"):
            data = tomllib.loads((SCRIPT.parents[1] / "config/codex" / name).read_text())
            self.assertEqual(data["model"], "gpt-6-astra")
            self.assertEqual(data["model_reasoning_effort"], "medium")
            for feature in ("context_management", "step_model_switching", "mcp_2026_07_28"):
                self.assertIs(data["features"][feature], True)
            self.assertIs(data["features"]["memories"], False)

    def test_roundtrip_managed_features_preserves_unmanaged_settings(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source, shared, target = (root / name for name in ("source.toml", "shared.toml", "target.toml"))
            source.write_text('model = "gpt-6-astra"\nmodel_reasoning_effort = "medium"\n'
                '[features]\nmemories = false\ncontext_management = true\n'
                'step_model_switching = true\nmcp_2026_07_28 = true\nunmanaged = false\n')
            target.write_text('model = "gpt-5.6-sol"\nmodel_reasoning_effort = "low"\n'
                'personality = "pragmatic"\n[features]\ncontext_management = false\n'
                'step_model_switching = false\nmcp_2026_07_28 = false\nunmanaged = true\n'
                '[profiles.external]\nmodel = "keep-external"\nmodel_provider = "llm-gateway"\n'
                '[agents.reviewer]\nconfig_file = "keep-reviewer.toml"\n')
            subprocess.run([str(SCRIPT), "save", "--source", str(source), "--target", str(shared)], check=True)
            saved = tomllib.loads(shared.read_text())
            self.assertNotIn("unmanaged", saved["features"])
            for feature in ("context_management", "step_model_switching", "mcp_2026_07_28"):
                self.assertIs(saved["features"][feature], True)
            for _ in range(2):
                subprocess.run([str(SCRIPT), "apply", "--source", str(shared), "--target", str(target)], check=True)
                data = tomllib.loads(target.read_text())
                self.assertEqual(data["model"], "gpt-6-astra")
                self.assertEqual(data["model_reasoning_effort"], "medium")
                self.assertIs(data["features"]["unmanaged"], True)
                self.assertIs(data["features"]["memories"], False)
                for feature in ("context_management", "step_model_switching", "mcp_2026_07_28"):
                    self.assertIs(data["features"][feature], True)
                self.assertEqual(data["profiles"]["external"]["model"], "keep-external")
                self.assertEqual(data["agents"]["reviewer"]["config_file"], "keep-reviewer.toml")
                self.assertEqual(data["personality"], "pragmatic")


if __name__ == "__main__":
    unittest.main()
