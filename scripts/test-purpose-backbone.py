#!/usr/bin/env python3
"""Contract proof for the canonical agent Purpose backbone and jcode routing."""

import subprocess
import tempfile
import tomllib
import unittest
from pathlib import Path


ROOT = Path(__file__).parents[1]
CANONICAL = ROOT / "config/agents/purpose-backbone.md"


class PurposeBackboneTest(unittest.TestCase):
    def test_canonical_doctrine_is_in_codex_and_overlay_projection(self):
        doctrine = CANONICAL.read_text()
        for name in ("config.toml", "shared-preferences.toml"):
            instructions = tomllib.loads((ROOT / "config/codex" / name).read_text())["developer_instructions"]
            self.assertEqual(instructions, doctrine)

        providers = (ROOT / "home/modules/jcode-providers.nix").read_text()
        self.assertIn("builtins.readFile ../../config/agents/purpose-backbone.md", providers)
        self.assertIn('home.file.".jcode/prompt-overlay.md"', providers)
        self.assertIn("Act, don't ask", providers)
        self.assertIn("Verify live state before claiming", providers)
        activation = (ROOT / "home/modules/activation.nix").read_text()
        self.assertIn('--backbone "${../../config/agents/purpose-backbone.md}"', activation)

    def test_swarm_prompt_has_current_routes_and_no_umans(self):
        prompt = (ROOT / "config/jcode/swarm-prompt.md").read_text()
        self.assertNotIn("umans", prompt.lower())
        self.assertIn("direct `minimax:MiniMax-M3`", prompt)
        self.assertIn("direct `kimi:k3`", prompt)
        self.assertIn("ollama-cloud:glm-5.3", prompt)

    def test_codex_apply_uses_canonical_doctrine_when_source_is_managed(self):
        with tempfile.TemporaryDirectory() as tmp:
            temp_root = Path(tmp)
            target = temp_root / "config.toml"
            source = temp_root / "shared.toml"
            source.write_text('developer_instructions = "stale"\n')
            target.write_text('developer_instructions = "stale"\n')
            subprocess.run([
                str(ROOT / "scripts/codex-preferences"), "apply",
                "--source", str(source), "--target", str(target),
                "--backbone", str(CANONICAL),
            ], check=True)
            self.assertEqual(tomllib.loads(target.read_text())["developer_instructions"], CANONICAL.read_text())


if __name__ == "__main__":
    unittest.main()
