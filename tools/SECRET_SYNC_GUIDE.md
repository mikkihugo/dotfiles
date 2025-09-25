# 🔄 Secret Sync - Multi-Machine Secret Synchronization

Your secret manager now includes a sophisticated P2P synchronization system that keeps your secrets in sync across multiple machines **without ever storing them in Git**.

## 🎯 Why This Approach?

✅ **Zero-Git Storage**: Secrets never touch your Git repository, even encrypted
✅ **True P2P**: Direct machine-to-machine encrypted communication
✅ **Multiple Methods**: Choose the sync method that works for your setup
✅ **Military-Grade Crypto**: ChaCha20-Poly1305 encryption with SHA256 checksums
✅ **Conflict Resolution**: Smart detection and resolution of sync conflicts

## 🔧 Available Sync Methods

### 1. 🌐 Local Network P2P
**Best for**: Home/office networks where machines can talk directly

- **How it works**: UDP broadcast discovery + direct TCP sync
- **Security**: End-to-end encrypted with your sync key
- **Setup**: Automatic - just enable on both machines
- **Pros**: Fast, simple, no external dependencies
- **Cons**: Only works on same network

### 2. 📁 File Drop Sync
**Best for**: Using existing file sync (Syncthing, Dropbox, etc.)

- **How it works**: Encrypted files in shared folder
- **Security**: Double-encrypted (sync + file service)
- **Setup**: Point to your sync folder
- **Pros**: Works anywhere, uses existing infrastructure
- **Cons**: Requires file sync service

### 3. 🔄 Relay Server
**Best for**: Remote machines, advanced users

