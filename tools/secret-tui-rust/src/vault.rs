// TODO: migrate this module from the custom vault.hugo.dk protocol to standard
// OIDC device-code flow against Authelia (login.hugo.dk).
//
// Why:
// - vault.hugo.dk isn't deployed; the endpoint is a placeholder.
// - Authelia is already the IdP for every other service (lldap-backed, passkeys,
//   group-gated policies). Using it here consolidates the trust chain.
//
// Migration scope:
// - Replace custom auth with `openidconnect::core::CoreClient` using
//   `ProviderMetadata::discover(https://login.hugo.dk/.well-known/openid-configuration)`
// - Use device authorization grant (RFC 8628) so the TUI stays headless-friendly
// - Gate admin actions (e.g. `secret-tui rotate ssh`) on the `lldap_admin` group
//   claim in the OIDC ID token
// - Add matching OIDC client in
//   clusters/wf-portal/apps/authelia/configmap.yaml (oidc.clients) with
//   `device_authorization` grant enabled
// - Delete the vault.hugo.dk DNS placeholder once the migration lands
//
// After migration: rename the `Vault` subcommand to `Auth` (or merge into the
// existing `Auth` command) and this module shrinks to token storage + device
// naming.

use anyhow::{Context, Result};
use hex::encode as hex_encode;
use rand::RngCore;
use reqwest::Client;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::{
    fs,
    path::PathBuf,
};

#[derive(Debug, Serialize, Deserialize)]
struct VaultDeviceConfig {
    base_url: String,
    device_id: String,
    device_name: String,
    public_key: String,
    claim_token: Option<String>,
    device_token: Option<String>,
}

#[derive(Debug, Serialize)]
struct RegisterRequest<'a> {
    device_id: &'a str,
    device_name: &'a str,
    public_key: &'a str,
}

#[derive(Debug, Deserialize)]
struct RegisterResponse {
    claim_token: String,
    approval_url: String,
}

#[derive(Debug, Deserialize)]
struct StatusResponse {
    status: String,
    device_token: Option<String>,
    message: Option<String>,
}

#[derive(Debug, Serialize)]
struct UnlockRequest<'a> {
    device_id: &'a str,
    device_token: &'a str,
}

#[derive(Debug, Deserialize)]
struct UnlockResponse {
    age_private_key: String,
}

pub struct PairResult {
    pub device_name: String,
    pub approval_url: String,
}

pub struct StatusResult {
    pub status: String,
    pub message: Option<String>,
    pub stored_token: bool,
}

pub struct VaultClient {
    config_path: PathBuf,
    config: VaultDeviceConfig,
    client: Client,
}

impl VaultClient {
    pub fn new(dotfiles_root: PathBuf, base_url: String) -> Result<Self> {
        let config_path = dotfiles_root.join(".vault-device.json");
        let config = if config_path.exists() {
            let content = fs::read_to_string(&config_path)?;
            serde_json::from_str::<VaultDeviceConfig>(&content)?
        } else {
            let device_name = hostname::get()
                .map(|value| value.to_string_lossy().to_string())
                .unwrap_or_else(|_| "unknown-device".to_string());
            VaultDeviceConfig {
                base_url: trim_base_url(&base_url),
                device_id: random_hex(16)?,
                device_name: device_name.clone(),
                public_key: fingerprint(&device_name),
                claim_token: None,
                device_token: None,
            }
        };

        Ok(Self {
            config_path,
            config,
            client: Client::new(),
        })
    }

    pub async fn pair(&mut self, base_url: String) -> Result<PairResult> {
        self.config.base_url = trim_base_url(&base_url);
        let response = self
            .client
            .post(format!("{}/api/v1/devices/register", self.config.base_url))
            .json(&RegisterRequest {
                device_id: &self.config.device_id,
                device_name: &self.config.device_name,
                public_key: &self.config.public_key,
            })
            .send()
            .await?
            .error_for_status()?
            .json::<RegisterResponse>()
            .await?;

        self.config.claim_token = Some(response.claim_token);
        self.config.device_token = None;
        self.save()?;

        Ok(PairResult {
            device_name: self.config.device_name.clone(),
            approval_url: response.approval_url,
        })
    }

    pub async fn status(&mut self, base_url: String) -> Result<StatusResult> {
        self.config.base_url = trim_base_url(&base_url);
        let claim_token = self
            .config
            .claim_token
            .clone()
            .context("No claim token. Run `secret-tui vault pair` first.")?;

        let response = self
            .client
            .get(format!(
                "{}/api/v1/devices/{}/status",
                self.config.base_url, self.config.device_id
            ))
            .query(&[("claim_token", claim_token)])
            .send()
            .await?
            .error_for_status()?
            .json::<StatusResponse>()
            .await?;

        let mut stored_token = false;
        if let Some(token) = response.device_token {
            self.config.device_token = Some(token);
            self.config.claim_token = None;
            self.save()?;
            stored_token = true;
        }
        Ok(StatusResult {
            status: response.status,
            message: response.message,
            stored_token,
        })
    }

    pub async fn unlock(&mut self, base_url: String, output: Option<PathBuf>) -> Result<PathBuf> {
        self.config.base_url = trim_base_url(&base_url);
        if self.config.device_token.is_none() && self.config.claim_token.is_some() {
            let _ = self.status(self.config.base_url.clone()).await?;
        }

        let device_token = self
            .config
            .device_token
            .clone()
            .context("No device token available. Pair and approve this machine first.")?;

        let response = self
            .client
            .post(format!("{}/api/v1/unlock", self.config.base_url))
            .json(&UnlockRequest {
                device_id: &self.config.device_id,
                device_token: &device_token,
            })
            .send()
            .await?
            .error_for_status()?
            .json::<UnlockResponse>()
            .await?;

        let target = output.unwrap_or_else(default_age_key_path);
        if let Some(parent) = target.parent() {
            fs::create_dir_all(parent)?;
        }
        fs::write(&target, format!("{}\n", response.age_private_key))?;
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            fs::set_permissions(&target, fs::Permissions::from_mode(0o600))?;
        }

        Ok(target)
    }

    fn save(&self) -> Result<()> {
        let payload = serde_json::to_string_pretty(&self.config)?;
        fs::write(&self.config_path, payload)?;
        Ok(())
    }
}

fn random_hex(bytes_len: usize) -> Result<String> {
    let mut bytes = vec![0u8; bytes_len];
    rand::thread_rng().fill_bytes(&mut bytes);
    Ok(hex_encode(bytes))
}

fn fingerprint(device_name: &str) -> String {
    let mut hasher = Sha256::new();
    hasher.update(device_name.as_bytes());
    hasher.update(b":vault-device");
    hex_encode(hasher.finalize())
}

fn trim_base_url(base_url: &str) -> String {
    base_url.trim().trim_end_matches('/').to_string()
}

fn default_age_key_path() -> PathBuf {
    dirs::home_dir()
        .unwrap_or_else(|| PathBuf::from("/tmp"))
        .join(".config/sops/age/keys.txt")
}
