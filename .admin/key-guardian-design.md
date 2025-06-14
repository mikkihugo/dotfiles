# Key Guardian Design - Secure Credential Management

## Architecture

### 1. **Key Guardian** (Rust binary)
- Runs as a daemon/service
- Connects to central vault (Doppler/Vault/1Password)
- Caches keys in memory (never disk)
- Provides keys via Unix socket or named pipe
- Auto-rotates based on TTL

### 2. **Shell Integration**
Instead of `source ~/.env_tokens`, shells would:
```bash
# Request keys from guardian
eval "$(key-guardian env)"

# Or for specific keys
export OPENAI_API_KEY=$(key-guardian get OPENAI_API_KEY)
```

### 3. **Central Vault Options**

#### Option A: Doppler Integration
```rust
// key-guardian connects to Doppler
let client = DopplerClient::new(auth_token);
let secrets = client.get_secrets("production");
```

#### Option B: HashiCorp Vault
```rust
// key-guardian connects to Vault
let client = VaultClient::new(vault_addr, vault_token);
let secrets = client.read("secret/data/api-keys");
```

#### Option C: 1Password CLI
```rust
// key-guardian uses op CLI
let output = Command::new("op")
    .args(&["read", "op://vault/item/field"])
    .output()?;
```

## Implementation Plan

### Phase 1: Basic Key Guardian
```rust
// key-guardian.rs
use std::collections::HashMap;
use std::os::unix::net::UnixListener;

struct KeyGuardian {
    secrets: HashMap<String, String>,
    vault_client: Box<dyn VaultProvider>,
    refresh_interval: Duration,
}

impl KeyGuardian {
    fn refresh_secrets(&mut self) {
        self.secrets = self.vault_client.fetch_all();
    }
    
    fn serve(&self) {
        let listener = UnixListener::bind("/tmp/key-guardian.sock")?;
        for stream in listener.incoming() {
            // Handle requests for keys
        }
    }
}
```

### Phase 2: Shell Helper
```bash
#!/bin/bash
# key-guardian-helper.sh

key-guardian() {
    case "$1" in
        env)
            # Get all environment variables
            nc -U /tmp/key-guardian.sock <<< "GET_ALL"
            ;;
        get)
            # Get specific key
            nc -U /tmp/key-guardian.sock <<< "GET $2"
            ;;
        refresh)
            # Force refresh from vault
            nc -U /tmp/key-guardian.sock <<< "REFRESH"
            ;;
    esac
}
```

### Phase 3: Admin Integration
```bash
# In shell-sync-guardian.sh
generate_key_loading() {
    local shell=$1
    
    if [ "$USE_KEY_GUARDIAN" = "1" ]; then
        # Use secure key guardian
        echo '# Load secrets from key guardian'
        echo 'if pgrep -f key-guardian >/dev/null; then'
        echo '    eval "$(key-guardian env)"'
        echo 'else'
        echo '    echo "Warning: Key guardian not running"'
        echo 'fi'
    else
        # Traditional file-based approach
        echo '# Load tokens from file'
        echo 'if [ -f "$HOME/.env_tokens" ]; then'
        echo '    source "$HOME/.env_tokens"'
        echo 'fi'
    fi
}
```

## Security Benefits

1. **No Plain Text Storage**: Keys never written to disk
2. **Central Management**: Single source of truth
3. **Automatic Rotation**: Keys refresh based on policy
4. **Access Control**: Only authorized processes can request keys
5. **Audit Trail**: Log all key access requests

## Usage Example

```bash
# Start key guardian
key-guardian daemon --vault doppler --project myapp

# In .bashrc
if command -v key-guardian &>/dev/null; then
    eval "$(key-guardian env)"
fi

# Manual key request
export DATABASE_URL=$(key-guardian get DATABASE_URL)

# Check status
key-guardian status
# Connected to: Doppler
# Keys loaded: 47
# Last refresh: 2 minutes ago
# Next refresh: in 58 minutes
```

## Integration with Existing Guardian

The key guardian could be:
1. **Part of shell-guardian**: Add key management features
2. **Separate binary**: key-guardian works alongside shell-guardian
3. **Managed by keeper**: The keeper ensures key-guardian stays running

## Next Steps

1. Choose vault provider (Doppler seems easiest)
2. Implement basic key-guardian in Rust
3. Create shell integration scripts
4. Update shell-sync-guardian to support both modes
5. Add monitoring and health checks