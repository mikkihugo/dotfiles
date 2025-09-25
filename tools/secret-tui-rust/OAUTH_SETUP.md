# 🔐 OAuth Authentication Setup Guide

Transform your secret sync from manual key sharing to OAuth-based device authentication, just like `gh auth login`!

## 🎯 Why OAuth Instead of Manual Keys?

### Before (Manual Key Sharing):
```bash
# Device 1: Generate key
secret-tui generate-key -> "base64-key-here"

# Device 2: Manually enter key
secret-tui import-key "base64-key-here"

# Problems:
# ❌ Error-prone key typing
# ❌ Keys in bash history
# ❌ No centralized access management
# ❌ No key rotation
# ❌ No device auditing
```

### After (OAuth Authentication):
```bash
# Device 1: Authenticate
secret-tui auth login
# Opens browser -> Auth with GitHub -> Done!

# Device 2: Authenticate
secret-tui auth login
# Opens browser -> Auth with GitHub -> Auto-paired!

# Benefits:
# ✅ Zero manual key handling
# ✅ Centralized access management
# ✅ Easy device revocation
# ✅ Automatic key rotation
# ✅ Device audit trail
```

## 🚀 Quick Start

### 1. First Device Setup
```bash
cd ~/.dotfiles/tools/secret-tui-rust
cargo build --release

# Authenticate with GitHub
./target/release/secret-tui auth login
# Browser opens -> Sign in to GitHub -> Device authorized ✅

# Check status
./target/release/secret-tui auth status
# ✅ Authenticated as username-laptop (device: a1b2c3d4)
#    Provider: GitHub
#    Permissions: ["family-secrets", "work-dev"]
#    Expires: 2024-01-30T15:30:00Z

# Start using the TUI
./target/release/secret-tui
# Now sync menu shows OAuth-authenticated devices!
```

### 2. Additional Devices
```bash
# On your second machine
./target/release/secret-tui auth login
# Browser opens -> Same GitHub account -> Automatically paired! 🎉

# Devices now share sync permissions automatically
./target/release/secret-tui
# Sync menu shows other authenticated devices
```

## 🔧 OAuth Provider Setup

### GitHub App Registration

1. **Create GitHub App**:
   - Go to GitHub Settings → Developer settings → GitHub Apps
   - Click "New GitHub App"
   - App name: "Personal Secret Sync"
   - Homepage URL: "https://github.com/your-username/dotfiles"
   - User authorization callback URL: Not needed for device flow
   - Webhook: Disable
   - Permissions:
     - Account: Email addresses (read)
     - Account: User (read)

2. **Configure Client ID**:
   ```bash
   # Add to your environment or config
   export SECRET_SYNC_GITHUB_CLIENT_ID="Iv1.your-client-id-here"
   ```

### Google OAuth Setup (Alternative)

