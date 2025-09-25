use clap::{Parser, Subcommand};

#[derive(Parser)]
#[command(name = "secret-tui")]
#[command(about = "Terminal UI for managing SOPS-encrypted secrets with OAuth authentication")]
pub struct Cli {
    #[command(subcommand)]
    pub command: Option<Commands>,
}

#[derive(Subcommand)]
pub enum Commands {
    /// OAuth authentication management (like gh auth)
    Auth {
        #[command(subcommand)]
        auth_command: AuthCommands,
    },
    /// GitHub Actions integration (better than gh secret)
    #[command(name = "github-actions")]
    GitHubActions {
        #[command(subcommand)]
        gh_command: GitHubActionsCommands,
    },
    /// Run the interactive TUI (default)
    Tui,
}

#[derive(Subcommand)]
pub enum AuthCommands {
    /// Authenticate with OAuth provider (like gh auth login)
    Login {
        /// OAuth provider to use
        #[arg(short, long, default_value = "github")]
        provider: String,
    },
    /// Show authentication status
    Status,
    /// Log out and remove stored credentials
    Logout,
    /// Refresh authentication token
    Refresh,
}

#[derive(Subcommand)]
pub enum GitHubActionsCommands {
    /// Inject secrets into GitHub Actions environment
    Inject {
        /// Environment name (development, staging, production)
        #[arg(short, long, default_value = "production")]
        environment: String,
        /// Secret categories to inject
        #[arg(short, long)]
        categories: Option<Vec<String>>,
    },
    /// Compare our secrets with GitHub Secrets
    Compare {
        /// Repository to compare with (defaults to current)
        #[arg(short, long)]
        repository: Option<String>,
    },
    /// Generate GitHub Actions workflow
    Workflow {
        /// Output workflow file
        #[arg(short, long, default_value = ".github/workflows/secret-sync.yml")]
        output: String,
    },
    /// Setup organization-wide secret sync
    Setup {
        /// Organization name
        #[arg(short, long)]
        organization: String,
        /// Serverless relay URL
        #[arg(short, long)]
        relay_url: String,
        /// Environments to configure
        #[arg(short, long, default_values_t = ["development".to_string(), "staging".to_string(), "production".to_string()])]
        environments: Vec<String>,
    },
    /// Migrate from GitHub Secrets to our system
    Migrate {
        /// Repository to migrate from
        #[arg(short, long)]
        repository: Option<String>,
        /// Dry run (don't actually migrate)
        #[arg(long)]
        dry_run: bool,
    },
}