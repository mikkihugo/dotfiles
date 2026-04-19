# SKILL: Automation & Workflow (n8n)

Manage and configure visual workflows and agent orchestration using n8n.

## Overview
This skill provides guidance on building and maintaining automation workflows in n8n. It covers node configuration, webhook integration, and AI agent orchestration.

## Capabilities
- **Workflow Design**: Create and edit visual workflows for data processing and integration.
- **AI Orchestration**: Configure AI nodes (chains, agents, memory) within n8n.
- **Integration**: Connect n8n to external services (Gmail, Outlook, GitHub, Vault).
- **Maintenance**: Monitor workflow execution, errors, and performance.

## Usage Guidelines

### 1. Webhook Security
Always secure n8n webhooks, especially those that trigger sensitive operations.
- Use Authelia or API keys to protect the n8n instance.

### 2. Secrets Management
Use the n8n Credentials system, but ideally pull secrets from a central vault (like OpenBae) where possible.

### 3. Monitoring
- Check the n8n UI for failed executions.
- Monitor resource usage (CPU/RAM) for complex workflows.

## Common Commands
| Task | Command |
| :--- | :--- |
| Check n8n Pods | `kubectl get pods -n n8n` |
| Restart n8n | `kubectl rollout restart deployment n8n` |
| View Logs | `kubectl logs deploy/n8n` |

## Best Practices
- **Atomic Workflows**: Keep workflows focused and modular.
- **Error Handling**: Use "Error Trigger" nodes to catch and notify on workflow failures.
- **Version Control**: Periodically export workflows and commit them to the dotfiles/infra repository.
- **Human-in-the-Loop**: Use n8n to implement approval steps for sensitive AI actions.
