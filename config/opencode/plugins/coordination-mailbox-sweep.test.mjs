import assert from "node:assert/strict";
import { describe, test } from "node:test";

import { deriveIdentity, validateIdentity } from "../../codex/hooks/coordination-mailbox-sweep.mjs";
import { tokenFromSessionId } from "./coordination-mailbox-sweep.js";

// ---------------------------------------------------------------------------
// opencode plugin contract: tokenFromSessionId MUST produce the same identity
// deriveIdentity would produce for the same session id, so peers addressing
// the literal short id (e.g. coordination_post --recipient opencode-abcd1234)
// reach the session whose plugin cached that identity. A divergence silently
// strands incoming mail, which is the regression class deriveIdentity's own
// header already documents once (the sha256-of-UUID regression, 2026-09-05).
// ---------------------------------------------------------------------------

describe("opencode plugin tokenFromSessionId matches deriveIdentity", () => {
  test("UUID-shaped session id with dashes -> literal first hex group", () => {
    const sessionId = "674f9a3f-fffa-4573-8c52-50cbb1b3b1c7";
    const expected = deriveIdentity("opencode", { session_id: sessionId }, {});
    const actual = `opencode-${tokenFromSessionId(sessionId)}`;
    assert.equal(actual, expected, `plugin=${actual} deriveIdentity=${expected}`);
  });

  test("owner-ref-style session id (single dash) -> literal first segment", () => {
    const sessionId = "674f9a3f-eng-swarm-bus";
    const expected = deriveIdentity("opencode", { session_id: sessionId }, {});
    const actual = `opencode-${tokenFromSessionId(sessionId)}`;
    assert.equal(actual, expected);
  });

  test("no-dash verbatim session id (matches identity.rs: no forced truncation)", () => {
    const sessionId = "abcdef0123456789";
    const expected = deriveIdentity("opencode", { session_id: sessionId }, {});
    const actual = `opencode-${tokenFromSessionId(sessionId)}`;
    assert.equal(actual, expected);
  });

  test("leading-dash degenerate falls back to first 8 normalized chars", () => {
    const sessionId = "-abcdef0123456789";
    const expected = deriveIdentity("opencode", { session_id: sessionId }, {});
    const actual = `opencode-${tokenFromSessionId(sessionId)}`;
    assert.equal(actual, expected);
  });

  test("empty / null / undefined session id falls back to '0000' (no crash)", () => {
    for (const bad of ["", null, undefined]) {
      assert.equal(tokenFromSessionId(bad), "0000");
    }
  });

  test("session id with only non-alphanumeric dashes falls back to '0000'", () => {
    const sessionId = "---";
    const expected = deriveIdentity("opencode", { session_id: sessionId }, {});
    const actual = `opencode-${tokenFromSessionId(sessionId)}`;
    assert.equal(actual, expected);
  });

  test("cached identity passes validateIdentity (downstream principal pattern)", () => {
    for (const sessionId of [
      "674f9a3f-fffa-4573-8c52-50cbb1b3b1c7",
      "674f9a3f-eng-swarm-bus",
      "abcdef0123456789",
      "-abcdef0123456789",
      "---",
      "",
    ]) {
      const identity = `opencode-${tokenFromSessionId(sessionId)}`;
      assert.doesNotThrow(
        () => validateIdentity(identity),
        `validateIdentity should accept ${identity}`,
      );
    }
  });
});
