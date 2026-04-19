# SKILL: OpenClaw Coding Agent (Orchestration & Peer Review)

Delegate tasks and seek second opinions from specialized agents (Codex, Claude Code, Pi) to ensure architectural integrity and code quality.

## Overview
This skill enables the agent to utilize the `openclaw` ecosystem for both execution and validation. It focuses on using sub-agents as "peer reviewers" to provide second opinions on complex strategies, refactors, or bug fixes before implementation.

## Capabilities
- **Second Opinion**: Invoke a specialized agent to review a proposed implementation plan or architectural decision.
- **Peer Review**: Delegate code review tasks to verify that an implementation meets quality standards.
- **Task Delegation**: Send specific prompts to sub-agents for autonomous execution of heavy-lifting tasks.
- **Multi-Agent Consensus**: Compare outputs from multiple agents to identify the most robust solution.

## Usage Guidelines

### 1. Seeking a Second Opinion (Recommended)
Before executing a high-impact change, ask a sub-agent to critique your plan.
- `openclaw run --agent claude 'Critique this plan for migrating the auth module: <plan_details>'`

### 2. Consensus Synthesis
If a sub-agent provides a diverging opinion:
1.  Analyze the trade-offs between your plan and the second opinion.
2.  Synthesize a "best-of-both" approach or present the options to the user.
3.  Explain the technical rationale for the final choice.

### 3. Permission Mode
Use appropriate permission modes when delegating to avoid interactive blocks.
- `claude --permission-mode bypassPermissions --print 'Task description'`

### 4. Post-Implementation Review
After completing a task, you can seek a final review from another agent to ensure no regressions were introduced.

## Best Practices
- **Explicit Critique**: When asking for a second opinion, specifically ask the agent to "find flaws" or "suggest alternatives" to avoid confirmation bias.
- **Contextual Parity**: Ensure the sub-agent has the same context (file paths, symbols) as you do.
- **Verification**: Always run local tests (`npm test`, `cargo test`) regardless of the agent's confidence.

## Common Commands
| Task | Command |
| :--- | :--- |
| Seek critique | `openclaw run 'Review this strategy for X...'` |
| Peer review code | `openclaw run --agent claude 'Review the changes in src/auth.ts'` |
| View agent status | `openclaw status` |
| List available agents | `openclaw agents list` |

## Error Handling
If agents provide conflicting advice that cannot be reconciled, defer to the user with a summary of the disagreement.
