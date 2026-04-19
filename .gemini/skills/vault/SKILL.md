# SKILL: OpenBae & Vault Management

Expert guidance for configuring, managing, and troubleshooting secrets within the OpenBae/Vault ecosystem.

## Overview
OpenBae (an open-source fork of Vault) is a community-driven secrets management system. This skill enables the agent to interact with Vault for secret retrieval, configuration of auth methods (AppRole, OIDC), and lifecycle management of sensitive data.

## Capabilities
- **Secret Retrieval**: Fetch K/V secrets from specific paths.
- **Auth Configuration**: Setup and manage AppRole, OIDC, and other authentication methods.
- **Policy Management**: Create and update policies to restrict access to specific paths.
- **Audit Logging**: Configure and monitor audit devices (file, syslog).
- **Initialization & Unsealing**: Handle the initial setup and unsealing of the vault.

## Usage Guidelines

### 1. Verification
Before interacting with secrets, verify the Vault status and your current authentication level.
- `bao status`
- `bao token lookup`

### 2. Secret Access
Use specific paths and fields when retrieving secrets to minimize data exposure.
- `bao kv get -format=json kv/data/<secret_path>`
- `bao kv get -field=<field_name> kv/data/<secret_path>`

### 3. Policy Principle
Always follow the Principle of Least Privilege. Design policies that grant the minimum necessary capabilities (`read`, `list`, `create`, `update`, `delete`).
- `bao policy write <name> <policy_file>`

### 4. AppRole Management
Use AppRoles for machine-to-machine authentication.
- `bao auth enable approle`
- `bao write auth/approle/role/<role_name> token_policies="<policy>"`
- `bao read auth/approle/role/<role_name>/role-id`
- `bao write -f auth/approle/role/<role_name>/secret-id`

## Best Practices
- **Never Log Secrets**: Ensure that `bao` commands that return secrets are either piped directly to their consumer or handled in a way that doesn't leak to logs.
- **Declarative Audit**: Use declarative configuration for audit devices in OpenBae 2.x.
- **Token TTLs**: Set reasonable TTLs for tokens to minimize the window of opportunity for leaked credentials.
- **Use SOPS for Backup**: Store unseal shares and root tokens in SOPS-encrypted files within the infrastructure repository.

## Common Commands
| Task | Command |
| :--- | :--- |
| Login (Generic) | `bao login` |
| List secrets | `bao kv list kv/metadata/` |
| Create AppRole | `bao write auth/approle/role/my-role token_policies="my-policy"` |
| Check Audit | `bao audit list` |
| Unseal | `bao operator unseal <share>` |

## Error Handling
If you receive a 403 (Forbidden), check the policy associated with your token. If the vault is sealed (503), it must be unsealed before any operations can proceed.
