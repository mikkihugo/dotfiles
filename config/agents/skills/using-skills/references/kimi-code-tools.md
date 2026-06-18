# Kimi Code Tool Mapping

Skills speak in actions ("dispatch a subagent", "create a todo", "read a file"). On Kimi Code these resolve to the tools below.

## Tools

| Action skills request | Kimi Code tool |
|----------------------|----------------|
| Read a file | `Read` |
| Create a new file | `Write` |
| Edit a file | `Edit` |
| Run a shell command | `Bash` |
| Search file contents | `Grep` |
| Find files by name | `Glob` |
| Fetch a URL | `FetchURL` |
| Search the web | `WebSearch` |
| Invoke a skill | `Skill` |
| Dispatch a subagent | `Agent` (with `subagent_type` parameter: `"coder"`, `"explore"`, or `"plan"`) |
| Multiple parallel dispatches | `AgentSwarm` (with `prompt_template` and `items` array) |
| Task tracking ("create a todo", "mark complete") | `TodoList` |
| Background-process lifecycle (read output, cancel) | `TaskList`, `TaskOutput`, `TaskStop` |
| Structured questions to user | `AskUserQuestion` |
| Goal management | `CreateGoal`, `GetGoal` |
| Scheduled tasks / reminders | `CronCreate`, `CronDelete`, `CronList` |
| Plan mode (implementation planning) | `EnterPlanMode`, `ExitPlanMode` |
| Read media files (images, video) | `ReadMediaFile` |

## Subagent types

Kimi Code's `Agent` tool accepts a `subagent_type` parameter:

- **`coder`** — General-purpose coding agent with full tool access (Bash, Read, Write, Edit, Grep, Glob, WebSearch, FetchURL). Use for implementation, fixing, and any work that edits files or runs commands.
- **`explore`** — Read-only codebase exploration specialist. Fast searches across files and patterns. Use for investigation and understanding codebases without making changes.
- **`plan`** — Read-only implementation planning and architecture design. Use for step-by-step plans and trade-off analysis before code changes.

## Parallel dispatch

`AgentSwarm` launches multiple subagents from one prompt template:

```
prompt_template: "Review {{item}} for regressions"
items: ["src/a.ts", "src/b.ts"]
```

Each item launches one subagent. Use for independent tasks that share no state.

## Instructions file

When a skill mentions "your instructions file", on Kimi Code this is **`AGENTS.md`**. Kimi Code discovers `AGENTS.md` files in the project tree and loads them as agent-specific instructions. Standard locations:

| Scope | Location |
|-------|----------|
| Project root | `./AGENTS.md` |
| Subdirectory | `./<subdir>/AGENTS.md` (takes precedence for files in that subdir) |
| User global | `~/.agents/AGENTS.md` |

Deeper `AGENTS.md` files take precedence over parent directories. User instructions in conversation always take highest precedence.

## Personal skills directory

User-level skills live at **`~/.agents/skills/`**. Each skill is a subdirectory containing a `SKILL.md` (with `name` and `description` frontmatter) plus any supporting files. Project-level skills can also be defined in `.agents/skills/` within the project root.

## Task tracking

Kimi Code's `TodoList` tool manages structured task lists:

```json
{
  "todos": [
    { "title": "Read session-control.ts", "status": "in_progress" },
    { "title": "Add planMode flag", "status": "pending" }
  ]
}
```

Statuses: `pending`, `in_progress`, `done`. Keep exactly one task `in_progress` at a time. Mark done only when fully accomplished.
