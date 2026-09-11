// coordination-mailbox-sweep — opencode plugin
//
// opencode's plugin API has only the generic event(input) dispatcher — there
// is NO separate `hooks/` directory or settings.json wiring (codex/claude/
// cursor have those). All hook behaviour lives in plugins placed under
// `.opencode/plugins/` (project) or `~/.config/opencode/plugins/` (global).
//
// This plugin wires opencode into the same canonical
// coordination-mailbox-sweep.mjs that the other clients shell out to. Three
// opencode events are used, each mapping to a hook contract the .mjs already
// supports:
//
//   shell.env           : inject REPO_MEMORY_COORDINATION_BUS=1 and
//                         REPO_MEMORY_SWARM_CONSUMER into every child shell
//                         so any nested process inherits a valid identity.
//                         Opencode gives us no equivalent of CODEX_THREAD_ID,
//                         so this is the only stable way to give the .mjs
//                         a session-unique identity.
//
//   session.created     : SessionStart equivalent. Caches the opencode
//                         session id (Session.id) and fires the initial
//                         sweep. From here on the cached identity flows
//                         into every shell via the shell.env handler.
//
//   tool.execute.before : UserPromptSubmit equivalent. Fires before every
//                         tool call the agent issues; the .mjs's sweep
//                         polls for unread mailbox messages and surfaces
//                         them to stdout, which opencode's `$` helper
//                         displays in the TUI output panel.
//
// `< /dev/null` is required on every $`-spawned invocation: the .mjs's
// main() awaits stdin until EOF. Codex/claude/cursor invoke it through
// their hook harness with the payload on stdin then close stdin; opencode's
// `$` shell helper spawns the script with the opencode TUI pty attached as
// stdin and never closes it, so without the redirect the script hangs in
// epoll_wait forever — observed 2026-09-10: two hung processes at 14 min
// each, state S<l+, blocking session.created.

const SWEEP_PATH =
  process.env.COORDINATION_MAILBOX_SWEEP_PATH ||
  "/home/mhugo/.codex/hooks/coordination-mailbox-sweep.mjs";

/**
 * Mirror of deriveIdentity()'s short-token extraction in
 * coordination-mailbox-sweep.mjs: literal first dash-segment of the
 * session id, normalized to ASCII alphanumerics, with the same fallback
 * chain (no-dash verbatim, then first 8 normalized chars, then "0000").
 *
 * MUST stay in lock-step with the .mjs — peers address us by the literal
 * short id derived this way (e.g. `coordination_post --recipient
 * opencode-abcd1234`), so a divergence silently strands incoming mail.
 *
 * Exported for the contract test below; not used by the plugin runtime.
 */
export function tokenFromSessionId(sessionId) {
  const raw = String(sessionId ?? "").trim();
  if (!raw) return "0000";
  const firstSegment = raw.split("-")[0]?.replace(/[^A-Za-z0-9]+/g, "") ?? "";
  return (
    firstSegment ||
    raw.replace(/[^A-Za-z0-9]+/g, "").slice(0, 8) ||
    "0000"
  );
}

// Module-scope cache: the opencode session token computed at
// session.created, consumed by every shell.env injection so child
// processes see the same REPO_MEMORY_SWARM_CONSUMER.
//
// One per opencode client lifetime. opencode's TUI runs one session at a
// time, so a per-process cache is correct; a multi-session desktop or
// web client would need a Map<sessionId, identity> keyed off
// event.properties.info.id, but the wire surface today is single-session.
let cachedIdentity = null;

export const CoordinationMailboxSweep = async ({ $ }) => {
  const sweep = async (eventName) => {
    if (!cachedIdentity) return;
    try {
      await $`REPO_MEMORY_COORDINATION_BUS=1 REPO_MEMORY_SWARM_CONSUMER=${cachedIdentity} ${SWEEP_PATH} opencode ${eventName} < /dev/null`;
    } catch {
      // Never fail the session over a sweep error — same contract as
      // the other clients' hooks (they always exit 0).
    }
  };

  return {
    event: async ({ event }) => {
      if (event.type !== "session.created") return;
      const sessionId = event?.properties?.info?.id;
      cachedIdentity = `opencode-${tokenFromSessionId(sessionId)}`;
      await sweep("SessionStart");
    },

    "shell.env": async (_input, output) => {
      if (!cachedIdentity) return;
      // Add-only: do NOT overwrite an env var the user set explicitly.
      // The .mjs honours REPO_MEMORY_SWARM_CONSUMER as the highest-
      // precedence identity source, so an operator-override wins by
      // being injected first by opencode before this hook fires.
      output.env.REPO_MEMORY_COORDINATION_BUS ??= "1";
      output.env.REPO_MEMORY_SWARM_CONSUMER ??= cachedIdentity;
    },

    "tool.execute.before": async () => {
      await sweep("UserPromptSubmit");
    },
  };
};
