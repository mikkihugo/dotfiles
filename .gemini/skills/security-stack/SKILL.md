# SKILL: Security Stack (Authelia & Traefik)

Manage and configure secure routing, authentication, and SSO using Traefik and Authelia.

## Overview
This skill provides guidance on securing applications with the Traefik reverse proxy and the Authelia SSO/MFA provider. It covers IngressRoute configuration, middleware (ForwardAuth, ipAllowList), and OIDC client management.

## Capabilities
- **Reverse Proxy**: Configure Traefik `IngressRoute` and `Middleware` resources.
- **Authentication**: Setup `ForwardAuth` to protect services with Authelia.
- **SSO/OIDC**: Register and manage OIDC clients in Authelia.
- **Access Control**: Implement `ipAllowList` and other security middlewares.
- **Monitoring**: Check Traefik dashboard and Authelia logs for access issues.

## Usage Guidelines

### 1. Ingress Security
Always protect sensitive internal services with either an IP allowlist or Authelia authentication.
- Traefik Middleware (ForwardAuth): `match: Host(`service.hugo.dk`)` + `middlewares: [name: authelia]`

### 2. OIDC Registration
When adding a new OIDC client (like Vault or n8n):
1. Update Authelia `configmap.yaml` with the client ID, secret, and redirect URIs.
2. Ensure the `authorization_policy` matches the required security level (one_factor/two_factor).

### 3. Debugging Access
- Check Traefik logs for 403/401 errors.
- Verify middleware association in the `IngressRoute`.
- Check Authelia logs for failed login attempts or OIDC handshake errors.

## Common Commands
| Task | Command |
| :--- | :--- |
| List IngressRoutes | `kubectl get ingressroute -A` |
| Check Middlewares | `kubectl get middleware -A` |
| Authelia Logs | `kubectl -n authelia logs deploy/authelia` |
| Traefik Logs | `kubectl -n traefik logs deploy/traefik` |

## Best Practices
- **Tailnet Isolation**: Use `ipAllowList` to restrict administrative UIs (Vault, Headscale) to the 100.64.0.0/10 range.
- **Secrets Management**: Store Authelia OIDC secrets and HMACs in SOPS-encrypted files.
- **Redirect URIs**: Always use HTTPS for OIDC redirect URIs in production.
