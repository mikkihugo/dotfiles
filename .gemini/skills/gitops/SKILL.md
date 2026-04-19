# SKILL: GitOps Workflow with Flux CD

Implement and manage GitOps workflows for automated, declarative Kubernetes deployments using Flux CD.

## Overview
GitOps is a set of practices to manage infrastructure and application configurations using Git as the single source of truth. This skill enables the agent to interact with Flux CD components (Source, Kustomize, Helm) to ensure the cluster state matches the Git repository.

## Capabilities
- **Source Management**: Manage `GitRepository`, `OCIRepository`, and `HelmRepository` resources.
- **Kustomize Reconciliation**: Configure `Kustomization` resources for declarative manifest application.
- **Helm Controller**: Manage `HelmRelease` and `HelmChart` for automated Helm deployments.
- **Status Monitoring**: Check reconciliation status, errors, and drift detection.
- **Manual Triggering**: Use annotations to force immediate reconciliation.

## Usage Guidelines

### 1. Verification
Check the health and status of Flux components.
- `flux get all -A`
- `flux check`

### 2. Manual Reconciliation
If you need to force Flux to sync immediately after a Git push.
- `flux reconcile source git <name> -n <namespace>`
- `flux reconcile kustomization <name> -n <namespace>`
- `flux reconcile helmrelease <name> -n <namespace>`

### 3. Debugging Failures
When reconciliation fails, inspect the conditions and logs.
- `flux logs -f`
- `kubectl describe kustomization <name> -n <namespace>`
- `kubectl get helmrelease <name> -n <namespace> -o yaml`

## Best Practices
- **Declarative Everything**: Avoid `kubectl apply` for persistent resources. Always commit to Git and let Flux reconcile.
- **Health Checks**: Always include `wait: true` or health checks in `Kustomization` or `HelmRelease` to ensure dependencies are met.
- **Secret Management**: Use `SOPS` (Decryption) or `ExternalSecrets` to manage sensitive data in a GitOps-compliant way.
- **Interval Management**: Set reasonable intervals for reconciliation to balance resource usage and sync speed (e.g., 10-30m for production, 1m for dev).

## Common Commands
| Task | Command |
| :--- | :--- |
| Get all Flux resources | `flux get all -A` |
| Reconcile Flux System | `flux reconcile source git flux-system -n flux-system` |
| Suspend reconciliation | `flux suspend kustomization <name>` |
| Resume reconciliation | `flux resume kustomization <name>` |
| Check image automation | `flux get image all` |

## Error Handling
If you see "Dependency not ready", verify the status of the required resource. If you see "kustomize build failed", check the YAML syntax and resource references in the kustomization.yaml file.
