#!/usr/bin/env python3
"""Contract proof for the canonical agent Purpose backbone and jcode routing."""

import unittest
from pathlib import Path


ROOT = Path(__file__).parents[1]
CANONICAL = ROOT / "config/agents/purpose-backbone.md"


class PurposeBackboneTest(unittest.TestCase):
    def test_canonical_doctrine_is_in_jcode_projection(self):
        providers = (ROOT / "home/modules/jcode-providers.nix").read_text()
        self.assertIn("builtins.readFile ../../config/agents/purpose-backbone.md", providers)
        self.assertIn('home.file.".jcode/prompt-overlay.md"', providers)
        self.assertIn("Act, don't ask", providers)
        self.assertIn("Verify live state before claiming", providers)

    def test_swarm_prompt_has_current_routes_and_no_umans(self):
        prompt = (ROOT / "config/jcode/swarm-prompt.md").read_text()
        self.assertNotIn("umans", prompt.lower())
        self.assertIn("direct `minimax:MiniMax-M3`", prompt)
        self.assertIn("direct `kimi:k3`", prompt)
        self.assertIn("ollama-cloud:glm-5.3", prompt)



if __name__ == "__main__":
    unittest.main()
