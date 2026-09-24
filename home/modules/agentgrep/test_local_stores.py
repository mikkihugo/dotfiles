"""Fixture-based tests for the kimi-code, qoder, and jcode adapters/catalog.

Uses synthetic fixture files, never real transcripts, so these tests are
safe to run against any machine and carry no user conversation content.
"""

from __future__ import annotations

import json
import pathlib

import pytest

from agentgrep.adapters import PARSER_REGISTRY
from agentgrep.adapters.jcode import parse_jcode_prompt_history, parse_jcode_session_file
from agentgrep.adapters.kimi_code import (
    parse_kimi_session_transcript,
    parse_kimi_tool_activity,
)
from agentgrep.adapters.qoder import (
    parse_qoder_conversation_history_file,
    parse_qoder_session_file,
)
from agentgrep.discovery import (
    discover_jcode_sources,
    discover_kimi_code_sources,
    discover_qoder_sources,
)
from agentgrep.records import AGENT_CHOICES, ITER_SOURCE_RECORD_ADAPTERS, BackendSelection
from agentgrep.records import SourceHandle
from agentgrep.store_catalog import CATALOG


def _handle(agent, store, adapter_id, path: pathlib.Path, *, path_kind="session_file", source_kind="jsonl"):
    return SourceHandle(
        agent=agent,
        store=store,
        adapter_id=adapter_id,
        path=path,
        path_kind=path_kind,
        source_kind=source_kind,
        search_root=None,
        mtime_ns=path.stat().st_mtime_ns,
    )


# --- catalog/registry consistency ------------------------------------------


def test_new_agents_are_registered_choices():
    for agent in ("kimi-code", "qoder", "jcode"):
        assert agent in AGENT_CHOICES


def test_every_new_discovery_spec_has_a_registered_parser():
    for descriptor in CATALOG.stores:
        if descriptor.agent not in ("kimi-code", "qoder", "jcode"):
            continue
        for spec in descriptor.discovery:
            assert spec.adapter_id in PARSER_REGISTRY, spec.adapter_id
            assert spec.adapter_id in ITER_SOURCE_RECORD_ADAPTERS, spec.adapter_id


# --- kimi-code ---------------------------------------------------------------


def _write_kimi_session(tmp_path: pathlib.Path) -> pathlib.Path:
    session_dir = tmp_path / ".kimi-code" / "sessions" / "wd_demo_abc123" / "session_deadbeef"
    agent_dir = session_dir / "agents" / "main"
    agent_dir.mkdir(parents=True)
    (session_dir / "state.json").write_text(
        json.dumps({"cwd": "/home/demo/project", "title": "demo incident"}),
    )
    wire_lines = [
        {
            "type": "context.append_message",
            "agentId": "main",
            "message": {"role": "user", "content": [{"type": "text", "text": "check lh-hostroot now"}]},
            "time": 1000,
        },
        {
            "type": "context.append_loop_event",
            "event": {
                "type": "content.part",
                "part": {"type": "text", "text": "Looking into lh-hostroot."},
            },
            "time": 1001,
        },
        {
            "type": "context.append_loop_event",
            "event": {
                "type": "content.part",
                "part": {"type": "think", "think": "private reasoning about lh-hostroot"},
            },
            "time": 1002,
        },
        {
            "type": "context.append_loop_event",
            "event": {
                "type": "tool.call",
                "name": "Bash",
                "toolCallId": "call_1",
                "args": {"command": "grep lh-hostroot /var/log"},
            },
            "time": 1003,
        },
        {
            "type": "context.append_loop_event",
            "event": {
                "type": "tool.result",
                "toolCallId": "call_1",
                "result": {"output": "found lh-hostroot in /var/log/syslog"},
            },
            "time": 1004,
        },
    ]
    wire_path = agent_dir / "wire.jsonl"
    wire_path.write_text("\n".join(json.dumps(line) for line in wire_lines) + "\n")
    tool_results_dir = agent_dir / "tool-results"
    tool_results_dir.mkdir()
    (tool_results_dir / "Bash-call_2-uuid.txt").write_text("spillover output mentioning lh-hostroot\n")
    tasks_dir = agent_dir / "tasks" / "bash-taskid"
    tasks_dir.mkdir(parents=True)
    (tasks_dir / "output.log").write_text("background task log mentioning lh-hostroot\n")
    return wire_path


