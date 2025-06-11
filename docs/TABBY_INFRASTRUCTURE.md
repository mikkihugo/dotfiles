# Tabby Terminal Infrastructure Documentation

## Overview

This document describes the three-tier Tabby terminal infrastructure setup that provides unified terminal access across all platforms and devices.

## Architecture Components

### 1. Tabby.sh (Desktop Application)
- **Purpose**: Native terminal emulator for Windows/macOS/Linux desktops
- **Features**:
  - Local terminal sessions
  - SSH connection management
  - Profile synchronization
  - Custom themes and hotkeys
- **Config Location**: Synced via GitHub gists

### 2. Tabby Web (Browser Interface)
- **Purpose**: Web-based terminal access from any browser
- **Features**:
  - No installation required
  - Access from any device
  - Persistent sessions
  - Database-backed configuration
- **Related Scripts**:
  - `backup-tabby-web-db.sh` - Backup web interface database
  - Database contains user sessions, preferences, connection history

### 3. Tabby Gateway (Connection Proxy)
- **Purpose**: Central SSH jump host and connection broker
- **Features**:
  - Unified authentication point
  - SSH proxy/bastion functionality
  - Connection management and routing
  - Security boundary for internal resources
- **Related Scripts**:
  - `deploy-tabby-gateway.sh` - Deploy gateway infrastructure
  - `tabby-gateway-config.sh` - Configure gateway settings
  - `backup-tabby-gateway.sh` - Backup gateway configuration
  - `test-gateway.sh` - Verify gateway functionality
  - `gateway-status.sh` - Monitor gateway health

## Connection Flow

```
┌─────────────┐
│  Tabby.sh   │──┐
│  (Desktop)  │  │
└─────────────┘  │    ┌────────────────┐    ┌──────────────┐
                 ├───►│  Tabby Gateway │───►│ SSH Targets  │
┌─────────────┐  │    │  (Jump Host)   │    │  (Servers)   │
│  Tabby Web  │──┘    └────────────────┘    └──────────────┘
│  (Browser)  │
└─────────────┘
```

## Configuration Management

### Synchronization
- **Method**: GitHub Gists (private)
- **Scripts**:
  - `tabby-sync.sh` - Standard synchronization
  - `tabby-sync-direct.sh` - Direct sync without gateway
- **Purpose**: 
  - Backup configurations
  - Sync across devices
  - Enable remote support/troubleshooting

### Security Model
1. **Gateway Level**: 
   - Centralized authentication
   - Connection auditing
   - Access control policies

2. **Configuration Level**:
   - Private gist storage
   - Encrypted credentials
   - Token-based authentication

## Maintenance Tasks

### Regular Operations
```bash
# Check gateway status
mise -f .system/mise/system-tasks.toml run gateway-status

# Backup configurations
mise -f .system/mise/system-tasks.toml run backup-tabby

# Deploy updates
mise -f .system/mise/system-tasks.toml run gateway-deploy
```

### Troubleshooting
1. **Gateway Issues**: Check `gateway-status.sh` output
2. **Sync Problems**: Verify gist access tokens in `~/.env_tokens`
3. **Web Database**: Restore from backups if corrupted

## Benefits

1. **Unified Access**: Same experience across all platforms
2. **Central Management**: Single point for configuration
3. **Security**: Gateway provides controlled access
4. **Flexibility**: Use desktop app or web based on context
5. **Reliability**: Multiple access methods with fallbacks

## Integration with Dotfiles

The Tabby infrastructure integrates with the dotfiles ecosystem:
- Shell configurations auto-load on connection
- Gateway respects mise tool installations
- Synchronized terminal profiles include shell preferences
- Guardian system protects gateway configuration files

---

*Note: This infrastructure is separate from shell configurations (bash/zsh/fish) which are managed independently in the dotfiles repository.*