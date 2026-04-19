# SKILL: Network Mesh (Tailscale & Headscale)

Manage private, secure mesh networks and connectivity using Tailscale and Headscale.

## Overview
This skill provides guidance on maintaining a private network overlay using Tailscale (the protocol) and Headscale (the self-hosted control plane). It covers node management, DNS overrides, and secure access to internal services.

## Capabilities
- **Node Management**: Join, approve, and revoke nodes in the mesh.
- **DNS Overrides**: Configure `extra_records` to resolve hostnames to tailnet IPs.
- **Access Control**: Manage ACLs and tags for node-to-node security.
- **Connectivity**: Troubleshoot routing and connectivity issues across the tailnet.

## Usage Guidelines

### 1. Adding Nodes
When adding a new device (like a phone or a new server):
1. Install the Tailscale client.
2. Login using the Headscale server URL (`https://vpn.hugo.dk`).
3. Approve the machine on the Headscale server using the provided CLI/UI.

### 2. DNS Resolution
Use `extra_records` in `config.yaml` to ensure internal services (Vault, n8n) resolve to the correct tailnet IP (e.g., `100.64.0.1` for flow) for tailnet clients.
- Remember to restart the `headscale` container after updating the config.

### 3. Verification
- Use `tailscale status` on any node to see the current mesh state.
- Use `ping` or `dig` to verify that internal hostnames resolve to `100.64.x.x` IPs.

## Common Commands
| Task | Command |
| :--- | :--- |
| List Nodes | `headscale nodes list` |
| Register Node | `headscale nodes register --user <user> --key <key>` |
| Tailscale Status | `tailscale status` |
| Check Ping | `tailscale ping <hostname>` |

## Best Practices
- **MagicDNS**: Use MagicDNS for automatic hostname resolution when possible.
- **Security**: Never expose the Headscale control plane or UI to the public internet without SSO/MFA.
- **Tailnet-Only UI**: Restrict administrative UIs (like Vault or n8n) to the tailnet range for enhanced security.