def test_kimi_session_transcript_surfaces_user_and_assistant_text(tmp_path):
    wire_path = _write_kimi_session(tmp_path)
    source = _handle("kimi-code", "kimi-code.sessions", "kimi_code.sessions_jsonl.v1", wire_path)
    records = list(parse_kimi_session_transcript(source))
    assert [(r.role, r.kind) for r in records] == [("user", "prompt"), ("assistant", "history")]
    assert all(r.origin is not None and r.origin.cwd == "/home/demo/project" for r in records)
    assert all(r.title == "demo incident" for r in records)
    assert "lh-hostroot" in records[0].text
    assert "lh-hostroot" in records[1].text
    # Reasoning ("think") and tool traffic must not leak into the primary transcript.
    assert not any("private reasoning" in r.text for r in records)
    assert not any("found lh-hostroot in /var/log" in r.text for r in records)


def test_kimi_tool_activity_surfaces_tool_call_result_and_reasoning(tmp_path):
    wire_path = _write_kimi_session(tmp_path)
    source = _handle("kimi-code", "kimi-code.tool_activity", "kimi_code.tool_activity_jsonl.v1", wire_path)
    records = list(parse_kimi_tool_activity(source))
    texts = [r.text for r in records]
    assert any("call_1" in (r.metadata.get("tool_call_id") or "") for r in records)
    assert any("found lh-hostroot in /var/log/syslog" in text for text in texts)
    assert any("private reasoning about lh-hostroot" in text for text in texts)
    assert any(r.metadata.get("reasoning") is True for r in records)
    # The user prompt / assistant reply must not be duplicated here.
    assert not any(text == "check lh-hostroot now" for text in texts)


def test_kimi_tool_result_file_and_discovery(tmp_path):
    _write_kimi_session(tmp_path)
    backends = BackendSelection(find_tool=None, grep_tool=None, json_tool=None)
    sources = discover_kimi_code_sources(tmp_path, backends, include_non_default=True)
    by_store = {}
    for source in sources:
        by_store.setdefault(source.store, []).append(source)
    assert len(by_store["kimi-code.sessions"]) == 1
    assert len(by_store["kimi-code.tool_activity"]) == 1
    assert len(by_store["kimi-code.tool_result_files"]) == 1
    assert len(by_store["kimi-code.task_output_files"]) == 1
    spillover = by_store["kimi-code.tool_result_files"][0]
    record = next(iter(PARSER_REGISTRY[spillover.adapter_id].parser(spillover)))
    assert "lh-hostroot" in record.text
    task_output = by_store["kimi-code.task_output_files"][0]
    task_record = next(iter(PARSER_REGISTRY[task_output.adapter_id].parser(task_output)))
    assert "lh-hostroot" in task_record.text


def test_kimi_code_missing_home_yields_no_sources(tmp_path):
    backends = BackendSelection(find_tool=None, grep_tool=None, json_tool=None)
    assert discover_kimi_code_sources(tmp_path, backends) == []


# --- qoder -------------------------------------------------------------------


def test_qoder_session_file_extracts_role_text_and_cwd(tmp_path):
    project_dir = tmp_path / ".qoder" / "projects" / "-home-demo-project"
    project_dir.mkdir(parents=True)
    session_path = project_dir / "11111111-1111-1111-1111-111111111111.jsonl"
    lines = [
        {"type": "workspace-directories", "sessionId": "s1", "directories": ["/home/demo/project"]},
        {
            "type": "user",
            "uuid": "u1",
            "sessionId": "s1",
            "cwd": "/home/demo/project",
            "message": {"role": "user", "content": "investigate lh-hostroot"},
        },
        {
            "type": "assistant",
            "uuid": "a1",
            "sessionId": "s1",
            "cwd": "/home/demo/project",
            "message": {"role": "assistant", "content": "lh-hostroot looks like a rogue pod"},
        },
    ]
    session_path.write_text("\n".join(json.dumps(line) for line in lines) + "\n")
    source = _handle("qoder", "qoder.sessions", "qoder.sessions_jsonl.v1", session_path)
    records = list(parse_qoder_session_file(source))
    assert [r.kind for r in records] == ["prompt", "history"]
    assert all(r.origin is not None and r.origin.cwd == "/home/demo/project" for r in records)
    # The generic message-candidate walk reads role/text off the nested
    # ``message`` object, which carries no session id of its own -- the
    # outer envelope's ``sessionId`` is not visible from there (matching
    # how ``claude.projects`` behaves on the same shape). ``conversation_id``
    # falls back reliably to the transcript file's own uuid stem instead.
    assert all(r.session_id is None for r in records)
    assert all(r.conversation_id == session_path.stem for r in records)