1. **Create Google Cloud Project**:
   - Go to [Google Cloud Console](https://console.cloud.google.com)
   - Create new project: "personal-secret-sync"
   - Enable "Google+ API" (for user info)

2. **Configure OAuth Client**:
   - Go to APIs & Services → Credentials
   - Create credentials → OAuth 2.0 Client IDs
   - Application type: "Desktop application"
   - Name: "Secret Sync CLI"

3. **Set Environment**:
   ```bash
   export SECRET_SYNC_GOOGLE_CLIENT_ID="your-google-client-id"
   export SECRET_SYNC_GOOGLE_CLIENT_SECRET="your-google-client-secret"
   ```

## 💡 How OAuth Device Flow Works

### The `gh auth login` Experience:

```bash
$ secret-tui auth login
🔐 Starting device authentication...
🌐 Please visit: https://github.com/login/device
📝 Enter code: WDJB-MJHT
🔗 Or visit: https://github.com/login/device?user_code=WDJB-MJHT
⏳ Waiting for authentication...

# Browser opens automatically
# User signs in to GitHub
# User enters device code WDJB-MJHT
# User authorizes "Personal Secret Sync" app

✅ Authentication successful!
🎉 Authentication successful!
   You can now run 'secret-tui' to start syncing secrets.
```

### Behind the Scenes:

1. **Device Code Request**: App requests device code from GitHub
2. **User Authorization**: User visits URL and authorizes device
3. **Token Exchange**: App polls GitHub until user approves
4. **Token Storage**: Access token stored securely in `~/.dotfiles/.secret-auth.json`
5. **Sync Key Generation**: Unique sync key derived from user identity + device ID

## 🔒 Security Architecture

### OAuth Token Security:
```json
// ~/.dotfiles/.secret-auth.json (600 permissions)
{
  "provider": "GitHub",
  "access_token": "gho_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
  "refresh_token": null,
  "expires_at": "2024-01-30T15:30:00Z",
  "device_id": "a1b2c3d4e5f6g7h8",
  "device_name": "username-laptop",
  "sync_permissions": ["family-secrets", "work-dev"]
}
```

### Sync Key Derivation:
```rust
// Sync key is NOT the OAuth token!
// Derived from: SHA256(device_id + access_token + room_id)
let sync_key = sha256(device_id + access_token + "family-secrets");
```

### Benefits:
- ✅ **OAuth tokens never used for encryption** - only for authentication
- ✅ **Sync keys automatically rotate** when OAuth tokens refresh
- ✅ **Room-specific keys** - different sync keys per secret category
- ✅ **Device isolation** - each device has unique sync key component
- ✅ **Revocable access** - remove OAuth token = device can't sync

## 📱 Device Management

### List All Devices:
```bash
$ secret-tui auth status
✅ Authenticated as john-laptop (device: a1b2c3d4)
   Provider: GitHub
   Permissions: ["family-secrets", "work-dev"]
   Expires: 2024-01-30T15:30:00Z

# In TUI, sync menu shows:
# 📱 Devices in family-secrets room:
#   • john-laptop (this device) - Last seen: now
#   • john-desktop - Last seen: 5 min ago
#   • john-server - Last seen: 1 hour ago
```

### Revoke Device Access:
```bash
# Method 1: GitHub App Settings
# Go to GitHub Settings → Applications → Authorized GitHub Apps
# Find "Personal Secret Sync" → Revoke access for specific installs

# Method 2: Local logout
$ secret-tui auth logout
👋 Logged out successfully

# Method 3: Via sync management (future feature)
# $ secret-tui devices revoke john-old-laptop
```

### Token Refresh:
```bash
# Manual refresh
$ secret-tui auth refresh
✅ Token refreshed successfully

# Automatic refresh (in TUI)
# Tokens auto-refresh 5 minutes before expiry
```

## 🔄 Integration with Sync Methods

### OAuth + Serverless Relays:
```rust
// Sync configuration now includes auth
{
  "device_name": "john-laptop",
  "oauth_provider": "GitHub",
  "sync_methods": [
    {
      "ServerlessRelay": {
        "provider": "Vercel",
        "server_url": "https://your-app.vercel.app",
        "room_id": "family-secrets",
        "auth_required": true  // Uses OAuth token for API calls
      }
    }
  ]
}
```

### Room Permissions:
```rust
// Centrally managed permissions
// GET /api/sync/permissions with OAuth token returns:
{
  "rooms": ["family-secrets", "work-dev"],
  "device_limit": 5,
  "expires_at": "2024-01-30T15:30:00Z"
}
```

## 🛠️ Development Setup

### GitHub App for Development:

```bash
# Clone and build
git clone https://github.com/your-username/dotfiles
cd dotfiles/tools/secret-tui-rust
cargo build

# Set up GitHub App (one-time setup)
# Use the Client ID from your GitHub App
export SECRET_SYNC_GITHUB_CLIENT_ID="Iv1.your-app-client-id"

# Test authentication flow
RUST_LOG=debug cargo run -- auth login

# Test sync with OAuth
cargo run
# Navigate to Sync Menu - should show OAuth-authenticated devices
```

### Custom OAuth Provider:
```rust
// Add your own identity provider
use auth::{AuthProvider, SecretAuth};

let custom_provider = AuthProvider::Custom {
    name: "MyCompany".to_string(),
    auth_url: "https://auth.mycompany.com/device/code".to_string(),
    token_url: "https://auth.mycompany.com/token".to_string(),
    device_code_url: "https://auth.mycompany.com/device".to_string(),
    client_id: "your-internal-client-id".to_string(),
};

let mut auth = SecretAuth::new(dotfiles_root, custom_provider)?;
auth.login().await?;
```

## 🐛 Troubleshooting

### Common Issues:

**"Browser didn't open automatically"**
```bash
# Manual browser opening
firefox "https://github.com/login/device?user_code=WDJB-MJHT"
```

**"Authentication timeout"**
```bash
# Increase timeout or check network
# Device codes expire after 15 minutes
secret-tui auth login  # Try again
```

**"Token expired"**
```bash
# Check status first
secret-tui auth status

# Refresh if possible
secret-tui auth refresh

# Re-authenticate if needed
secret-tui auth logout
secret-tui auth login
```

**"Permission denied errors"**
```bash
# Check file permissions
ls -la ~/.dotfiles/.secret-auth.json
# Should be 600 (user read/write only)
chmod 600 ~/.dotfiles/.secret-auth.json
```

## 🎯 Migration from Manual Keys

### Existing Manual Setup:
```json
// Old .sync-config.json
{
  "device_name": "my-laptop",
  "sync_key": "manually-shared-base64-key==",
  "sync_methods": [...]
}
```

### Migration Steps:
```bash
# 1. Backup existing config
cp ~/.dotfiles/tools/secret-tui-rust/.sync-config.json ~/.sync-config.backup

# 2. Set up OAuth
secret-tui auth login

# 3. The app will automatically:
#    - Generate new OAuth-derived sync keys
#    - Migrate existing sync methods
#    - Maintain device compatibility during transition

# 4. Update other devices
# Run `secret-tui auth login` on each device
# Old manual keys will be replaced with OAuth-derived keys
```

## 🚀 Next Steps

1. **Set up your OAuth provider** (GitHub App recommended)
2. **Configure environment variables** (Client ID, etc.)
3. **Run `secret-tui auth login`** on your first device
4. **Authenticate additional devices** with same OAuth provider
5. **Enjoy automatic device pairing** and centralized access management!

Your secret sync is now as easy as `gh auth login` but with military-grade encryption and zero-knowledge relay architecture! 🎉