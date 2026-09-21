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

    def test_repairs_replayed_tool_output_ids_by_function_call_order(self):
        compat = load_module()
        payload = {
            "input": [
                {"type": "function_call", "call_id": "call-a"},
                {"type": "function_call_output", "call_id": "grok-call-1", "output": "a"},
                {"type": "function_call", "call_id": "call-b"},
                {"type": "function_call_output", "call_id": "grok-call-2", "output": "b"},
            ]
        }
        normalized = compat.normalize_request_payload(payload)
        self.assertEqual(
            [item["call_id"] for item in normalized["input"] if item["type"] == "function_call_output"],
            ["call-a", "call-b"],
        )

    def test_repairs_empty_and_duplicate_function_call_ids(self):
        compat = load_module()
        payload = {
            "input": [
                {"type": "function_call", "call_id": ""},
                {"type": "function_call", "call_id": "same"},
                {"type": "function_call", "call_id": "same"},
                {"type": "function_call_output", "call_id": "grok-call-1", "output": "a"},
                {"type": "function_call_output", "call_id": "grok-call-2", "output": "b"},
                {"type": "function_call_output", "call_id": "grok-call-3", "output": "c"},
            ]
        }
        normalized = compat.normalize_request_payload(payload)
        calls = [item["call_id"] for item in normalized["input"] if item["type"] == "function_call"]
        outputs = [item["call_id"] for item in normalized["input"] if item["type"] == "function_call_output"]
        self.assertEqual(calls, ["grok-replay-call-0", "same", "same-2"])
        self.assertEqual(outputs, calls)

    def test_strips_reasoning_items_from_nonstream_output(self):
        compat = load_module()
        payload = {
            "id": "resp_x",
            "output": [
                {"type": "reasoning", "summary": [], "content": [{"type": "reasoning_text", "text": "thinking"}]},
                {"type": "message", "role": "assistant", "content": [{"type": "output_text", "text": "answer"}]},
            ],
        }
        normalized = compat.strip_minimax_reasoning_items(payload)
        self.assertEqual([item["type"] for item in normalized["output"]], ["message"])

    def test_reasoning_strip_keeps_payload_without_output(self):
        compat = load_module()
        payload = {"id": "resp_y", "service_tier": "standard"}
        self.assertEqual(compat.strip_minimax_reasoning_items(payload), payload)

    def test_sse_reasoning_text_events_are_dropped(self):
        compat = load_module()
        self.assertIsNone(
            compat.normalize_sse_line(
                'data: {"type": "response.reasoning_text.delta", "delta": "hmm"}\n'
            )
        )
        self.assertIsNone(
            compat.normalize_sse_line(
                'data: {"type": "response.reasoning_text.done", "text": "done thinking"}\n'
            )
        )
        kept = compat.normalize_sse_line('data: {"type": "response.output_text.delta", "delta": "hi"}\n')
        self.assertIsNotNone(kept)
        self.assertEqual(json.loads(kept[6:])["type"], "response.output_text.delta")


if __name__ == "__main__":
    unittest.main()