def test_qoder_conversation_history_file(tmp_path):
    conv_dir = tmp_path / ".qoder" / "cache" / "projects" / "demo-aabbccdd" / "conversation-history" / "1a2b3c4d"
    conv_dir.mkdir(parents=True)
    conv_path = conv_dir / "1a2b3c4d.jsonl"
    lines = [
        {"role": "user", "message": {"content": [{"type": "text", "text": "what is lh-hostroot"}]}},
        {"role": "assistant", "message": {"content": [{"type": "text", "text": "lh-hostroot is a static pod"}]}},
    ]
    conv_path.write_text("\n".join(json.dumps(line) for line in lines) + "\n")
    source = _handle(
        "qoder",
        "qoder.conversation_history",
        "qoder.conversation_history_jsonl.v1",
        conv_path,
    )
    records = list(parse_qoder_conversation_history_file(source))
    assert [r.role for r in records] == ["user", "assistant"]
    assert all(r.conversation_id == "1a2b3c4d" for r in records)


def test_qoder_discovery_finds_both_stores(tmp_path):
    project_dir = tmp_path / ".qoder" / "projects" / "-home-demo"
    project_dir.mkdir(parents=True)
    (project_dir / "s1.jsonl").write_text(
        json.dumps({"type": "user", "sessionId": "s1", "cwd": "/home/demo", "message": {"role": "user", "content": "hi"}})
        + "\n",
    )
    conv_dir = tmp_path / ".qoder" / "cache" / "projects" / "demo-aabbccdd" / "conversation-history" / "c1"
    conv_dir.mkdir(parents=True)
    (conv_dir / "c1.jsonl").write_text(
        json.dumps({"role": "user", "message": {"content": [{"type": "text", "text": "hi"}]}}) + "\n",
    )
    backends = BackendSelection(find_tool=None, grep_tool=None, json_tool=None)
    sources = discover_qoder_sources(tmp_path, backends)
    stores = {s.store for s in sources}
    assert stores == {"qoder.sessions", "qoder.conversation_history"}


# --- jcode ---------------------------------------------------------------


def test_jcode_prompt_history_reads_bare_json_strings(tmp_path):
    path = tmp_path / "prompt-history.jsonl"
    path.write_text('"first prompt"\n"lh-hostroot lookup"\n')
    source = _handle("jcode", "jcode.prompt_history", "jcode.prompt_history_jsonl.v1", path, path_kind="history_file")
    records = list(parse_jcode_prompt_history(source))
    assert [r.text for r in records] == ["first prompt", "lh-hostroot lookup"]
    assert all(r.kind == "prompt" for r in records)


def test_jcode_session_file_does_not_confuse_message_id_with_session_id(tmp_path):
    session_id = "session_demo_1234_aaaa"
    payload = {
        "id": session_id,
        "title": "incident triage",
        "working_dir": "/home/demo/code/proj",
        "model": "demo-model",
        "messages": [
            {
                "id": "message_should_not_leak_as_session_id",
                "role": "user",
                "content": [{"type": "text", "text": "any sign of lh-hostroot?"}],
                "timestamp": "2026-01-01T00:00:00Z",
            },
            {
                "id": "message_2",
                "role": "assistant",
                "content": [{"type": "text", "text": "yes, lh-hostroot showed up in the pod list"}],
                "timestamp": "2026-01-01T00:00:01Z",
            },
        ],
    }
    path = tmp_path / f"{session_id}.json"
    path.write_text(json.dumps(payload))
    source = _handle("jcode", "jcode.sessions", "jcode.sessions_json.v1", path, source_kind="json")
    records = list(parse_jcode_session_file(source))
    assert len(records) == 2
    for record in records:
        assert record.session_id == session_id
        assert record.conversation_id == session_id
        assert record.session_id != "message_should_not_leak_as_session_id"
        assert record.origin is not None
        assert record.origin.cwd == "/home/demo/code/proj"
        assert record.title == "incident triage"
    assert records[0].kind == "prompt"
    assert records[1].kind == "history"


def test_jcode_discovery_reads_json_and_bak(tmp_path):
    sessions_dir = tmp_path / ".jcode" / "sessions"
    sessions_dir.mkdir(parents=True)
    payload = {
        "id": "session_x_1_a",
        "working_dir": "/home/demo",
        "messages": [{"id": "m1", "role": "user", "content": [{"type": "text", "text": "hi"}]}],
    }
    (sessions_dir / "session_x_1_a.json").write_text(json.dumps(payload))
    (sessions_dir / "session_y_2_b.bak").write_text(json.dumps({**payload, "id": "session_y_2_b"}))
    (tmp_path / ".jcode" / "prompt-history.jsonl").write_text('"hi"\n')
    backends = BackendSelection(find_tool=None, grep_tool=None, json_tool=None)
    sources = discover_jcode_sources(tmp_path, backends)
    session_sources = [s for s in sources if s.store == "jcode.sessions"]
    assert len(session_sources) == 2
    assert {s.path.suffix for s in session_sources} == {".json", ".bak"}
    assert any(s.store == "jcode.prompt_history" for s in sources)


if __name__ == "__main__":
    raise SystemExit(pytest.main([__file__, "-v"]))
