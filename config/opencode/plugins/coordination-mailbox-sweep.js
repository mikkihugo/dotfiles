// coordination-mailbox-sweep — opencode plugin
//
// opencode's plugin API (verified against opencode.ai/docs/plugins and the
// installed @opencode-ai/sdk type defs, EventSessionCreated) has no
// per-prompt "before send" hook, only a generic event(input) dispatcher over
// the same server event stream the SDK types describe. This plugin covers
// session.created only (opencode's SessionStart equivalent); there is no
// UserPromptSubmit-equivalent sweep here, unlike the other clients wired to
// coordination-mailbox-sweep.mjs.
//
// It shells out to the existing, already-tested hook implementation instead
// of reimplementing the repo-memory bus protocol.
export const CoordinationMailboxSweep = async ({ $ }) => {
  return {
    event: async ({ event }) => {
      if (event.type !== "session.created") return;
      try {
        await $`/home/mhugo/.codex/hooks/coordination-mailbox-sweep.mjs opencode SessionStart`;
      } catch {
        // Never fail the session over a sweep error — same contract as the
        // other clients' hooks (they always exit 0).
      }
    },
  };
};
