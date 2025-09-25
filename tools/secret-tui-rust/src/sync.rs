use anyhow::{Context, Result};
use base64::{Engine as _, engine::general_purpose};
use chacha20poly1305::{
    aead::{Aead, AeadCore, KeyInit, OsRng},
    ChaCha20Poly1305, Nonce, Key
};
use chrono::{DateTime, Utc};
use rand::RngCore;
use reqwest::Client;
use serde::{Deserialize, Serialize};
use sha2::{Sha256, Digest};
use std::{
    collections::HashMap,
    fs,
    path::{Path, PathBuf},
    time::Duration,
};
use tokio::time::sleep;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SyncConfig {
    pub device_name: String,
    pub sync_key: String, // Base64 encoded 32-byte key
    pub sync_methods: Vec<SyncMethod>,
    pub auto_sync: bool,
    pub last_sync: Option<DateTime<Utc>>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum SyncMethod {
    /// Direct P2P via local network discovery
    LocalNetwork {
        port: u16,
        discovery_port: u16,
    },
    /// Via secure relay server (self-hosted)
    Relay {
        server_url: String,
        room_id: String,
    },
    /// Via serverless relay (Vercel/Netlify/Cloudflare)
    ServerlessRelay {
        provider: ServerlessProvider,
        server_url: String,
        room_id: String,
    },
    /// Via encrypted file drop (syncthing/dropbox folder)
    FileDrop {
        sync_folder: PathBuf,
    },
    /// Via encrypted webhook/API
    Webhook {
        endpoint: String,
        auth_token: String,
    },
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum ServerlessProvider {
    Vercel,
    Netlify,
    CloudflareWorkers,
    Custom { name: String },
}

#[derive(Debug, Serialize, Deserialize)]
pub struct SyncPacket {
    pub device_id: String,
    pub timestamp: DateTime<Utc>,
    pub sequence: u64,
    pub encrypted_data: String, // Base64 encoded encrypted payload
    pub nonce: String,          // Base64 encoded nonce
    pub checksum: String,       // SHA256 of decrypted data
}

#[derive(Debug, Serialize, Deserialize)]
pub struct SecretData {
    pub categories: HashMap<String, HashMap<String, String>>,
    pub metadata: HashMap<String, SecretMetadata>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct SecretMetadata {
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    pub updated_by: String, // device_name
}

pub struct SecretSync {
    config: SyncConfig,
    config_path: PathBuf,
    dotfiles_root: PathBuf,
    client: Client,
}

impl SecretSync {
    pub fn new(dotfiles_root: PathBuf) -> Result<Self> {
        let config_path = dotfiles_root.join(".sync-config.json");
        let config = if config_path.exists() {
            let content = fs::read_to_string(&config_path)?;
            serde_json::from_str(&content)?
        } else {
            Self::create_default_config()?
        };

        let client = Client::new();

        Ok(Self {
            config,
            config_path,
            dotfiles_root,
            client,
        })
    }

    fn create_default_config() -> Result<SyncConfig> {
        let device_name = hostname::get()
            .map(|h| h.to_string_lossy().to_string())
            .unwrap_or_else(|_| "unknown".to_string());

        // Generate a random 256-bit sync key
        let mut key_bytes = [0u8; 32];
        OsRng.fill_bytes(&mut key_bytes);
        let sync_key = general_purpose::STANDARD.encode(key_bytes);

        Ok(SyncConfig {
            device_name,
            sync_key,
            sync_methods: vec![
                SyncMethod::LocalNetwork {
                    port: 8765,
                    discovery_port: 8766,
                },
                // Example serverless configurations (commented out by default)
                // Uncomment and configure your preferred serverless provider:
                /*
                SyncMethod::ServerlessRelay {
                    provider: ServerlessProvider::Vercel,
                    server_url: "https://your-app.vercel.app".to_string(),
                    room_id: "your-shared-room-id".to_string(),
                },
                */
            ],
            auto_sync: false,
            last_sync: None,
        })
    }

    pub fn save_config(&self) -> Result<()> {
        let content = serde_json::to_string_pretty(&self.config)?;
        fs::write(&self.config_path, content)?;
        Ok(())
    }

    pub fn get_config(&self) -> &SyncConfig {
        &self.config
    }

    pub fn add_sync_method(&mut self, method: SyncMethod) -> Result<()> {
        self.config.sync_methods.push(method);
        self.save_config()
    }

    pub fn generate_pairing_qr(&self) -> Result<String> {
        let pairing_data = serde_json::json!({
            "type": "secret_sync_pairing",
            "device_name": self.config.device_name,
            "sync_key": self.config.sync_key,
            "methods": self.config.sync_methods
        });

        let qr_data = serde_json::to_string(&pairing_data)?;
        let code = qrcode::QrCode::new(&qr_data)?;
        Ok(code.render::<char>()
            .quiet_zone(false)
            .module_dimensions(2, 1)
            .build())
    }

    pub async fn discover_peers(&self) -> Result<Vec<String>> {
        let mut peers = Vec::new();

        for method in &self.config.sync_methods {
            match method {
                SyncMethod::LocalNetwork { discovery_port, .. } => {
                    // Broadcast discovery on local network
                    peers.extend(self.discover_local_peers(*discovery_port).await?);
                }
                SyncMethod::Relay { server_url, room_id } => {
                    // Query relay server for peers in room
                    peers.extend(self.discover_relay_peers(server_url, room_id).await?);
                }
                SyncMethod::ServerlessRelay { server_url, room_id, .. } => {
                    // Query serverless relay for peers in room
                    peers.extend(self.discover_relay_peers(server_url, room_id).await?);
                }
                _ => {} // Other methods don't have discovery
            }
        }

        Ok(peers)
    }

    async fn discover_local_peers(&self, discovery_port: u16) -> Result<Vec<String>> {
        use tokio::net::UdpSocket;
        use std::collections::HashSet;

        // Bind discovery socket
        let discovery_socket = UdpSocket::bind(format!("0.0.0.0:{}", discovery_port)).await?;
        discovery_socket.set_broadcast(true)?;

        // Also bind listening socket for responses
        let listen_socket = UdpSocket::bind("0.0.0.0:0").await?;

        let discovery_msg = serde_json::json!({
            "type": "secret_sync_discovery",
            "device_name": self.config.device_name,
            "device_id": self.get_device_id(),
            "sync_key_hash": self.get_sync_key_hash(),
            "timestamp": Utc::now(),
            "response_port": listen_socket.local_addr()?.port()
        });

        // Enhanced broadcast to multiple network ranges
        let broadcast_addresses = [
            // Common home networks
            format!("192.168.1.255:{}", discovery_port),
            format!("192.168.0.255:{}", discovery_port),
            format!("192.168.2.255:{}", discovery_port),
            // Corporate networks
            format!("10.0.0.255:{}", discovery_port),
            format!("10.1.0.255:{}", discovery_port),
            format!("172.16.0.255:{}", discovery_port),
            // Local subnet detection
            format!("255.255.255.255:{}", discovery_port), // Limited broadcast
        ];

        // Send discovery broadcasts
        for addr in &broadcast_addresses {
            if let Ok(addr_parsed) = addr.parse() {
                let _ = discovery_socket.send_to(
                    discovery_msg.to_string().as_bytes(),
                    addr_parsed
                ).await;
            }
        }

        // Listen for responses with timeout
        let mut peers = HashSet::new();
        let mut buf = [0; 2048];
        let listen_timeout = Duration::from_secs(5);

        let deadline = tokio::time::Instant::now() + listen_timeout;

        while tokio::time::Instant::now() < deadline {
            tokio::select! {
                _ = tokio::time::sleep_until(deadline) => break,
                result = listen_socket.recv_from(&mut buf) => {
                    if let Ok((len, peer_addr)) = result {
                        if let Ok(response) = String::from_utf8(buf[..len].to_vec()) {
                            if let Ok(data) = serde_json::from_str::<serde_json::Value>(&response) {
                                // Verify it's a sync response with matching key hash
                                if data["type"] == "secret_sync_response"
                                    && data["sync_key_hash"] == self.get_sync_key_hash()
                                    && data["device_id"] != self.get_device_id() {

                                    let peer_info = format!("{}:{}",
                                        peer_addr.ip(),
                                        data["sync_port"].as_u64().unwrap_or(8765)
                                    );
                                    peers.insert(peer_info);
                                }
                            }
                        }
                    }
                }
            }
        }

        Ok(peers.into_iter().collect())
    }

    fn get_sync_key_hash(&self) -> String {
        use sha2::{Sha256, Digest};
        let mut hasher = Sha256::new();
        hasher.update(&self.config.sync_key);
        hex::encode(hasher.finalize())[..16].to_string()
    }

    async fn discover_relay_peers(&self, server_url: &str, room_id: &str) -> Result<Vec<String>> {
        let url = format!("{}/room/{}/peers", server_url, room_id);
        let response = self.client
            .get(&url)
            .timeout(Duration::from_secs(5))
            .send()
            .await?;

        let peers: Vec<String> = response.json().await?;
        Ok(peers)
    }

    pub async fn sync_secrets(&mut self) -> Result<SyncResult> {
        let current_data = self.load_current_secrets()?;
        let mut sync_result = SyncResult {
            synced_categories: Vec::new(),
            conflicts: Vec::new(),
            errors: Vec::new(),
        };

        for method in &self.config.sync_methods.clone() {
            match self.sync_via_method(method, &current_data).await {
                Ok(result) => {
                    sync_result.merge(result);
                }
                Err(e) => {
                    sync_result.errors.push(format!("Sync method failed: {}", e));
                }
            }
        }

        self.config.last_sync = Some(Utc::now());
        self.save_config()?;

        Ok(sync_result)
    }

    async fn sync_via_method(&self, method: &SyncMethod, data: &SecretData) -> Result<SyncResult> {
        match method {
            SyncMethod::LocalNetwork { port, .. } => {
                self.sync_local_network(*port, data).await
            }
            SyncMethod::Relay { server_url, room_id } => {
                self.sync_relay(server_url, room_id, data).await
            }
            SyncMethod::ServerlessRelay { provider, server_url, room_id } => {
                self.sync_serverless_relay(provider, server_url, room_id, data).await
            }
            SyncMethod::FileDrop { sync_folder } => {
                self.sync_file_drop(sync_folder, data).await
            }
            SyncMethod::Webhook { endpoint, auth_token } => {
                self.sync_webhook(endpoint, auth_token, data).await
            }
        }
    }

    async fn sync_local_network(&self, _port: u16, data: &SecretData) -> Result<SyncResult> {
        // Create encrypted packet
        let packet = self.create_sync_packet(data)?;

        // Send to discovered peers
        let peers = self.discover_peers().await?;
        let mut result = SyncResult::default();

        for peer in peers {
            match self.send_to_peer(&peer, &packet).await {
                Ok(_) => {
                    result.synced_categories.push("local_network".to_string());
                }
                Err(e) => {
                    result.errors.push(format!("Failed to sync with {}: {}", peer, e));
                }
            }
        }

        Ok(result)
    }

    async fn sync_relay(&self, server_url: &str, room_id: &str, data: &SecretData) -> Result<SyncResult> {
        let packet = self.create_sync_packet(data)?;
        let url = format!("{}/room/{}/sync", server_url, room_id);

        let response = self.client
            .post(&url)
            .json(&packet)
            .timeout(Duration::from_secs(30))
            .send()
            .await?;

        if response.status().is_success() {
            Ok(SyncResult {
                synced_categories: vec!["relay".to_string()],
                conflicts: Vec::new(),
                errors: Vec::new(),
            })
        } else {
            anyhow::bail!("Relay sync failed: {}", response.status());
        }
    }

    async fn sync_serverless_relay(&self, provider: &ServerlessProvider, server_url: &str, room_id: &str, data: &SecretData) -> Result<SyncResult> {
        let packet = self.create_sync_packet(data)?;

        // Prepare payload for serverless relay API
        let relay_payload = serde_json::json!({
            "from_device": self.get_device_id(),
            "device_name": self.config.device_name,
            "encrypted_payload": serde_json::to_string(&packet)?,
            "timestamp": Utc::now().to_rfc3339(),
        });

        // Send to serverless relay
        let url = format!("{}/sync/{}", server_url, room_id);
        let response = self.client
            .post(&url)
            .header("Content-Type", "application/json")
            .json(&relay_payload)
            .timeout(Duration::from_secs(30))
            .send()
            .await?;

        if response.status().is_success() {
            // Also try to retrieve any pending messages for this device
            let device_id = self.get_device_id();
            let retrieve_url = format!("{}/sync/{}?device_id={}", server_url, room_id, device_id);

            if let Ok(retrieve_response) = self.client
                .get(&retrieve_url)
                .timeout(Duration::from_secs(15))
                .send()
                .await
            {
                if retrieve_response.status().is_success() {
                    if let Ok(incoming_data) = retrieve_response.json::<serde_json::Value>().await {
                        if let Some(messages) = incoming_data.get("messages").and_then(|m| m.as_array()) {
                            // Process incoming messages (simplified for now)
                            for message in messages {
                                // Could decrypt and merge incoming secrets here
                                // For now, just log that we received messages
                                eprintln!("📥 Received sync message from serverless relay");
                            }
                        }
                    }
                }
            }

            let provider_name = match provider {
                ServerlessProvider::Vercel => "vercel",
                ServerlessProvider::Netlify => "netlify",
                ServerlessProvider::CloudflareWorkers => "cloudflare",
                ServerlessProvider::Custom { name } => name,
            };

            Ok(SyncResult {
                synced_categories: vec![format!("serverless-{}", provider_name)],
                conflicts: Vec::new(),
                errors: Vec::new(),
            })
        } else {
            anyhow::bail!("Serverless relay sync failed: {}", response.status());
        }
    }

    async fn sync_file_drop(&self, sync_folder: &Path, data: &SecretData) -> Result<SyncResult> {
        let packet = self.create_sync_packet(data)?;
        let device_id = self.get_device_id();
        let filename = format!("secrets-{}-{}.sync", device_id, Utc::now().timestamp());
        let sync_file = sync_folder.join(filename);

        let content = serde_json::to_string_pretty(&packet)?;
        fs::write(sync_file, content)?;

        // Also check for incoming sync files
        let mut conflicts = Vec::new();
        if let Ok(entries) = fs::read_dir(sync_folder) {
            for entry in entries {
                if let Ok(entry) = entry {
                    let path = entry.path();
                    if path.extension().and_then(|s| s.to_str()) == Some("sync") {
                        if let Ok(incoming) = self.process_incoming_sync_file(&path) {
                            conflicts.extend(incoming.conflicts);
                        }
                    }
                }
            }
        }

        Ok(SyncResult {
            synced_categories: vec!["file_drop".to_string()],
            conflicts,
            errors: Vec::new(),
        })
    }

    async fn sync_webhook(&self, endpoint: &str, auth_token: &str, data: &SecretData) -> Result<SyncResult> {
        let packet = self.create_sync_packet(data)?;

        let response = self.client
            .post(endpoint)
            .header("Authorization", format!("Bearer {}", auth_token))
            .json(&packet)
            .timeout(Duration::from_secs(30))
            .send()
            .await?;

        if response.status().is_success() {
            Ok(SyncResult {
                synced_categories: vec!["webhook".to_string()],
                conflicts: Vec::new(),
                errors: Vec::new(),
            })
        } else {
            anyhow::bail!("Webhook sync failed: {}", response.status());
        }
    }

    fn create_sync_packet(&self, data: &SecretData) -> Result<SyncPacket> {
        let key_bytes = general_purpose::STANDARD.decode(&self.config.sync_key)?;
        let key = Key::from_slice(&key_bytes);
        let cipher = ChaCha20Poly1305::new(key);

        let plaintext = serde_json::to_vec(data)?;
        let nonce = ChaCha20Poly1305::generate_nonce(&mut OsRng);
        let encrypted = cipher.encrypt(&nonce, plaintext.as_slice())
            .map_err(|_| anyhow::anyhow!("Encryption failed"))?;

        let checksum = {
            let mut hasher = Sha256::new();
            hasher.update(&plaintext);
            hex::encode(hasher.finalize())
        };

        Ok(SyncPacket {
            device_id: self.get_device_id(),
            timestamp: Utc::now(),
            sequence: self.get_next_sequence(),
            encrypted_data: general_purpose::STANDARD.encode(encrypted),
            nonce: general_purpose::STANDARD.encode(nonce),
            checksum,
        })
    }

    fn load_current_secrets(&self) -> Result<SecretData> {
        let mut categories = HashMap::new();
        let mut metadata = HashMap::new();

        let secrets_dir = self.dotfiles_root.join("secrets");
        if !secrets_dir.exists() {
            return Ok(SecretData { categories, metadata });
        }

        for entry in fs::read_dir(&secrets_dir)? {
            let entry = entry?;
            let path = entry.path();

            if path.extension().and_then(|s| s.to_str()) == Some("yaml") {
                let category_name = path.file_stem()
                    .and_then(|s| s.to_str())
                    .unwrap_or("unknown")
                    .to_string();

                if category_name == "shared" {
                    continue; // Skip shared.yaml - we're using categorized structure
                }

                match self.decrypt_sops_file(&path) {
                    Ok(content) => {
                        if let Ok(secrets) = serde_yaml::from_str::<HashMap<String, String>>(&content) {
                            categories.insert(category_name.clone(), secrets);

                            // Add metadata
                            let file_meta = fs::metadata(&path)?;
                            if let Ok(modified) = file_meta.modified() {
                                metadata.insert(category_name, SecretMetadata {
                                    created_at: modified.into(),
                                    updated_at: modified.into(),
                                    updated_by: self.config.device_name.clone(),
                                });
                            }
                        }
                    }
                    Err(_) => {
                        // Skip files that can't be decrypted
                        continue;
                    }
                }
            }
        }

        Ok(SecretData { categories, metadata })
    }

    fn decrypt_sops_file(&self, file_path: &Path) -> Result<String> {
        let sops_key_file = dirs::home_dir()
            .context("Cannot find home directory")?
            .join(".config/sops/age/keys.txt");

        let output = std::process::Command::new("sops")
            .args(["-d", &file_path.to_string_lossy()])
            .env("SOPS_AGE_KEY_FILE", &sops_key_file)
            .output()
            .context("Failed to run sops command")?;

        if !output.status.success() {
            let error = String::from_utf8_lossy(&output.stderr);
            anyhow::bail!("SOPS decryption failed: {}", error);
        }

        Ok(String::from_utf8(output.stdout)?)
    }

    async fn send_to_peer(&self, peer: &str, packet: &SyncPacket) -> Result<()> {
        let response = self.client
            .post(&format!("http://{}/sync", peer))
            .json(packet)
            .timeout(Duration::from_secs(10))
            .send()
            .await?;

        if response.status().is_success() {
            Ok(())
        } else {
            anyhow::bail!("Peer sync failed: {}", response.status());
        }
    }

    fn process_incoming_sync_file(&self, path: &Path) -> Result<SyncResult> {
        let content = fs::read_to_string(path)?;
        let packet: SyncPacket = serde_json::from_str(&content)?;

        // Decrypt and process the sync packet
        self.process_sync_packet(packet)
    }

    fn process_sync_packet(&self, packet: SyncPacket) -> Result<SyncResult> {
        let key_bytes = general_purpose::STANDARD.decode(&self.config.sync_key)?;
        let key = Key::from_slice(&key_bytes);
        let cipher = ChaCha20Poly1305::new(key);

        let nonce_bytes = general_purpose::STANDARD.decode(&packet.nonce)?;
        let nonce = Nonce::from_slice(&nonce_bytes);
        let encrypted_data = general_purpose::STANDARD.decode(&packet.encrypted_data)?;

        let decrypted = cipher.decrypt(nonce, encrypted_data.as_slice())
            .map_err(|_| anyhow::anyhow!("Decryption failed"))?;

        let incoming_data: SecretData = serde_json::from_slice(&decrypted)?;

        // Verify checksum
        let mut hasher = Sha256::new();
        hasher.update(&decrypted);
        let computed_checksum = hex::encode(hasher.finalize());

        if computed_checksum != packet.checksum {
            anyhow::bail!("Checksum verification failed");
        }

        // Process the incoming data and detect conflicts
        self.merge_secrets(incoming_data, &packet.device_id)
    }

    fn merge_secrets(&self, incoming: SecretData, source_device: &str) -> Result<SyncResult> {
        let current = self.load_current_secrets()?;
        let mut result = SyncResult::default();

        for (category, incoming_secrets) in incoming.categories {
            if let Some(current_secrets) = current.categories.get(&category) {
                // Check for conflicts
                for (key, incoming_value) in &incoming_secrets {
                    if let Some(current_value) = current_secrets.get(key) {
                        if current_value != incoming_value {
                            result.conflicts.push(SyncConflict {
                                category: category.clone(),
                                key: key.clone(),
                                local_value: current_value.clone(),
                                remote_value: incoming_value.clone(),
                                remote_device: source_device.to_string(),
                            });
                        }
                    }
                }
            }

            result.synced_categories.push(category);
        }

        Ok(result)
    }

    fn get_device_id(&self) -> String {
        // Create a stable device ID from the device name and sync key
        let mut hasher = Sha256::new();
        hasher.update(format!("{}:{}", self.config.device_name, self.config.sync_key));
        hex::encode(hasher.finalize())[..16].to_string()
    }

    fn get_next_sequence(&self) -> u64 {
        // Simple sequence number based on timestamp
        Utc::now().timestamp() as u64
    }

    // Convenience methods for setting up serverless providers
    pub fn add_vercel_relay(&mut self, server_url: String, room_id: String) -> Result<()> {
        let method = SyncMethod::ServerlessRelay {
            provider: ServerlessProvider::Vercel,
            server_url,
            room_id,
        };
        self.add_sync_method(method)
    }

    pub fn add_netlify_relay(&mut self, server_url: String, room_id: String) -> Result<()> {
        let method = SyncMethod::ServerlessRelay {
            provider: ServerlessProvider::Netlify,
            server_url,
            room_id,
        };
        self.add_sync_method(method)
    }

    pub fn add_cloudflare_relay(&mut self, server_url: String, room_id: String) -> Result<()> {
        let method = SyncMethod::ServerlessRelay {
            provider: ServerlessProvider::CloudflareWorkers,
            server_url,
            room_id,
        };
        self.add_sync_method(method)
    }

    pub fn add_custom_serverless_relay(&mut self, provider_name: String, server_url: String, room_id: String) -> Result<()> {
        let method = SyncMethod::ServerlessRelay {
            provider: ServerlessProvider::Custom { name: provider_name },
            server_url,
            room_id,
        };
        self.add_sync_method(method)
    }

    pub fn list_serverless_providers(&self) -> Vec<&ServerlessProvider> {
        self.config.sync_methods.iter()
            .filter_map(|method| match method {
                SyncMethod::ServerlessRelay { provider, .. } => Some(provider),
                _ => None,
            })
            .collect()
    }

    pub async fn test_serverless_relay(&self, provider: &ServerlessProvider, server_url: &str) -> Result<bool> {
        let health_url = format!("{}/health", server_url);
        let response = self.client
            .get(&health_url)
            .timeout(Duration::from_secs(10))
            .send()
            .await?;

        Ok(response.status().is_success())
    }
}

#[derive(Debug, Default)]
pub struct SyncResult {
    pub synced_categories: Vec<String>,
    pub conflicts: Vec<SyncConflict>,
    pub errors: Vec<String>,
}

impl SyncResult {
    fn merge(&mut self, other: SyncResult) {
        self.synced_categories.extend(other.synced_categories);
        self.conflicts.extend(other.conflicts);
        self.errors.extend(other.errors);
    }
}

#[derive(Debug)]
pub struct SyncConflict {
    pub category: String,
    pub key: String,
    pub local_value: String,
    pub remote_value: String,
    pub remote_device: String,
}