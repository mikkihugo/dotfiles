# SKILL: GitHub Operations

Manage GitHub repositories, issues, pull requests, and CI/CD workflows using the `gh` CLI.

## Overview
This skill enables the agent to interact with GitHub for version control workflows, project management, and automation monitoring. It covers the full lifecycle of a contribution from issue identification to PR merge.

## Capabilities
- **Issue Management**: Create, list, close, and comment on issues.
- **Pull Request Management**: Create, review, merge, and check status of PRs.
- **Workflow Monitoring**: View CI/CD run status and retrieve workflow logs.
- **Repository Management**: Clone, fork, and manage repository settings.
- **API Access**: Execute complex queries via the GitHub GraphQL or REST APIs.

## Usage Guidelines

### 1. Verification
Check your authentication status and current repository context.
- `gh auth status`
- `gh repo view`

### 2. PR Workflow
When working on a feature or fix:
1. Create a branch: `git checkout -b feature/name`
2. Commit changes: `git commit -m "feat: description"`
3. Push and create PR: `gh pr create --title "feat: description" --body "Details..."`
4. Check CI: `gh pr checks`

### 3. Issue Triage
- List issues: `gh issue list`
- View details: `gh issue view <number>`
- Comment: `gh issue comment <number> --body "I've investigated this..."`

### 4. CI/CD Monitoring
- List recent runs: `gh run list`
- View run logs: `gh run view <run_id> --log`

## Best Practices
- **PR Descriptions**: Always provide a clear and concise description of the changes in the PR body.
- **Review Readiness**: Ensure that CI checks pass before asking for a review or attempting to merge.
- **Branch Naming**: Use descriptive branch names (e.g., `fix/bug-description`, `feat/feature-name`).
- **Secret Protection**: Never commit secrets to the repository. Use GitHub Secrets for CI/CD environments.

## Common Commands
| Task | Command |
| :--- | :--- |
| List PRs | `gh pr list` |
| Check PR status | `gh pr checks` |
| View issue | `gh issue view <id>` |
| Create PR | `gh pr create` |
| Merge PR | `gh pr merge --merge` |
| View workflow runs | `gh run list` |

## Error Handling
If a command fails with "not authenticated", run `gh auth login`. If you receive a 403 (Forbidden), verify your permissions on the repository.
