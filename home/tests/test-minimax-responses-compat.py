import importlib.util
import json
import pathlib
import unittest


ROOT = pathlib.Path(__file__).parents[1]
SCRIPT = ROOT / "modules" / "minimax-responses-compat.py"


def load_module():
    spec = importlib.util.spec_from_file_location("compat", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class ResponsesCompatTests(unittest.TestCase):
    def test_does_not_duplicate_v1_upstream_prefix(self):
        compat = load_module()
        parsed, path = compat.upstream_target("/v1/responses")
        self.assertEqual(parsed.netloc, "api.minimax.io")
        self.assertEqual(path, "/v1/responses")

    def test_normalizes_only_standard_service_tier(self):
        compat = load_module()
        payload = {
            "id": "resp_1",
            "service_tier": "standard",
            "output": [{"type": "reasoning", "summary": []}],
        }
        self.assertEqual(compat.normalize_payload(payload)["service_tier"], "default")
        self.assertEqual(compat.normalize_payload(payload)["output"], payload["output"])

    def test_normalizes_null_annotations_for_grok(self):
        compat = load_module()
        payload = {"reasoning": {"effort": None, "summary": None}, "output": [{"content": [{"annotations": None}]}]}
        normalized = compat.normalize_payload(payload)
        self.assertIsNone(normalized["reasoning"]["summary"])
        self.assertEqual(normalized["output"][0]["content"][0]["annotations"], [])

    def test_adds_missing_output_token_details(self):
        compat = load_module()
        payload = {"usage": {"input_tokens": 1, "output_tokens": 2, "total_tokens": 3}}
        normalized = compat.normalize_payload(payload)
        self.assertEqual(normalized["usage"]["output_tokens_details"], {"reasoning_tokens": 0})

    def test_models_v2_catalog_has_configured_profile(self):
        compat = load_module()
        catalog = compat.models_v2_payload()
        self.assertEqual(catalog["object"], "list")
        self.assertEqual(catalog["data"][0]["id"], "minimax-m3-responses")

    def test_rewrites_sse_data_without_touching_done_or_nonstandard(self):
        compat = load_module()
        event = json.dumps({"service_tier": "standard", "id": "resp_2"})
        self.assertEqual(
            json.loads(compat.normalize_sse_line(f"data: {event}")[6:])["service_tier"],
            "default",
        )
        self.assertEqual(compat.normalize_sse_line("data: [DONE]"), "data: [DONE]")
        other = json.dumps({"service_tier": "priority"})
        self.assertEqual(
            json.loads(compat.normalize_sse_line(f"data: {other}")[6:])["service_tier"],
            "priority",
        )


if __name__ == "__main__":
    unittest.main()
