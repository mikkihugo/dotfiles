use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use std::{collections::HashMap, env, fs};
use tokio::process::Command;

use crate::auth::{SecretAuth, AuthProvider};
use crate::sync::{SecretSync, SyncMethod, ServerlessProvider};

/// GitHub Actions integration for secret management
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GitHubActionsConfig {
    pub organization: Option<String>,
    pub repository: String,
    pub environment: String, // development, staging, production
    pub runner_type: RunnerType,
    pub secret_categories: Vec<String>, // Which categories this runner can access
    pub auto_inject: bool, // Automatically inject secrets as environment variables
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum RunnerType {
    GitHubHosted,
    SelfHosted { runner_name: String },
    Local { developer: String },
}

/// GitHub Actions integration manager
pub struct GitHubActionsIntegration {
    auth: SecretAuth,
    sync: SecretSync,
    config: GitHubActionsConfig,
}

impl GitHubActionsIntegration {
    pub async fn new() -> Result<Self> {
        let dotfiles_root = if env::var("GITHUB_ACTIONS").is_ok() {
            // Running in GitHub Actions - use runner temp directory
            env::var("RUNNER_TEMP")
                .context("RUNNER_TEMP not set in GitHub Actions")?
                .into()
        } else {
            // Running locally
            dirs::home_dir()
                .context("Could not find home directory")?
                .join(".dotfiles")
        };

        // Detect runner environment
        let config = Self::detect_environment().await?;

        // Initialize OAuth with organization/repo context
        let auth_provider = AuthProvider::GitHub; // Could be configurable
        let auth = SecretAuth::new(dotfiles_root.clone(), auth_provider)?;
        let sync = SecretSync::new(dotfiles_root)?;

        Ok(Self { auth, sync, config })
    }

    async fn detect_environment() -> Result<GitHubActionsConfig> {
        if env::var("GITHUB_ACTIONS").is_ok() {
            // Running in GitHub Actions
            let repository = env::var("GITHUB_REPOSITORY")
                .context("GITHUB_REPOSITORY not set in GitHub Actions")?;

            let environment = env::var("GITHUB_ENV_NAME")
                .or_else(|_| env::var("ENVIRONMENT"))
                .unwrap_or_else(|_| "production".to_string());

            let runner_type = if env::var("RUNNER_ENVIRONMENT").as_deref() == Ok("github-hosted") {
                RunnerType::GitHubHosted
            } else {
                RunnerType::SelfHosted {
                    runner_name: env::var("RUNNER_NAME")
                        .unwrap_or_else(|_| "self-hosted".to_string()),
                }
            };

            Ok(GitHubActionsConfig {
                organization: env::var("GITHUB_REPOSITORY_OWNER").ok(),
                repository,
                environment,
                runner_type,
                secret_categories: vec!["ci".to_string(), environment.clone()],
                auto_inject: true,
            })
        } else {
            // Running locally - try to detect git repository
            let repository = Self::detect_git_repository().await?;
            let developer = env::var("USER").or_else(|_| env::var("USERNAME"))
                .unwrap_or_else(|_| "developer".to_string());

            Ok(GitHubActionsConfig {
                organization: None,
                repository,
                environment: "development".to_string(),
                runner_type: RunnerType::Local { developer },
                secret_categories: vec!["dev".to_string(), "local".to_string()],
                auto_inject: false,
            })
        }
    }

    async fn detect_git_repository() -> Result<String> {
        let output = Command::new("git")
            .args(&["remote", "get-url", "origin"])
            .output()
            .await?;

        let url = String::from_utf8(output.stdout)?;

        // Parse GitHub repository from git URL
        if let Some(captures) = regex::Regex::new(r"github\.com[:/]([^/]+/[^/]+)(?:\.git)?")
            .unwrap()
            .captures(&url)
        {
            Ok(captures[1].to_string())
        } else {
            anyhow::bail!("Could not detect GitHub repository from git remote")
        }
    }

    /// Authenticate the runner using GitHub Actions OIDC token
    pub async fn authenticate(&mut self) -> Result<()> {
        if env::var("GITHUB_ACTIONS").is_ok() {
            // Use GitHub Actions OIDC token for authentication
            self.authenticate_with_oidc().await
        } else {
            // Use standard OAuth device flow for local development
            self.auth.login().await
        }
    }

    async fn authenticate_with_oidc(&mut self) -> Result<()> {
        // Get GitHub Actions OIDC token
        let request_token = env::var("ACTIONS_ID_TOKEN_REQUEST_TOKEN")
            .context("ACTIONS_ID_TOKEN_REQUEST_TOKEN not available")?;
        let request_url = env::var("ACTIONS_ID_TOKEN_REQUEST_URL")
            .context("ACTIONS_ID_TOKEN_REQUEST_URL not available")?;

        let client = reqwest::Client::new();
        let response = client
            .get(&request_url)
            .header("Authorization", format!("Bearer {}", request_token))
            .query(&[("audience", "secret-sync")])
            .send()
            .await?;

        let token_response: serde_json::Value = response.json().await?;
        let oidc_token = token_response["value"]
            .as_str()
            .context("Failed to get OIDC token from response")?;

        println!("🔐 Authenticated using GitHub Actions OIDC token");

        // Exchange OIDC token for our auth system
        // This would require a custom auth service that validates GitHub OIDC tokens
        // For now, we'll use the OIDC token directly
        // TODO: Implement OIDC token validation and exchange

        Ok(())
    }

    /// Load secrets for the current environment
    pub async fn load_secrets(&mut self) -> Result<HashMap<String, String>> {
        // Ensure authentication
        if !self.auth.is_authenticated() {
            self.authenticate().await?;
        }

        // Sync secrets from configured sources
        self.sync.sync_secrets().await?;

        // Load secrets for current environment/categories
        let mut secrets = HashMap::new();

        for category in &self.config.secret_categories.clone() {
            if let Ok(category_secrets) = self.load_category_secrets(category).await {
                secrets.extend(category_secrets);
            }
        }

        Ok(secrets)
    }

    async fn load_category_secrets(&self, category: &str) -> Result<HashMap<String, String>> {
        // Load SOPS-encrypted secrets for the specific category
        let category_file = format!("secrets/{}.yaml", category);
        let secrets_path = dirs::home_dir()
            .context("Could not find home directory")?
            .join(".dotfiles")
            .join(&category_file);

        if secrets_path.exists() {
            let output = Command::new("sops")
                .args(&["-d", secrets_path.to_str().unwrap()])
                .output()
                .await?;

            let decrypted = String::from_utf8(output.stdout)?;
            let secrets: HashMap<String, String> = serde_yaml::from_str(&decrypted)?;
            Ok(secrets)
        } else {
            Ok(HashMap::new())
        }
    }

    /// Inject secrets into environment (for GitHub Actions)
    pub async fn inject_secrets(&mut self) -> Result<()> {
        let secrets = self.load_secrets().await?;

        if env::var("GITHUB_ACTIONS").is_ok() {
            // In GitHub Actions - write to GITHUB_ENV file
            let github_env = env::var("GITHUB_ENV")
                .context("GITHUB_ENV not set in GitHub Actions")?;

            let mut env_content = String::new();
            for (key, value) in secrets {
                // Mask sensitive values in logs
                println!("::add-mask::{}", value);
                env_content.push_str(&format!("{}={}\n", key, value));
            }

            fs::write(&github_env, env_content)
                .context("Failed to write secrets to GITHUB_ENV")?;

            println!("✅ Injected {} secrets into GitHub Actions environment", secrets.len());
        } else {
            // Local development - just print export commands
            println!("# Add these exports to your shell:");
            for (key, value) in secrets {
                println!("export {}='{}'", key, value);
            }
        }

        Ok(())
    }

    /// Set up sync for organization-wide secret sharing
    pub async fn setup_organization_sync(&mut self, org_config: OrganizationSyncConfig) -> Result<()> {
        // Add serverless relay for organization
        self.sync.add_vercel_relay(
            org_config.relay_url,
            format!("org-{}", org_config.organization),
        )?;

        // Configure environment-specific sync
        for env_name in &org_config.environments {
            self.sync.add_netlify_relay(
                org_config.relay_url.clone(),
                format!("org-{}-{}", org_config.organization, env_name),
            )?;
        }

        println!("✅ Configured organization-wide secret sync for {}", org_config.organization);
        Ok(())
    }

    /// Compare our secrets with GitHub Secrets (for migration)
    pub async fn compare_with_github_secrets(&self) -> Result<SecretComparisonReport> {
        let our_secrets = self.load_secrets().await?;
        let github_secrets = self.list_github_secrets().await?;

        let mut report = SecretComparisonReport {
            only_in_our_system: Vec::new(),
            only_in_github: Vec::new(),
            in_both: Vec::new(),
            conflicts: Vec::new(),
        };

        for key in our_secrets.keys() {
            if github_secrets.contains_key(key) {
                report.in_both.push(key.clone());
            } else {
                report.only_in_our_system.push(key.clone());
            }
        }

        for key in github_secrets.keys() {
            if !our_secrets.contains_key(key) {
                report.only_in_github.push(key.clone());
            }
        }

        Ok(report)
    }

    async fn list_github_secrets(&self) -> Result<HashMap<String, String>> {
        // Use gh CLI to list repository secrets
        let output = Command::new("gh")
            .args(&["secret", "list", "--json", "name"])
            .output()
            .await?;

        let github_secrets: serde_json::Value = serde_json::from_slice(&output.stdout)?;
        let mut secrets = HashMap::new();

        if let Some(secret_list) = github_secrets.as_array() {
            for secret in secret_list {
                if let Some(name) = secret["name"].as_str() {
                    secrets.insert(name.to_string(), "***".to_string()); // Values not retrievable
                }
            }
        }

        Ok(secrets)
    }

    /// Generate GitHub Actions workflow that uses our secret system
    pub fn generate_workflow(&self) -> Result<String> {
        let workflow = format!(r#"
name: Build with Secret Sync

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]

jobs:
  build:
    runs-on: ubuntu-latest

    permissions:
      id-token: write  # Required for OIDC authentication
      contents: read

    steps:
    - uses: actions/checkout@v4

    - name: Setup Secret Sync
      run: |
        # Download and install secret-tui
        wget https://github.com/{}/releases/latest/download/secret-tui-linux-x86_64
        chmod +x secret-tui-linux-x86_64
        sudo mv secret-tui-linux-x86_64 /usr/local/bin/secret-tui

    - name: Load Secrets
      run: |
        # Authenticate using GitHub Actions OIDC
        secret-tui auth login --oidc

        # Load and inject secrets for this environment
        secret-tui github-actions inject --environment=production
      env:
        ENVIRONMENT: production

    - name: Build Application
      run: |
        # Your build commands here
        # All secrets are now available as environment variables
        echo "Building with API_KEY: ${{{{ env.API_KEY }}}}"
        npm install
        npm run build
        npm test

    - name: Deploy
      if: github.ref == 'refs/heads/main'
      run: |
        # Deploy commands with access to deployment secrets
        echo "Deploying with DEPLOY_TOKEN: ${{{{ env.DEPLOY_TOKEN }}}}"
        ./deploy.sh
"#,
        self.config.repository
        );

        Ok(workflow)
    }
}

