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
model_picker_providers = ["llm-gateway", "kimi", "minimax-direct", "openai-oauth", "ollama-cloud"]
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

[providers.ollama-cloud]
type = "open-ai-compatible"
base_url = "https://ollama.com/v1"
auth = "bearer"
api_key_env = "OLLAMA_API_KEY"
env_file = "ollama-cloud.env"
default_model = "glm-5.2"
requires_api_key = true
provider_routing = false
allow_provider_pinning = false
model_catalog = true

[[providers.ollama-cloud.models]]
id = "glm-5.2"

[providers.byteplus-ark]
type = "open-ai-compatible"
base_url = "https://ark.ap-southeast.bytepluses.com/api/coding/v3"
auth = "bearer"
api_key_env = "BYTEPLUS_ARK_API_KEY"
env_file = "byteplus-ark.env"
default_model = "ark-code-latest"
model_catalog = false

[[providers.byteplus-ark.models]]
id = "ark-code-latest"
context_window = 262144
input = ["text"]
'''


# J-Code's own TOML writer emits long arrays across several lines. patch_section
# must consume the whole value, not just its first line -- including a bracket
# that only appears inside a quoted string, and a trailing comment.
MULTILINE_LIVE = '''[display]
theme = "dark"

[provider]
default_provider = "old"
model_picker_providers = [
    "old-a",
    "old-b]",  # a bracket inside a string, and a comment
]
stream_idle_timeout_secs = 180

[providers.other]
token = "keep-me"
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


    def test_apply_rewrites_multiline_managed_array_without_stray_continuation(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source = root / "shared-preferences.toml"
            target = root / "config.toml"
            source.write_text(SOURCE)
            target.write_text(MULTILINE_LIVE)

            self.apply(source, target)
            rendered = target.read_text()
            parsed = tomllib.loads(rendered)

            self.assertEqual(
                parsed["provider"]["model_picker_providers"],
                ["llm-gateway", "kimi", "minimax-direct", "openai-oauth", "ollama-cloud"],
            )
            # the stale entries must be gone entirely, not left dangling
            self.assertNotIn("old-a", rendered)
            self.assertNotIn("old-b]", rendered)
            # the key that followed the multi-line array survives
            self.assertEqual(parsed["provider"]["stream_idle_timeout_secs"], 180)
            self.assertEqual(parsed["providers"]["other"]["token"], "keep-me")
            self.assertEqual(parsed["display"]["theme"], "dark")

            self.apply(source, target)
            self.assertEqual(target.read_text(), rendered)

    def test_byteplus_ark_profile_is_managed(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source = root / "shared-preferences.toml"
            target = root / "config.toml"
            source.write_text(SOURCE)
            target.write_text(LIVE)

            self.apply(source, target)
            parsed = tomllib.loads(target.read_text())
            profile = parsed["providers"]["byteplus-ark"]
            self.assertEqual(profile["base_url"], "https://ark.ap-southeast.bytepluses.com/api/coding/v3")
            self.assertEqual(profile["api_key_env"], "BYTEPLUS_ARK_API_KEY")
            self.assertFalse(profile["model_catalog"])
            self.assertEqual(profile["models"], [{"id": "ark-code-latest", "context_window": 262144, "input": ["text"]}])


    def test_apply_consumes_multiline_string_value_of_a_managed_key(self) -> None:
        live = (
            "[display]\n"
            "theme = \"dark\"\n"
            "\n"
            "[provider]\n"
            "default_model = '''\n"
            "junk\n"
            "'''\n"
            "stream_idle_timeout_secs = 180\n"
        )
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source = root / "shared-preferences.toml"
            target = root / "config.toml"
            source.write_text(SOURCE)
            target.write_text(live)

            self.apply(source, target)
            rendered = target.read_text()
            parsed = tomllib.loads(rendered)

            self.assertEqual(parsed["provider"]["default_model"], "llm-gateway:auto")
            self.assertNotIn("junk", rendered)
            self.assertEqual(parsed["provider"]["stream_idle_timeout_secs"], 180)
            self.assertEqual(parsed["display"]["theme"], "dark")

    def test_apply_never_rewrites_a_key_inside_an_unmanaged_multiline_string(self) -> None:
        live = (
            "[provider]\n"
            'note = """\n'
            'model_picker_providers = ["POISON"]\n'
            '"""\n'
            'default_provider = "old"\n'
        )
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source = root / "shared-preferences.toml"
            target = root / "config.toml"
            source.write_text(SOURCE)
            target.write_text(live)

            self.apply(source, target)
            parsed = tomllib.loads(target.read_text())

            # the prose inside the user's string is theirs, not a managed key
            self.assertIn('model_picker_providers = ["POISON"]', parsed["provider"]["note"])
            self.assertEqual(
                parsed["provider"]["model_picker_providers"],
                ["llm-gateway", "kimi", "minimax-direct", "openai-oauth", "ollama-cloud"],
            )
            self.assertEqual(parsed["provider"]["default_provider"], "llm-gateway")

    def test_apply_does_not_split_a_section_on_a_nested_array_line(self) -> None:
        # `    ["c"]` matches SECTION_HEADER; chunks() must not treat it as one.
        live = (
            "[provider]\n"
            "model_picker_providers = [\n"
            '    ["a", "b"],\n'
            '    ["c"]\n'
            "]\n"
            "stream_idle_timeout_secs = 180\n"
        )
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source = root / "shared-preferences.toml"
            target = root / "config.toml"
            source.write_text(SOURCE)
            target.write_text(live)

            self.apply(source, target)
            rendered = target.read_text()
            parsed = tomllib.loads(rendered)

            self.assertEqual(
                parsed["provider"]["model_picker_providers"],
                ["llm-gateway", "kimi", "minimax-direct", "openai-oauth", "ollama-cloud"],
            )
            self.assertNotIn('["c"]', rendered)
            self.assertEqual(parsed["provider"]["stream_idle_timeout_secs"], 180)


if __name__ == "__main__":
    unittest.main()
