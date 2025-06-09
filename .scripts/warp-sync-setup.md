# Warp Cloud Sync (Warp Drive)

## How Warp Syncs:

1. **Warp Drive** - Built-in cloud sync
   - Syncs workflows, notebooks, and settings
   - Teams can share configurations
   - Free tier includes basic sync

2. **What syncs automatically:**
   - Custom workflows
   - Command notebooks
   - AI command history
   - Settings and themes

3. **What DOESN'T sync (yet):**
   - SSH hosts/connections
   - Local terminal profiles

## Current Setup:

Since Warp doesn't sync SSH hosts natively, our script:
1. Reads from Termius cloud (your source of truth)
2. Generates local Warp config files
3. You can then save these as Warp workflows

## To use Warp Drive:

1. **In Warp terminal:**
   ```
   Settings → Account → Sign in
   ```

2. **Enable sync:**
   ```
   Settings → Sync → Enable Warp Drive
   ```

3. **Create shared workflows:**
   - Click '+' in workflows panel
   - Save your SSH commands
   - They sync automatically

## Our Integration:

The `termius-cloud-sync` script generates:
- `~/.warp/ssh_hosts.yml` - Local config
- `~/.warp/termius_workflows.yml` - Workflow templates

You then manually add these as Warp workflows, which sync via Warp Drive.

## Future:
Warp is working on SSH connection management. Until then, we bridge Termius → Warp.