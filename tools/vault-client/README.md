# Hugo Vault Client - Lightweight Secret Management

The Hugo Vault provides multiple ways for systems to access secrets stored in PostgreSQL. All methods are lightweight and don't require heavy dependencies.

## Access Methods

### 1. Direct PostgreSQL Connection (Most Lightweight)
Connect directly to PostgreSQL using standard database drivers.

```sql
-- Get a secret
SELECT value FROM vault WHERE key = 'api_key';

-- Set a secret
INSERT INTO vault (key, value) VALUES ('api_key', 'secret123')
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
```

Connection details:
- Host: `db` (internal) or `your-postgres-host`
- Port: `5432`
- Database: `hugo`
- User: `hugo`
- Password: `hugo`

### 2. Shell Script Client
Minimal bash script that uses `psql` command.

```bash
# Get a secret
./vault-client.sh get github_token

# Set a secret
./vault-client.sh set github_token ghp_xxxxx

# List all keys
./vault-client.sh list

# Export all as environment variables
source <(./vault-client.sh export)
```

### 3. Python Client
Lightweight Python client using psycopg2.

```python
from vault_client import VaultClient

# Direct database connection
vault = VaultClient()
token = vault.get('github_token')
vault.set('api_key', 'secret123')

# Export all to environment
vault.export_env()
```

### 4. HTTP API Client
For systems that can't connect to PostgreSQL directly.

```bash
# Get a secret
curl -H "X-API-Key: hugo-vault-api-2025" \
  http://vault-api:5001/api/v1/secrets/github_token

# Set a secret
curl -X POST -H "X-API-Key: hugo-vault-api-2025" \
  -H "Content-Type: application/json" \
  -d '{"key":"api_key","value":"secret123"}' \
  http://vault-api:5001/api/v1/secrets
```

### 5. Dev Shell Integration
For Nix/direnv (or any managed shell) sessions that need secrets before launching tooling.

```bash
# Load all secrets into environment
./vault-env.sh setup

# Sync .env file to vault
./vault-env.sh sync .env

# Generate .env from vault
./vault-env.sh env .env.production
```

## Integration Examples

### Docker Container
```dockerfile
# Install only psql client (5MB)
RUN apt-get update && apt-get install -y postgresql-client

# Copy vault client script
COPY vault-client.sh /usr/local/bin/vault-client
RUN chmod +x /usr/local/bin/vault-client

# In entrypoint
RUN source <(/usr/local/bin/vault-client export)
```

### Node.js
```javascript
const { Client } = require('pg');

const vault = new Client({
  host: 'db',
  database: 'hugo',
  user: 'hugo',
  password: 'hugo'
});

await vault.connect();
const result = await vault.query('SELECT value FROM vault WHERE key = $1', ['api_key']);
const apiKey = result.rows[0]?.value;
```

### Go
```go
import "database/sql"
import _ "github.com/lib/pq"

db, _ := sql.Open("postgres", "host=db user=hugo password=hugo dbname=hugo sslmode=disable")
var value string
db.QueryRow("SELECT value FROM vault WHERE key = $1", "api_key").Scan(&value)
```

### Environment Variables
The vault can automatically export secrets as environment variables:

```bash
# Export with prefix
vault-client export MYAPP_
# Results in: MYAPP_GITHUB_TOKEN, MYAPP_API_KEY, etc.

# Export without prefix
vault-client export
# Results in: GITHUB_TOKEN, API_KEY, etc.
```

## Security Notes

1. **Network Isolation**: Keep vault database on internal network
2. **API Key**: Change default API key in production
3. **Encryption**: Vault data is encrypted at rest in PostgreSQL
4. **Access Control**: Use PostgreSQL roles for fine-grained access
5. **Audit**: Enable PostgreSQL audit logging for compliance

## Minimal Dependencies

- **Shell Script**: Only needs `psql` (5MB)
- **Python Client**: Only needs `psycopg2` (2MB)
- **Direct SQL**: Use existing database drivers
- **HTTP API**: Standard HTTP client in any language

Choose the method that best fits your system's constraints!
