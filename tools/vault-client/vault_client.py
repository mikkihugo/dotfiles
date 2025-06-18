#!/usr/bin/env python3
"""
Lightweight PostgreSQL Vault Client for Python
Can be used by any Python application to fetch secrets
"""

import os
import psycopg2
from psycopg2.extras import RealDictCursor
import requests
from typing import Optional, List, Dict


class VaultClient:
    """PostgreSQL-based vault client"""
    
    def __init__(self, host=None, port=None, user=None, password=None, database=None):
        self.host = host or os.getenv('VAULT_HOST', 'db')
        self.port = port or os.getenv('VAULT_PORT', '5432')
        self.user = user or os.getenv('VAULT_USER', 'hugo')
        self.password = password or os.getenv('VAULT_PASSWORD', 'hugo')
        self.database = database or os.getenv('VAULT_DB', 'hugo')
        self._conn = None
    
    def _get_connection(self):
        """Get or create database connection"""
        if not self._conn or self._conn.closed:
            self._conn = psycopg2.connect(
                host=self.host,
                port=self.port,
                user=self.user,
                password=self.password,
                database=self.database
            )
        return self._conn
    
    def get(self, key: str) -> Optional[str]:
        """Get a secret value"""
        conn = self._get_connection()
        with conn.cursor() as cur:
            cur.execute("SELECT value FROM vault WHERE key = %s", (key,))
            result = cur.fetchone()
            return result[0] if result else None
    
    def set(self, key: str, value: str) -> None:
        """Set a secret value"""
        conn = self._get_connection()
        with conn.cursor() as cur:
            cur.execute("""
                INSERT INTO vault (key, value) VALUES (%s, %s)
                ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value
            """, (key, value))
        conn.commit()
    
    def list(self) -> List[str]:
        """List all secret keys"""
        conn = self._get_connection()
        with conn.cursor() as cur:
            cur.execute("SELECT key FROM vault ORDER BY key")
            return [row[0] for row in cur.fetchall()]
    
    def delete(self, key: str) -> None:
        """Delete a secret"""
        conn = self._get_connection()
        with conn.cursor() as cur:
            cur.execute("DELETE FROM vault WHERE key = %s", (key,))
        conn.commit()
    
    def get_all(self) -> Dict[str, str]:
        """Get all secrets as a dictionary"""
        conn = self._get_connection()
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute("SELECT key, value FROM vault")
            return {row['key']: row['value'] for row in cur.fetchall()}
    
    def export_env(self, prefix: str = "") -> None:
        """Export all secrets as environment variables"""
        secrets = self.get_all()
        for key, value in secrets.items():
            env_key = f"{prefix}{key.upper()}" if prefix else key.upper()
            os.environ[env_key] = value
    
    def close(self):
        """Close database connection"""
        if self._conn and not self._conn.closed:
            self._conn.close()


class VaultAPIClient:
    """HTTP API client for vault service"""
    
    def __init__(self, base_url=None, api_key=None):
        self.base_url = base_url or os.getenv('VAULT_API_URL', 'http://vault-api:5001')
        self.api_key = api_key or os.getenv('VAULT_API_KEY', 'hugo-vault-api-2025')
        self.headers = {'X-API-Key': self.api_key}
    
    def get(self, key: str) -> Optional[str]:
        """Get a secret value via API"""
        resp = requests.get(f"{self.base_url}/api/v1/secrets/{key}", headers=self.headers)
        if resp.status_code == 200:
            return resp.json()['value']
        return None
    
    def set(self, key: str, value: str) -> None:
        """Set a secret value via API"""
        resp = requests.post(
            f"{self.base_url}/api/v1/secrets",
            json={'key': key, 'value': value},
            headers=self.headers
        )
        resp.raise_for_status()
    
    def list(self) -> List[str]:
        """List all secret keys via API"""
        resp = requests.get(f"{self.base_url}/api/v1/secrets", headers=self.headers)
        resp.raise_for_status()
        return [s['key'] for s in resp.json()]
    
    def delete(self, key: str) -> None:
        """Delete a secret via API"""
        resp = requests.delete(f"{self.base_url}/api/v1/secrets/{key}", headers=self.headers)
        resp.raise_for_status()


# CLI interface
if __name__ == "__main__":
    import sys
    
    # Use direct DB connection for CLI
    client = VaultClient()
    
    if len(sys.argv) < 2:
        print("Usage: vault_client.py {get|set|list|delete|export} [args...]")
        print("  get <key>           - Get a secret value")
        print("  set <key> <value>   - Set a secret value")
        print("  list                - List all secret keys")
        print("  delete <key>        - Delete a secret")
        print("  export [prefix]     - Export all secrets as env vars")
        sys.exit(1)
    
    command = sys.argv[1]
    
    try:
        if command == "get" and len(sys.argv) >= 3:
            value = client.get(sys.argv[2])
            if value:
                print(value)
        elif command == "set" and len(sys.argv) >= 4:
            client.set(sys.argv[2], sys.argv[3])
            print(f"Set {sys.argv[2]}")
        elif command == "list":
            for key in client.list():
                print(key)
        elif command == "delete" and len(sys.argv) >= 3:
            client.delete(sys.argv[2])
            print(f"Deleted {sys.argv[2]}")
        elif command == "export":
            prefix = sys.argv[2] if len(sys.argv) >= 3 else ""
            client.export_env(prefix)
            print("Exported to environment")
        else:
            print(f"Unknown command: {command}")
            sys.exit(1)
    finally:
        client.close()