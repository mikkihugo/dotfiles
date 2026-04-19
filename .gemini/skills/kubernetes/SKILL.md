# SKILL: Kubernetes Cluster Operations

Execute and manage Kubernetes cluster operations using the `kubectl` command-line tool.

## Overview
This skill enables the agent to interact directly with Kubernetes clusters. It provides the necessary context and safety guidelines for querying resources, deploying applications, debugging containers, and managing cluster state.

## Capabilities
- **Query Resources**: List and describe pods, deployments, services, nodes, namespaces, etc.
- **Deploy & Update**: Create, apply, patch, and delete Kubernetes resources.
- **Debug & Troubleshoot**: View container logs, execute commands inside pods (`exec`), and inspect cluster events.
- **Manage Configuration**: Switch contexts, manage namespaces, and view/edit kubeconfigs.
- **Monitor Health**: Check rollout status, resource usage (top), and pod conditions.

## Usage Guidelines

### 1. Information Gathering (Read-Only)
Always start by verifying the current context and namespace before performing any modifications.
- `kubectl config current-context`
- `kubectl get pods -n <namespace>`

### 2. Resource Identification
Use label selectors to target specific groups of resources and avoid accidental bulk operations.
- `kubectl get pods -l app=my-app`

### 3. Safety First (Dry Runs)
Before applying changes or deleting resources, use the `--dry-run=client` flag to validate the command.
- `kubectl apply -f manifest.yaml --dry-run=client`
- `kubectl delete deployment my-deploy --dry-run=client`

### 4. Troubleshooting Workflow
When investigating issues, follow this sequence:
1. `kubectl get pods` (Check status)
2. `kubectl describe pod <pod-name>` (Check events/errors)
3. `kubectl logs <pod-name>` (Check application logs)
4. `kubectl exec -it <pod-name> -- /bin/sh` (Interactive debugging if necessary)

## Best Practices
- **Namespace Scoping**: Always specify the `-n <namespace>` flag unless operating on the default namespace. Use `-A` only for cluster-wide discovery.
- **Output Formatting**: Use `-o yaml` or `-o json` when you need to parse complex resource definitions.
- **Wait for Readiness**: Use `kubectl wait` or `kubectl rollout status` when deploying to ensure the system reaches the desired state.
- **Minimize Privileges**: Only perform actions within the scope of the provided ServiceAccount permissions.

## Common Commands
| Task | Command |
| :--- | :--- |
| List all pods | `kubectl get pods -A` |
| Stream logs | `kubectl logs -f <pod-name>` |
| Scale deployment | `kubectl scale deployment/<name> --replicas=3` |
| Check events | `kubectl get events --sort-by='.lastTimestamp'` |
| Port forward | `kubectl port-forward pod/<name> 8080:80` |

## Error Handling
If a command fails due to RBAC (Forbidden), do not attempt to bypass security. Report the permission gap to the user. If a resource is not found, verify the namespace and spelling before assuming it doesn't exist.
