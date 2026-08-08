#!/usr/bin/env python3
import os
import stat
import subprocess
import sys
import tempfile
import tomllib
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("jcode-preferences")


SOURCE = '''[provider]
default_provider = "llm-gateway"
default_model = "llm-gateway:auto"
model_picker_providers = ["llm-gateway", "kimi", "minimax-direct", "openai-oauth"]
cross_provider_failover = "manual"

[auth]
trusted_external_sources = []
trusted_external_source_paths = []

[providers.llm-gateway]
type = "open-ai-compatible"
base_url = "https://llm-gateway.centralcloud.com/v1"
api_key_env = "JCODE_PROVIDER_LLM_GATEWAY_API_KEY"
model_catalog = true

[[providers.llm-gateway.models]]
id = "auto"

[providers.minimax-direct]
type = "open-ai-compatible"
base_url = "https://api.minimax.io/v1"
api_key_env = "MINIMAX_API_KEY"
default_model = "MiniMax-M3"
'''


LIVE = '''[display]
theme = "dark"

[provider]
default_provider = "old"
preserve_reasoning_context = true
model_picker_providers = ["old"]

[auth]
trusted_external_sources = ["cursor"]
keep_existing_login = true

[providers.llm-gateway]
base_url = "https://stale.example/v1"
obsolete = true

[[providers.llm-gateway.models]]
id = "stale"

[providers.minimax-direct]
base_url = "https://stale-minimax.example/v1"
obsolete = true

[providers.other]
token = "keep-me"
'''


class JcodePreferencesTest(unittest.TestCase):
    def apply(self, source: Path, target: Path) -> None:
        subprocess.run(
            [sys.executable, str(SCRIPT), "apply", "--source", str(source), "--target", str(target)],
            check=True,
        )

    def test_apply_preserves_unowned_config_replaces_profiles_and_is_idempotent(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source = root / "shared-preferences.toml"
            target = root / "config.toml"
            source.write_text(SOURCE)
            target.write_text(LIVE)
            target.chmod(0o640)

            self.apply(source, target)
            first = target.read_text()
            parsed = tomllib.loads(first)

            self.assertEqual(parsed["display"]["theme"], "dark")
            self.assertTrue(parsed["provider"]["preserve_reasoning_context"])
            self.assertEqual(parsed["provider"]["default_provider"], "llm-gateway")
            self.assertEqual(parsed["auth"]["keep_existing_login"], True)
            self.assertEqual(parsed["auth"]["trusted_external_sources"], [])
            self.assertEqual(parsed["providers"]["other"]["token"], "keep-me")
            self.assertNotIn("obsolete", parsed["providers"]["llm-gateway"])
            self.assertNotIn("obsolete", parsed["providers"]["minimax-direct"])
            self.assertEqual(parsed["providers"]["llm-gateway"]["models"], [{"id": "auto"}])
            self.assertEqual(parsed["providers"]["minimax-direct"]["default_model"], "MiniMax-M3")
            self.assertEqual(stat.S_IMODE(target.stat().st_mode), 0o640)

            self.apply(source, target)
            self.assertEqual(target.read_text(), first)


if __name__ == "__main__":
    unittest.main()
