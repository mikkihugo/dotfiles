use anyhow::{Context, Result};
use base64::{Engine as _, engine::general_purpose};
use chrono::{DateTime, Utc, Duration};
use reqwest::Client;
use serde::{Deserialize, Serialize};
use std::{collections::HashMap, fs, path::PathBuf};
use tokio::time::sleep;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AuthConfig {
    pub provider: AuthProvider,
    pub access_token: Option<String>,
    pub refresh_token: Option<String>,
    pub expires_at: Option<DateTime<Utc>>,
    pub device_id: String,
    pub device_name: String,
    pub sync_permissions: Vec<String>, // Which rooms/categories this device can access
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum AuthProvider {
    GitHub,
    Google,
    Microsoft,
    Custom {
        name: String,
        auth_url: String,
        token_url: String,
        device_code_url: String,
        client_id: String,
    },
}

#[derive(Debug, Deserialize)]
struct DeviceCodeResponse {
    device_code: String,
    user_code: String,
    verification_uri: String,
    verification_uri_complete: Option<String>,
    expires_in: u64,
    interval: u64,
}

#[derive(Debug, Deserialize)]
struct TokenResponse {
    access_token: String,
    refresh_token: Option<String>,
    expires_in: Option<u64>,
    scope: Option<String>,
}

#[derive(Debug, Deserialize)]
struct UserInfo {
    login: Option<String>,
    name: Option<String>,
    email: Option<String>,
}

pub struct SecretAuth {
    config: AuthConfig,
    config_path: PathBuf,
    client: Client,
}

impl SecretAuth {
    pub fn new(dotfiles_root: PathBuf, provider: AuthProvider) -> Result<Self> {
        let config_path = dotfiles_root.join(".secret-auth.json");
        let device_name = hostname::get()
            .map(|h| h.to_string_lossy().to_string())
            .unwrap_or_else(|_| "unknown-device".to_string());

        let config = if config_path.exists() {
            let content = fs::read_to_string(&config_path)?;
            serde_json::from_str(&content)?
        } else {
            AuthConfig {
                provider,
                access_token: None,
                refresh_token: None,
                expires_at: None,
                device_id: Self::generate_device_id(&device_name),
                device_name,
                sync_permissions: Vec::new(),
            }
        };

        Ok(Self {
            config,
            config_path,
            client: Client::new(),
        })
    }

    /// GitHub CLI-style device authentication flow
    pub async fn login(&mut self) -> Result<()> {
        println!("🔐 Starting device authentication...");

        match &self.config.provider {
            AuthProvider::GitHub => self.github_device_flow().await,
            AuthProvider::Google => self.google_device_flow().await,
            AuthProvider::Microsoft => self.microsoft_device_flow().await,
            AuthProvider::Custom { .. } => self.custom_device_flow().await,
        }?;

        // Fetch user info and sync permissions
        self.fetch_user_info().await?;
        self.fetch_sync_permissions().await?;

        self.save_config()?;
        println!("✅ Authentication successful!");
        Ok(())
    }

    async fn github_device_flow(&mut self) -> Result<()> {
        let client_id = "your-github-app-client-id"; // You'd register a GitHub App

        // Step 1: Request device code
        let device_response = self.client
            .post("https://github.com/login/device/code")
            .header("Accept", "application/json")
            .form(&[
                ("client_id", client_id),
                ("scope", "read:user"), // Minimal scope needed
            ])
            .send()
            .await?
            .json::<DeviceCodeResponse>()
            .await?;

        // Step 2: Show user instructions (like gh auth login)
        println!("🌐 Please visit: {}", device_response.verification_uri);
        println!("📝 Enter code: {}", device_response.user_code);

        if let Some(complete_uri) = &device_response.verification_uri_complete {
            println!("🔗 Or visit: {}", complete_uri);
            // Could auto-open browser like gh CLI does
            if let Err(_) = opener::open(complete_uri) {
                println!("   (Failed to open browser automatically)");
            }
        }

        // Step 3: Poll for authorization
        let poll_interval = std::time::Duration::from_secs(device_response.interval);
        let expires_at = Utc::now() + Duration::seconds(device_response.expires_in as i64);

        println!("⏳ Waiting for authentication...");

        while Utc::now() < expires_at {
            sleep(poll_interval).await;

            let token_response = self.client
                .post("https://github.com/login/oauth/access_token")
                .header("Accept", "application/json")
                .form(&[
                    ("client_id", client_id),
                    ("device_code", &device_response.device_code),
                    ("grant_type", "urn:ietf:params:oauth:grant-type:device_code"),
                ])
                .send()
                .await?;

            if token_response.status().is_success() {
                let token: TokenResponse = token_response.json().await?;

                self.config.access_token = Some(token.access_token);
                self.config.refresh_token = token.refresh_token;

                if let Some(expires_in) = token.expires_in {
                    self.config.expires_at = Some(Utc::now() + Duration::seconds(expires_in as i64));
                }

                return Ok(());
            }

            // Handle specific error cases
            let error_text = token_response.text().await?;
            if error_text.contains("authorization_pending") {
                continue; // Keep polling
            } else if error_text.contains("expired_token") {
                anyhow::bail!("Device code expired. Please run 'secret-tui auth login' again.");
            } else if error_text.contains("access_denied") {
                anyhow::bail!("Authentication was denied.");
            }
        }

        anyhow::bail!("Authentication timed out.")
    }

    async fn google_device_flow(&mut self) -> Result<()> {
        // Similar to GitHub but using Google OAuth endpoints
        // https://developers.google.com/identity/protocols/oauth2/limited-input-device
        todo!("Implement Google device flow")
    }

    async fn microsoft_device_flow(&mut self) -> Result<()> {
        // Microsoft device flow for Azure AD
        // https://docs.microsoft.com/en-us/azure/active-directory/develop/v2-oauth2-device-code
        todo!("Implement Microsoft device flow")
    }

    async fn custom_device_flow(&mut self) -> Result<()> {
        // Custom OAuth provider (like your own identity server)
        todo!("Implement custom OAuth provider flow")
    }

    async fn fetch_user_info(&mut self) -> Result<()> {
        if let Some(token) = &self.config.access_token {
            let user_info: UserInfo = self.client
                .get("https://api.github.com/user")
                .bearer_auth(token)
                .send()
                .await?
                .json()
                .await?;

            if let Some(login) = user_info.login {
                self.config.device_name = format!("{}-{}", login, self.config.device_name);
            }
        }
        Ok(())
    }

    async fn fetch_sync_permissions(&mut self) -> Result<()> {
        // Query your auth server for what sync rooms/categories this user can access
        // This would hit your custom API that manages sync permissions
        if let Some(token) = &self.config.access_token {
            // Example: GET /api/sync/permissions
            let permissions_response = self.client
                .get("https://your-auth-server.com/api/sync/permissions")
                .bearer_auth(token)
                .send()
                .await;

            if let Ok(response) = permissions_response {
                if let Ok(permissions) = response.json::<Vec<String>>().await {
                    self.config.sync_permissions = permissions;
                }
            }
            // Don't fail if permissions server is down - use defaults
        }
        Ok(())
    }

    pub async fn refresh_token_if_needed(&mut self) -> Result<bool> {
        if let Some(expires_at) = self.config.expires_at {
            if Utc::now() + Duration::minutes(5) > expires_at {
                if let Some(refresh_token) = &self.config.refresh_token.clone() {
                    return self.refresh_access_token(refresh_token).await;
                } else {
                    // No refresh token, need to re-authenticate
                    return Ok(false);
                }
            }
        }
        Ok(true)
    }

    async fn refresh_access_token(&mut self, refresh_token: &str) -> Result<bool> {
        // Implement token refresh logic based on provider
        match &self.config.provider {
            AuthProvider::GitHub => {
                // GitHub doesn't typically provide refresh tokens for device flow
                // Would need to re-authenticate
                Ok(false)
            }
            _ => {
                // Other providers might support refresh tokens
                todo!("Implement token refresh for other providers")
            }
        }
    }

    pub fn is_authenticated(&self) -> bool {
        self.config.access_token.is_some() &&
        self.config.expires_at.map_or(true, |exp| Utc::now() < exp)
    }

    pub fn get_access_token(&self) -> Option<&String> {
        self.config.access_token.as_ref()
    }

    pub fn logout(&mut self) -> Result<()> {
        self.config.access_token = None;
        self.config.refresh_token = None;
        self.config.expires_at = None;
        self.config.sync_permissions.clear();
        self.save_config()?;
        println!("👋 Logged out successfully");
        Ok(())
    }

    pub fn status(&self) -> String {
        if self.is_authenticated() {
            format!(
                "✅ Authenticated as {} (device: {})\n   Provider: {:?}\n   Permissions: {:?}\n   Expires: {:?}",
                self.config.device_name,
                self.config.device_id,
                self.config.provider,
                self.config.sync_permissions,
                self.config.expires_at
            )
        } else {
            "❌ Not authenticated. Run 'secret-tui auth login'".to_string()
        }
    }

    fn generate_device_id(device_name: &str) -> String {
        use sha2::{Sha256, Digest};
        let mut hasher = Sha256::new();
        hasher.update(device_name);
        hasher.update(Utc::now().timestamp().to_string());
        hex::encode(hasher.finalize())[..16].to_string()
    }

    fn save_config(&self) -> Result<()> {
        let content = serde_json::to_string_pretty(&self.config)?;
        fs::write(&self.config_path, content)?;
        Ok(())
    }
}

// Integration with sync module
impl From<&AuthConfig> for String {
    fn from(auth: &AuthConfig) -> String {
        // Generate room-specific sync key based on authenticated user + device
        use sha2::{Sha256, Digest};
        let mut hasher = Sha256::new();
        hasher.update(&auth.device_id);
        if let Some(token) = &auth.access_token {
            hasher.update(token);
        }
        general_purpose::STANDARD.encode(hasher.finalize())
    }
}