- **How it works**: Encrypted packets via relay server
- **Security**: Zero-knowledge relay (can't see content)
- **Setup**: Self-hosted relay server
- **Pros**: Works anywhere with internet
- **Cons**: Requires server setup

### 4. 🌐 Webhook Sync
**Best for**: Custom integrations, cloud setups

- **How it works**: HTTPS POST to your endpoint
- **Security**: Encrypted payload + TLS
- **Setup**: Configure webhook endpoint
- **Pros**: Flexible, integrates with existing systems
- **Cons**: Need to implement receiver

## 🚀 Quick Setup Guide

### Method 1: File Drop Sync (Easiest)

1. **Set up file sync** (Syncthing recommended)
   ```bash
   # Install Syncthing
   sudo apt install syncthing  # or your distro's package
   ```

2. **Create shared folder**
   ```bash
   mkdir -p ~/Sync/secrets
   # Add this folder to Syncthing on both machines
   ```

3. **Configure sync in TUI**
   - Run `~/.dotfiles/tools/secret-manager`
   - Navigate to `🔄 Secret Sync` → `⚙️ Sync Setup`
   - Add File Drop method pointing to `~/Sync/secrets`

### Method 2: Local Network P2P

1. **Run on first machine**
   ```bash
   ~/.dotfiles/tools/secret-manager
   # Go to Secret Sync → Sync Setup
   # Note the device name and sync key
   ```

2. **Run on second machine**
   ```bash
   ~/.dotfiles/tools/secret-manager
   # Go to Secret Sync → Sync Setup
   # Use the same sync key from first machine
   ```

3. **Sync**
   - Both machines must be on same network
   - Go to `🔄 Sync Now` on either machine
   - Automatic discovery and sync

## 🔐 Security Architecture

```
┌─────────────┐    Encrypted     ┌─────────────┐
│  Machine A  │ ◄──── Sync ────► │  Machine B  │
│             │    Packets       │             │
└─────────────┘                  └─────────────┘
       │                                │
       ▼                                ▼
┌─────────────┐                  ┌─────────────┐
│ ChaCha20-   │                  │ ChaCha20-   │
│ Poly1305    │                  │ Poly1305    │
│ Encryption  │                  │ Encryption  │
└─────────────┘                  └─────────────┘
       │                                │
       ▼                                ▼
┌─────────────┐                  ┌─────────────┐
│ SOPS Age    │                  │ SOPS Age    │
│ Encryption  │                  │ Encryption  │
└─────────────┘                  └─────────────┘
```

### Encryption Layers
1. **SOPS Layer**: Your secrets are already encrypted with age
2. **Sync Layer**: Additional ChaCha20-Poly1305 encryption for transport
3. **Network Layer**: TLS/HTTPS for supported methods

### Key Management
- **Sync Key**: 256-bit random key for sync encryption
- **Age Key**: Your existing SOPS age key for secret encryption
- **Device ID**: SHA256 hash for device identification

## 📱 Sync Workflow

### First Sync (New Machine)
```bash
# On existing machine
~/.dotfiles/tools/secret-manager
# → Secret Sync → Sync Setup → Generate QR Code
# (Shows QR with sync configuration)

# On new machine
~/.dotfiles/tools/secret-manager
# → Secret Sync → Sync Setup → Scan QR Code
# (Automatic configuration)
```

### Regular Sync
```bash
# Manual sync
~/.dotfiles/tools/secret-manager
# → Secret Sync → Sync Now

# Or enable auto-sync for background operation
```

### Conflict Resolution
When conflicts occur (same secret changed on both machines):
1. TUI shows conflict details
2. Choose local or remote version
3. Apply resolution across all machines

## 🛠️ Advanced Configuration

### Self-Hosted Relay Server
```bash
# Simple relay server (Python)
pip install secret-sync-relay
secret-relay --port 8080 --host 0.0.0.0

# Add to sync methods:
# Server: https://your-server.com:8080
# Room ID: your-unique-room-name
```

### Custom Webhook
```javascript
// Express.js webhook receiver
app.post('/sync', (req, res) => {
  const packet = req.body;
  // Decrypt with your sync key
  // Process secrets
  // Return success
  res.json({ success: true });
});
```

## 🔍 Troubleshooting

### Sync Not Working
1. Check network connectivity
2. Verify sync keys match
3. Check firewall settings (port 8765-8766)
4. Verify SOPS/age setup

### Conflicts Keep Occurring
1. Check system clocks are synchronized
2. Avoid editing same secrets simultaneously
3. Use proper conflict resolution

### File Drop Issues
1. Check folder permissions
2. Verify file sync service is working
3. Check available disk space

## 📊 Sync Status

The TUI provides detailed sync status:
- ✅ Last sync time
- 📊 Categories synchronized
- ⚔️ Active conflicts
- 🔍 Sync method health
- 📈 Sync statistics

## 🎛️ Configuration Files

### Sync Config Location
```
~/.dotfiles/.sync-config.json
```

### Example Configuration
```json
{
  "device_name": "laptop-home",
  "sync_key": "base64-encoded-key",
  "sync_methods": [
    {
      "FileDrop": {
        "sync_folder": "/home/user/Sync/secrets"
      }
    }
  ],
  "auto_sync": false,
  "last_sync": "2025-01-01T12:00:00Z"
}
```

## 🚦 Best Practices

### ✅ Do
- Use strong passwords for file sync services
- Keep sync keys secure
- Regular sync (daily)
- Monitor sync status
- Test restore procedures

### ❌ Don't
- Share sync keys via insecure channels
- Use sync on untrusted networks without VPN
- Ignore conflict warnings
- Skip backup verification

## 🆘 Emergency Procedures

### Lost Sync Key
1. Stop auto-sync on all machines
2. Generate new sync key
3. Manually distribute to all machines
4. Resume sync operations

### Corrupted Sync Data
1. Stop sync on all machines
2. Verify SOPS files integrity
3. Restore from backup
4. Reinitialize sync

### Machine Compromise
1. Revoke sync access immediately
2. Generate new sync and age keys
3. Re-encrypt all secrets
4. Update all trusted machines

---

## 🎉 You're All Set!

Your secrets are now synchronized securely across machines without ever touching Git. The system provides enterprise-grade security with user-friendly operation.

**Next Steps:**
1. Set up your preferred sync method
2. Test with a few secrets
3. Enable on all your machines
4. Consider backup strategies

**Support:**
- Check TUI help system
- Review logs in debug mode
- Test with non-sensitive data first