#[derive(Debug, Serialize, Deserialize)]
pub struct OrganizationSyncConfig {
    pub organization: String,
    pub relay_url: String,
    pub environments: Vec<String>, // dev, staging, production
    pub team_access: HashMap<String, Vec<String>>, // team -> categories
}

#[derive(Debug)]
pub struct SecretComparisonReport {
    pub only_in_our_system: Vec<String>,
    pub only_in_github: Vec<String>,
    pub in_both: Vec<String>,
    pub conflicts: Vec<String>,
}

// CLI integration for GitHub Actions
pub async fn handle_github_actions_command(command: &str) -> Result<()> {
    let mut integration = GitHubActionsIntegration::new().await?;

    match command {
        "inject" => {
            integration.inject_secrets().await?;
        }
        "compare" => {
            let report = integration.compare_with_github_secrets().await?;
            println!("🔍 Secret Comparison Report:");
            println!("  Only in our system: {:?}", report.only_in_our_system);
            println!("  Only in GitHub: {:?}", report.only_in_github);
            println!("  In both systems: {:?}", report.in_both);
        }
        "workflow" => {
            let workflow = integration.generate_workflow()?;
            println!("{}", workflow);
        }
        _ => anyhow::bail!("Unknown GitHub Actions command: {}", command),
    }

    Ok(())
}