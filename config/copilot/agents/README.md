# Custom agents for `/agent` invocation

This directory holds user-defined agents that the Copilot CLI
discovers for `/agent [name]` invocation in the interactive CLI.

It does **not** hold the system prompts for the built-in agent types
used by the `task` tool's `agent_type` field (`explore`, `task`,
`general-purpose`, `rubber-duck`, `code-review`, `research`,
`security-review`). Those system prompts live inside the Copilot CLI
binary and are not user-editable. See `task-prompts.md` in this
directory for the scope briefs that actually produce useful output
when you call `task` against this devbox.

## File layout

| File | Purpose |
|---|---|
| `balanced.agent.md` | Default devbox assistant. Mixed read/edit/search/bash. Three-lane fallback. |
| `cheap-explore.agent.md` | Read-only investigation. Search, source-trace, summarize. |
| `tri-lane.agent.md` | Three-tier routing by task shape (cheap → coordinator → heavyweight). |
| `task-prompts.md` | Per-invocation scope briefs for the `task` tool's `prompt` field. |
| `README.md` | This file. |

## Per-agent model defaults

The `model:` field in each `.agent.md` declares the model's chain.
The chain is tried in order; the CLI picks the first available lane.
Per-agent overrides set in `config/copilot/settings.json` under
`subagents.agents.<agent_type>` take precedence — keep those
consistent with the chains declared here.

## Wiring

Files in this directory are projected to
`/home/mhugo/.copilot/agents/` by the home-manager entry declared in
`home/modules/files.nix` (`".copilot/agents/<file>" =
{ source = ../../config/copilot/agents/<file>; }`). To add a new
agent:

1. Create `<name>.agent.md` here with valid YAML frontmatter
   (`name`, `description`, `model`, `model-policy`, `tools`).
2. Add the matching entry in `home/modules/files.nix`.
3. Activate with `home-manager switch` (or whatever activation
   command the host provides).

Without step 2 the file exists in dotfiles but is not visible to the
harness.

## Why the `.agent.md` format

This is the format the Copilot CLI expects when discovering
user-defined agents. The YAML frontmatter carries:

- `name` — used by `/agent [name]` to address the agent.
- `description` — shown in `/agent` browse list.
- `model` — chain of model aliases; first available wins.
- `model-policy: required` — refuses to substitute models outside
  the declared list, even if a cheaper or "better" alternative is
  visible in the catalog.
- `tools` — explicit allow-list of tools the agent can use. Setting
  `tools: [read, search]` produces a read-only agent.

The body (markdown after the frontmatter) is the agent's system
prompt. It is loaded as part of the agent's identity, not as a
per-invocation brief.

## See also

- `../settings.json` — global Copilot CLI settings, including the
  `subagents.agents.<agent_type>` model map.
- `../copilot-instructions.md` — global instructions loaded every
  session.
- `../hooks/` — event-driven hooks (mailbox-sweep, observations,
  remind-skills, swarm-messages).
- `../../AGENTS.md` — devbox-wide agent doctrine (model tiers,
  forbidden alternatives, operator authority).
