-- PostgreSQL Vault Database Initialization
-- Creates tables for secure secret storage

-- Create vault schema
CREATE SCHEMA IF NOT EXISTS vault;

-- Secrets table with encryption
CREATE TABLE IF NOT EXISTS vault.secrets (
    id SERIAL PRIMARY KEY,
    key_name VARCHAR(255) UNIQUE NOT NULL,
    encrypted_value TEXT NOT NULL,
    category VARCHAR(100) DEFAULT 'general',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_by VARCHAR(100) DEFAULT 'system',
    metadata JSONB DEFAULT '{}'::jsonb
);

-- Access log table
CREATE TABLE IF NOT EXISTS vault.access_log (
    id SERIAL PRIMARY KEY,
    key_name VARCHAR(255) NOT NULL,
    action VARCHAR(50) NOT NULL, -- 'read', 'write', 'delete'
    user_id VARCHAR(100) NOT NULL,
    ip_address INET,
    user_agent TEXT,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    success BOOLEAN DEFAULT true,
    error_message TEXT
);

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_secrets_key_name ON vault.secrets(key_name);
CREATE INDEX IF NOT EXISTS idx_secrets_category ON vault.secrets(category);
CREATE INDEX IF NOT EXISTS idx_access_log_timestamp ON vault.access_log(timestamp);
CREATE INDEX IF NOT EXISTS idx_access_log_user ON vault.access_log(user_id);

-- Updated timestamp trigger
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER update_secrets_updated_at 
    BEFORE UPDATE ON vault.secrets 
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Insert some sample encrypted secrets (using simple ROT13 for demo)
-- In production, use proper encryption with the VAULT_MASTER_KEY
INSERT INTO vault.secrets (key_name, encrypted_value, category, created_by) VALUES
('sample_api_key', encode('demo_key_12345', 'base64'), 'api', 'init')
ON CONFLICT (key_name) DO NOTHING;

-- Grant permissions
GRANT USAGE ON SCHEMA vault TO hugo;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA vault TO hugo;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA vault TO hugo;

-- Success message
DO $$
BEGIN
    RAISE NOTICE 'Vault database initialized successfully!';
    RAISE NOTICE 'Tables created: vault.secrets, vault.access_log';
    RAISE NOTICE 'User: hugo has full access to vault schema';
END $$;