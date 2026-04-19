# SKILL: OpenClaw Coding Agent

Delegate coding tasks to other agents (Codex, Claude Code, Pi) using bash-first execution.

## Overview
This skill enables the agent to delegate complex coding tasks, refactoring, or codebase analysis to specialized sub-agents. It leverages the `openclaw` ecosystem for background processing and agent orchestration.

## Capabilities
- **Task Delegation**: Send specific prompts to sub-agents for autonomous execution.
- **Background Processing**: Run agent tasks in the background and monitor progress.
- **Multi-Agent Coordination**: Orchestrate workflows involving multiple agents.
- **Codebase Analysis**: Delegate large-scale codebase understanding to agents with larger context windows.

## Usage Guidelines

### 1. Task Scoping
Clearly define the task and provided context before delegating.
- `cd /path/to/project && openclaw run 'Refactor the auth module'`

### 2. Agent Selection
Choose the appropriate agent for the task based on its strengths (e.g., Claude Code for logic, Codex for snippets).
- `openclaw run --agent claude 'Review this PR'`

### 3. Permission Mode
Use appropriate permission modes when delegating to avoid interactive blocks.
- `claude --permission-mode bypassPermissions --print 'Task description'`

### 4. Verification
Always verify the output of the delegated task before committing.
- Run tests: `npm test`
- Lint check: `npm run lint`

## Best Practices
- **Atomic Tasks**: Break down large tasks into smaller, manageable units for better agent performance.
- **Provide Context**: Include relevant file paths and symbols in the delegation prompt.
- **Monitor Logs**: Check agent logs if a task fails or hangs.
- **Safety First**: Never delegate tasks that involve modifying sensitive security configurations without explicit approval.

## Common Commands
| Task | Command |
| :--- | :--- |
| Delegate refactor | `openclaw run 'Refactor module X'` |
| View agent status | `openclaw status` |
| List available agents | `openclaw agents list` |
| Stop background task | `openclaw stop <task_id>` |

## Error Handling
If an agent fails due to "context window exceeded", try breaking the task into smaller parts. If you see "authentication failed", verify the agent's API keys in the vault.
