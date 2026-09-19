import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const agents = await readFile("config/codex/AGENTS.md", "utf8");
const managedStart = agents.indexOf("<!-- BEGIN purpose-tool skills");
const handwritten = agents.slice(0, managedStart);

test("Codex uses the persistent hook reader instead of a capability-less direct sweep", () => {
  assert.match(
    handwritten,
    /Home Manager hook.*mailbox reader/i,
    "the managed hook must be the interactive Codex mailbox reader",
  );
  assert.match(
    handwritten,
    /do not call[^.]{0,160}coordination_sweep[^.]{0,160}persisted[^.]{0,160}inbox_uri/is,
    "a direct stateless sweep must require its own persisted capability",
  );
  assert.doesNotMatch(
    handwritten,
    /Every turn start[^.]{0,220}call MCP server[^.]{0,220}coordination_sweep/is,
    "instructions must not require an unsupported capability-less direct sweep",
  );
});

test("hook and direct-reader mailboxes remain isolated and never take over foreign state", () => {
  assert.match(handwritten, /<principal>-hook/i, "hook lane must remain explicit");
  assert.match(
    handwritten,
    /do not\s+retry,\s+claim,\s+delete,\s+or\s+replace\s+a\s+foreign\s+inbox/i,
    "foreign inbox recovery must fail closed",
  );
  assert.match(handwritten, /inbox_uri[^.]{0,120}(?:secret|capability)/i);
});
