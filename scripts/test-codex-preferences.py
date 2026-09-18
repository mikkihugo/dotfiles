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
                'developer_instructions = """Ground claims in evidence.\n'
                'Delegate only independent work.\n"""\n\n'
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
                'status_line_use_colors = true\n\n'
                '[agents.user_specialist]\n'
                'config_file = "keep-user-specialist.toml"\n'
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
            self.assertEqual(
                parsed["developer_instructions"],
                "Ground claims in evidence.\nDelegate only independent work.\n",
            )
            self.assertEqual(parsed["tui"]["status_line"], ["model-with-reasoning", "thread-id"])
            self.assertEqual(parsed["tui"]["terminal_title"], ["activity", "project-name"])
            self.assertTrue(parsed["tui"]["status_line_use_colors"])
            self.assertIn('[projects."/home/mhugo"]', rendered)
            self.assertIn('personality = "pragmatic"', rendered)
            self.assertEqual(parsed["agents"]["user_specialist"]["config_file"], "keep-user-specialist.toml")


    def test_managed_defaults_match_operator_settings(self):
        for name in ("config.toml", "shared-preferences.toml"):
            data = tomllib.loads((SCRIPT.parents[1] / "config/codex" / name).read_text())
            self.assertEqual(data["model"], "gpt-5.6-sol")
            self.assertEqual(data["model_provider"], "openai")
            self.assertEqual(data["model_reasoning_effort"], "medium")
            for feature in ("context_management", "step_model_switching", "mcp_2026_07_28"):
                self.assertIs(data["features"][feature], True)
            self.assertIs(data["features"]["memories"], False)

    def test_otlp_http_exporters_use_signal_specific_collector_paths(self):
        data = tomllib.loads((SCRIPT.parents[1] / "config/codex/config.toml").read_text())
        collector = "http://otel-collector.monitoring.svc.cluster.local:4318"
        self.assertEqual(data["otel"]["exporter"]["otlp-http"]["endpoint"], f"{collector}/v1/logs")
        self.assertEqual(data["otel"]["trace_exporter"]["otlp-http"]["endpoint"], f"{collector}/v1/traces")

    def test_base_developer_instructions_are_pdd_and_adr_0000(self):
        for name in ("config.toml", "shared-preferences.toml"):
            data = tomllib.loads((SCRIPT.parents[1] / "config/codex" / name).read_text())
            instructions = data["developer_instructions"]
            self.assertIn("no behavior change without a PurposeContract", instructions)
            self.assertIn("purpose, consumer, contract, failureBoundary", instructions)
            self.assertIn("ADR-0000 lifecycle", instructions)
            self.assertIn("Contract tests or executable evidence before implementation", instructions)

    def test_subagent_routing_is_explicit_and_least_cost(self):
        root = SCRIPT.parents[1]
        for name in ("config.toml", "shared-preferences.toml"):
            data = tomllib.loads((root / "config/codex" / name).read_text())
            instructions = data["developer_instructions"]
            self.assertIn("least-cost capable model", instructions)
            self.assertIn("Never silently use the default", instructions)
            self.assertIn("model for delegated work", instructions)

        expected = {
            "scout": ("gpt-5.6-luna", "low", "read-only"),
            "implementer": ("gpt-5.6-terra", "medium", "workspace-write"),
            "reviewer": ("gpt-5.6-sol", "high", "read-only"),
        }
        config = tomllib.loads((root / "config/codex/config.toml").read_text())
        for role, (model, effort, sandbox) in expected.items():
            self.assertEqual(config["agents"][role]["config_file"], f"agents/{role}.toml")
            profile = tomllib.loads((root / "config/codex/agents" / f"{role}.toml").read_text())
            self.assertEqual(profile["model_provider"], "openai")
            self.assertEqual(profile["model"], model)
            self.assertEqual(profile["model_reasoning_effort"], effort)
            self.assertEqual(profile["sandbox_mode"], sandbox)

    def test_apply_manages_first_party_agent_roles_without_erasing_user_roles(self):
        root = SCRIPT.parents[1]
        with tempfile.TemporaryDirectory() as tmp:
            target = Path(tmp) / "config.toml"
            target.write_text(
                '[agents.scout]\nconfig_file = "stale.toml"\n\n'
                '[agents.user_specialist]\nconfig_file = "keep-user-specialist.toml"\n'
            )
            subprocess.run(
                [str(SCRIPT), "apply", "--source", str(root / "config/codex/shared-preferences.toml"), "--target", str(target)],
                check=True,
            )
            data = tomllib.loads(target.read_text())
            for role in ("scout", "implementer", "reviewer"):
                self.assertEqual(data["agents"][role]["config_file"], f"agents/{role}.toml")
            self.assertEqual(data["agents"]["user_specialist"]["config_file"], "keep-user-specialist.toml")

    def test_roundtrip_managed_features_preserves_unmanaged_settings(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source, shared, target = (root / name for name in ("source.toml", "shared.toml", "target.toml"))
            source.write_text('model = "gpt-6-astra"\nmodel_reasoning_effort = "medium"\n'
                '[features]\nmemories = false\ncontext_management = true\n'
                'step_model_switching = true\nmcp_2026_07_28 = true\nunmanaged = false\n'
                '[agents.scout]\nconfig_file = "mutable-live-drift.toml"\n')
            target.write_text('model = "gpt-5.6-sol"\nmodel_reasoning_effort = "low"\n'
                'personality = "pragmatic"\n[features]\ncontext_management = false\n'
                'step_model_switching = false\nmcp_2026_07_28 = false\nunmanaged = true\n'
                '[profiles.external]\nmodel = "keep-external"\nmodel_provider = "llm-gateway"\n'
                '[agents.reviewer]\nconfig_file = "keep-reviewer.toml"\n')
            subprocess.run([str(SCRIPT), "save", "--source", str(source), "--target", str(shared)], check=True)
            saved = tomllib.loads(shared.read_text())
            self.assertNotIn("unmanaged", saved["features"])
            self.assertNotIn("agents", saved)
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

    def test_save_preserves_canonical_agent_roles_without_importing_live_drift(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source, shared, target = (root / name for name in ("source.toml", "shared.toml", "target.toml"))
            shared.write_text(
                'model = "gpt-5.6-sol"\n\n'
                '[agents.scout]\n'
                'description = "Canonical scout"\n'
                'config_file = "agents/scout.toml"\n\n'
                '[agents.implementer]\n'
                'description = "Canonical implementer"\n'
                'config_file = "agents/implementer.toml"\n\n'
                '[agents.reviewer]\n'
                'description = "Canonical reviewer"\n'
                'config_file = "agents/reviewer.toml"\n'
            )
            source.write_text(
                'model = "gpt-6-astra"\n\n'
                '[agents.scout]\n'
                'description = "Mutable scout drift"\n'
                'config_file = "agents/live-scout.toml"\n'
                'live_only = true\n\n'
                '[agents.implementer]\n'
                'description = "Mutable implementer drift"\n'
                'config_file = "agents/live-implementer.toml"\n\n'
                '[agents.reviewer]\n'
                'description = "Mutable reviewer drift"\n'
                'config_file = "agents/live-reviewer.toml"\n'
            )

            subprocess.run([str(SCRIPT), "save", "--source", str(source), "--target", str(shared)], check=True)
            saved = tomllib.loads(shared.read_text())
            self.assertEqual(saved["model"], "gpt-6-astra")
            self.assertEqual(saved["agents"]["scout"]["description"], "Canonical scout")
            self.assertEqual(saved["agents"]["scout"]["config_file"], "agents/scout.toml")
            self.assertNotIn("live_only", saved["agents"]["scout"])
            self.assertEqual(saved["agents"]["implementer"]["config_file"], "agents/implementer.toml")
            self.assertEqual(saved["agents"]["reviewer"]["config_file"], "agents/reviewer.toml")

            target.write_text(source.read_text())
            subprocess.run([str(SCRIPT), "apply", "--source", str(shared), "--target", str(target)], check=True)
            applied = tomllib.loads(target.read_text())
            self.assertEqual(applied["agents"]["scout"]["description"], "Canonical scout")
            self.assertEqual(applied["agents"]["scout"]["config_file"], "agents/scout.toml")
            self.assertNotIn("live_only", applied["agents"]["scout"])
            self.assertEqual(applied["agents"]["implementer"]["config_file"], "agents/implementer.toml")
            self.assertEqual(applied["agents"]["reviewer"]["config_file"], "agents/reviewer.toml")


if __name__ == "__main__":
    unittest.main()
