# SKILL: Backup Management (Borgmatic)

Manage automated, encrypted backups using Borgmatic and BorgBackup.

## Overview
This skill provides guidance on configuring and monitoring backups for critical data (Mailcow, OpenClaw, Databases). It covers repository management, pruning, and health monitoring.

## Capabilities
- **Backup Creation**: Configure and execute backups via `borgmatic`.
- **Retention Policies**: Manage pruning of old backups based on time/count.
- **Verification**: Perform integrity checks on backup repositories.
- **Restoration**: Guidance on recovering data from specific backup archives.

## Usage Guidelines

### 1. Daily Backups
Ensure backups are running on a regular schedule (e.g., via cron).
- Check status: `borgmatic list --repository <path>`

### 2. Destination
Backups should ideally be stored off-site (e.g., Hetzner Storage Box).
- Verify connectivity to the remote repository.

### 3. Monitoring
- Check backup logs for errors or warnings.
- Ensure that the "Done Tonight" checklist includes verification of the latest backup.

## Common Commands
| Task | Command |
| :--- | :--- |
| Run Backup | `borgmatic create` |
| List Backups | `borgmatic list` |
| Check Repo | `borgmatic check` |
| Prune Old | `borgmatic prune` |

## Best Practices
- **Encryption**: Always use strong encryption for backup repositories.
- **Atomic Backups**: Ensure databases are dumped (pg_dump) before being included in the backup.
- **Testing**: Periodically perform a test restoration to verify the integrity and usability of the backups.
- **Secrets Management**: Store Borg passphrases in the Vault or SOPS.
