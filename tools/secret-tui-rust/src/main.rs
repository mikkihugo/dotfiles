use anyhow::{Context, Result};
use clap::Command;
use crossterm::{
    event::{self, DisableMouseCapture, EnableMouseCapture, Event, KeyCode},
    execute,
    terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen},
};
use ratatui::{
    backend::{Backend, CrosstermBackend},
    layout::{Constraint, Direction, Layout, Rect},
    style::{Color, Modifier, Style},
    text::{Line, Span},
    widgets::{Block, Borders, List, ListItem, ListState, Paragraph, Clear},
    Frame, Terminal,
};
use std::{
    collections::HashMap,
    fs,
    io,
    path::{Path, PathBuf},
    process::Command as ProcessCommand,
};

mod auth;
mod cli;
mod github_actions;
mod sync;

use auth::{SecretAuth, AuthProvider};
use cli::{Cli, Commands, AuthCommands, GitHubActionsCommands};
use github_actions::{GitHubActionsIntegration, OrganizationSyncConfig};
use sync::{SecretSync, SyncMethod, SyncResult};
use clap::Parser;

#[derive(Debug, Clone)]
struct SecretCategory {
    name: String,
    description: String,
    color: Color,
    file_path: PathBuf,
}

#[derive(Debug, Clone)]
struct SecretEntry {
    key: String,
    description: String,
    category: String,
    encrypted: bool,
}

#[derive(Debug, Clone, PartialEq)]
enum AppMode {
    MainMenu,
    CategoryList,
    SecretList,
    SecretEdit,
    StatusView,
    MigrationView,
    SyncMenu,
    SyncSetup,
    SyncStatus,
    SyncConflicts,
}

struct App {
    mode: AppMode,
    categories: Vec<SecretCategory>,
    secrets: Vec<SecretEntry>,
    selected_category: Option<usize>,
    selected_secret: Option<usize>,
    menu_state: ListState,
    category_state: ListState,
    secret_state: ListState,
    sync_menu_state: ListState,
    dotfiles_root: PathBuf,
    message: Option<String>,
    edit_input: String,
    edit_key: String,
    secret_sync: Option<SecretSync>,
    sync_result: Option<SyncResult>,
}

impl App {
    fn new() -> Result<Self> {
        let dotfiles_root = dirs::home_dir()
            .context("Cannot find home directory")?
            .join(".dotfiles");

        let categories = vec![
            SecretCategory {
                name: "AI Services".to_string(),
                description: "AI/Language Model providers".to_string(),
                color: Color::Blue,
                file_path: dotfiles_root.join("secrets/ai.yaml"),
            },
            SecretCategory {
                name: "Infrastructure".to_string(),
                description: "Database and infrastructure secrets".to_string(),
                color: Color::Cyan,
                file_path: dotfiles_root.join("secrets/infrastructure.yaml"),
            },
            SecretCategory {
                name: "Cloud Services".to_string(),
                description: "Cloud providers and CDN".to_string(),
                color: Color::Green,
                file_path: dotfiles_root.join("secrets/cloud.yaml"),
            },
            SecretCategory {
                name: "Development".to_string(),
                description: "Development tools and CI/CD".to_string(),
                color: Color::Magenta,
                file_path: dotfiles_root.join("secrets/dev.yaml"),
            },
            SecretCategory {
                name: "Authentication".to_string(),
                description: "Auth keys and security tokens".to_string(),
                color: Color::Red,
                file_path: dotfiles_root.join("secrets/auth.yaml"),
            },
        ];

        // Initialize sync system
        let secret_sync = match SecretSync::new(dotfiles_root.clone()) {
            Ok(sync) => Some(sync),
            Err(_) => None, // Sync unavailable, but app can still work
        };

        let mut app = Self {
            mode: AppMode::MainMenu,
            categories,
            secrets: Vec::new(),
            selected_category: None,
            selected_secret: None,
            menu_state: ListState::default(),
            category_state: ListState::default(),
            secret_state: ListState::default(),
            sync_menu_state: ListState::default(),
            dotfiles_root,
            message: None,
            edit_input: String::new(),
            edit_key: String::new(),
            secret_sync,
            sync_result: None,
        };

        app.menu_state.select(Some(0));
        Ok(app)
    }

    fn load_secrets_for_category(&mut self, category_index: usize) -> Result<()> {
        self.secrets.clear();

        if let Some(category) = self.categories.get(category_index) {
            if category.file_path.exists() {
                // Try to decrypt and parse SOPS file
                match self.decrypt_sops_file(&category.file_path) {
                    Ok(content) => {
                        if let Ok(data) = serde_yaml::from_str::<HashMap<String, String>>(&content) {
                            for (key, _value) in data {
                                self.secrets.push(SecretEntry {
                                    key: key.clone(),
                                    description: format!("Encrypted secret: {}", key),
                                    category: category.name.clone(),
                                    encrypted: true,
                                });
                            }
                        }
                    }
                    Err(_) => {
                        self.message = Some("Failed to decrypt SOPS file".to_string());
                    }
                }
            }
        }

        if !self.secrets.is_empty() {
            self.secret_state.select(Some(0));
        }

        Ok(())
    }

    fn decrypt_sops_file(&self, file_path: &Path) -> Result<String> {
        let sops_key_file = dirs::home_dir()
            .context("Cannot find home directory")?
            .join(".config/sops/age/keys.txt");

        let output = ProcessCommand::new("sops")
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

    fn get_status_info(&self) -> Vec<String> {
        let mut status = Vec::new();

        for category in &self.categories {
            let exists = category.file_path.exists();
            let status_icon = if exists { "✅" } else { "❌" };

            status.push(format!(
                "{} {} - {}",
                status_icon,
                category.name,
                category.description
            ));

            if exists {
                if let Ok(metadata) = fs::metadata(&category.file_path) {
                    status.push(format!(
                        "   📁 {} ({} bytes)",
                        category.file_path.display(),
                        metadata.len()
                    ));
                }

                // Test decryption
                match self.decrypt_sops_file(&category.file_path) {
                    Ok(_) => status.push("   🔓 Decryption: OK".to_string()),
                    Err(_) => status.push("   🔒 Decryption: Failed".to_string()),
                }
            }

            status.push(String::new());
        }

        status
    }

    fn migrate_from_shared(&self) -> Result<()> {
        let shared_file = self.dotfiles_root.join("secrets/shared.yaml");

        if !shared_file.exists() {
            anyhow::bail!("shared.yaml file not found");
        }

        let content = self.decrypt_sops_file(&shared_file)?;
        let data: HashMap<String, String> = serde_yaml::from_str(&content)?;

        // Categorization logic based on key prefixes/names
        let mut categorized: HashMap<&str, HashMap<String, String>> = HashMap::new();
        categorized.insert("ai", HashMap::new());
        categorized.insert("infrastructure", HashMap::new());
        categorized.insert("cloud", HashMap::new());
        categorized.insert("dev", HashMap::new());
        categorized.insert("auth", HashMap::new());

        for (key, value) in data {
            let category = if key.contains("CLAUDE") || key.contains("OPENAI") || key.contains("ANTHROPIC")
                || key.contains("GEMINI") || key.contains("MISTRAL") || key.contains("GROQ") {
                "ai"
            } else if key.contains("DATABASE") || key.contains("VAULT") || key.contains("JWT") {
                "infrastructure"
            } else if key.contains("CLOUDFLARE") || key.contains("VULTR") || key.contains("AWS") {
                "cloud"
            } else if key.contains("GITHUB") || key.contains("GIT") {
                "dev"
            } else {
                "auth"
            };

            if let Some(cat_data) = categorized.get_mut(category) {
                cat_data.insert(key, value);
            }
        }

        // Create categorized files
        for (cat_name, cat_data) in categorized {
            if !cat_data.is_empty() {
                let file_path = self.dotfiles_root.join(format!("secrets/{}.yaml", cat_name));
                let yaml_content = serde_yaml::to_string(&cat_data)?;

                // Write temporary file
                let temp_file = file_path.with_extension("tmp");
                fs::write(&temp_file, yaml_content)?;

                // Encrypt with SOPS
                let sops_key_file = dirs::home_dir()
                    .context("Cannot find home directory")?
                    .join(".config/sops/age/keys.txt");

                let status = ProcessCommand::new("sops")
                    .args(["-e", "-i", &temp_file.to_string_lossy()])
                    .env("SOPS_AGE_KEY_FILE", &sops_key_file)
                    .status()?;

                if status.success() {
                    fs::rename(&temp_file, &file_path)?;
                } else {
                    fs::remove_file(&temp_file)?;
                    anyhow::bail!("Failed to encrypt {} file", cat_name);
                }
            }
        }

        Ok(())
    }
}

fn ui(f: &mut Frame, app: &mut App) {
    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .margin(1)
        .constraints([Constraint::Length(3), Constraint::Min(0), Constraint::Length(3)])
        .split(f.area());

    // Header
    let header = Paragraph::new("🔐 Secret Manager - SOPS Integration")
        .style(Style::default().fg(Color::Cyan).add_modifier(Modifier::BOLD))
        .block(Block::default().borders(Borders::ALL));
    f.render_widget(header, chunks[0]);

    // Main content
    match app.mode {
        AppMode::MainMenu => render_main_menu(f, app, chunks[1]),
        AppMode::CategoryList => render_category_list(f, app, chunks[1]),
        AppMode::SecretList => render_secret_list(f, app, chunks[1]),
        AppMode::StatusView => render_status_view(f, app, chunks[1]),
        AppMode::MigrationView => render_migration_view(f, app, chunks[1]),
        AppMode::SecretEdit => render_secret_edit(f, app, chunks[1]),
        AppMode::SyncMenu => render_sync_menu(f, app, chunks[1]),
        AppMode::SyncSetup => render_sync_setup(f, app, chunks[1]),
        AppMode::SyncStatus => render_sync_status(f, app, chunks[1]),
        AppMode::SyncConflicts => render_sync_conflicts(f, app, chunks[1]),
    }

    // Footer
    let footer_text = match app.mode {
        AppMode::MainMenu => "↑↓: Navigate | Enter: Select | q: Quit",
        AppMode::CategoryList => "↑↓: Navigate | Enter: View Secrets | Esc: Back | q: Quit",
        AppMode::SecretList => "↑↓: Navigate | Enter: Edit | Esc: Back | q: Quit",
        AppMode::StatusView => "Esc: Back | r: Refresh | q: Quit",
        AppMode::MigrationView => "Enter: Start Migration | Esc: Back | q: Quit",
        AppMode::SecretEdit => "Esc: Cancel | Enter: Save | q: Quit",
        AppMode::SyncMenu => "↑↓: Navigate | Enter: Select | Esc: Back | q: Quit",
        AppMode::SyncSetup => "s: Start Setup | Esc: Back | q: Quit",
        AppMode::SyncStatus => "Esc: Back | q: Quit",
        AppMode::SyncConflicts => "Esc: Back | q: Quit",
    };

    let footer = Paragraph::new(footer_text)
        .style(Style::default().fg(Color::Gray))
        .block(Block::default().borders(Borders::ALL));
    f.render_widget(footer, chunks[2]);

    // Message overlay
    if let Some(ref message) = app.message {
        let popup_area = centered_rect(60, 20, f.area());
        f.render_widget(Clear, popup_area);
        let popup = Paragraph::new(message.clone())
            .style(Style::default().fg(Color::Yellow))
            .block(Block::default().title("Message").borders(Borders::ALL));
        f.render_widget(popup, popup_area);
    }
}

fn render_main_menu(f: &mut Frame, app: &mut App, area: Rect) {
    let sync_status = if app.secret_sync.is_some() { "🔄" } else { "⚠️" };

    let items = vec![
        ListItem::new("📋 View Secret Categories"),
        ListItem::new("📊 Show Status"),
        ListItem::new(format!("{} Secret Sync", sync_status)),
        ListItem::new("🔄 Migrate from shared.yaml"),
        ListItem::new("❌ Exit"),
    ];

    let list = List::new(items)
        .block(Block::default().title("Main Menu").borders(Borders::ALL))
        .style(Style::default().fg(Color::White))
        .highlight_style(Style::default().add_modifier(Modifier::REVERSED))
        .highlight_symbol(">> ");

    f.render_stateful_widget(list, area, &mut app.menu_state);
}

fn render_category_list(f: &mut Frame, app: &mut App, area: Rect) {
    let items: Vec<ListItem> = app
        .categories
        .iter()
        .map(|cat| {
            let status = if cat.file_path.exists() { "✅" } else { "❌" };
            ListItem::new(format!("{} {} - {}", status, cat.name, cat.description))
                .style(Style::default().fg(cat.color))
        })
        .collect();

    let list = List::new(items)
        .block(Block::default().title("Secret Categories").borders(Borders::ALL))
        .style(Style::default().fg(Color::White))
        .highlight_style(Style::default().add_modifier(Modifier::REVERSED))
        .highlight_symbol(">> ");

    f.render_stateful_widget(list, area, &mut app.category_state);
}

fn render_secret_list(f: &mut Frame, app: &mut App, area: Rect) {
    let title = if let Some(cat_idx) = app.selected_category {
        if let Some(category) = app.categories.get(cat_idx) {
            format!("Secrets - {}", category.name)
        } else {
            "Secrets".to_string()
        }
    } else {
        "Secrets".to_string()
    };

    let items: Vec<ListItem> = app
        .secrets
        .iter()
        .map(|secret| {
            let icon = if secret.encrypted { "🔒" } else { "📄" };
            ListItem::new(format!("{} {} - {}", icon, secret.key, secret.description))
        })
        .collect();

    let list = List::new(items)
        .block(Block::default().title(title.as_str()).borders(Borders::ALL))
        .style(Style::default().fg(Color::White))
        .highlight_style(Style::default().add_modifier(Modifier::REVERSED))
        .highlight_symbol(">> ");

    f.render_stateful_widget(list, area, &mut app.secret_state);
}

fn render_status_view(f: &mut Frame, app: &mut App, area: Rect) {
    let status_info = app.get_status_info();
    let text: Vec<Line> = status_info
        .iter()
        .map(|line| {
            if line.contains("✅") {
                Line::from(Span::styled(line, Style::default().fg(Color::Green)))
            } else if line.contains("❌") {
                Line::from(Span::styled(line, Style::default().fg(Color::Red)))
            } else if line.contains("🔓") {
                Line::from(Span::styled(line, Style::default().fg(Color::Green)))
            } else if line.contains("🔒") {
                Line::from(Span::styled(line, Style::default().fg(Color::Red)))
            } else {
                Line::from(Span::styled(line, Style::default().fg(Color::Gray)))
            }
        })
        .collect();

    let paragraph = Paragraph::new(text)
        .block(Block::default().title("SOPS Status").borders(Borders::ALL))
        .style(Style::default().fg(Color::White));

    f.render_widget(paragraph, area);
}

fn render_migration_view(f: &mut Frame, _app: &mut App, area: Rect) {
    let text = vec![
        Line::from("🔄 Migration from shared.yaml to categorized structure"),
        Line::from(""),
        Line::from("This will:"),
        Line::from("• Read secrets from secrets/shared.yaml"),
        Line::from("• Categorize them by type (AI, Infrastructure, Cloud, etc.)"),
        Line::from("• Create separate encrypted SOPS files"),
        Line::from("• Preserve all encryption"),
        Line::from(""),
        Line::from(Span::styled(
            "⚠️  This is a one-way migration. Make sure you have backups!",
            Style::default().fg(Color::Yellow).add_modifier(Modifier::BOLD)
        )),
        Line::from(""),
        Line::from("Press Enter to continue or Esc to cancel"),
    ];

    let paragraph = Paragraph::new(text)
        .block(Block::default().title("Migration").borders(Borders::ALL))
        .style(Style::default().fg(Color::White));

    f.render_widget(paragraph, area);
}

fn render_secret_edit(f: &mut Frame, app: &mut App, area: Rect) {
    let text = format!("Editing: {}\nValue: {}", app.edit_key, app.edit_input);

    let paragraph = Paragraph::new(text)
        .block(Block::default().title("Edit Secret").borders(Borders::ALL))
        .style(Style::default().fg(Color::White));

    f.render_widget(paragraph, area);
}

fn render_sync_menu(f: &mut Frame, app: &mut App, area: Rect) {
    let items = if app.secret_sync.is_some() {
        vec![
            ListItem::new("🔄 Sync Now"),
            ListItem::new("📊 Sync Status"),
            ListItem::new("⚙️  Sync Setup"),
            ListItem::new("⚔️  Resolve Conflicts"),
            ListItem::new("🏠 Back to Main"),
        ]
    } else {
        vec![
            ListItem::new("⚙️  Setup Sync"),
            ListItem::new("🏠 Back to Main"),
        ]
    };

    let list = List::new(items)
        .block(Block::default().title("Secret Synchronization").borders(Borders::ALL))
        .style(Style::default().fg(Color::White))
        .highlight_style(Style::default().add_modifier(Modifier::REVERSED))
        .highlight_symbol(">> ");

    f.render_stateful_widget(list, area, &mut app.sync_menu_state);
}

fn render_sync_setup(f: &mut Frame, app: &mut App, area: Rect) {
    let sync_methods = if let Some(ref sync) = app.secret_sync {
        let config = sync.get_config();
        format!("Current sync methods:\n\n{:#?}\n\nDevice: {}\nLast sync: {:?}",
            config.sync_methods, config.device_name, config.last_sync)
    } else {
        "Sync not initialized".to_string()
    };

    let text = vec![
        Line::from("🔄 Secret Sync Setup"),
        Line::from(""),
        Line::from("Available sync methods:"),
        Line::from("• 🌐 Local Network P2P - Direct device-to-device sync"),
        Line::from("• 🔄 Relay Server - Via secure relay server (self-hosted)"),
        Line::from("• ☁️  Serverless Relay - Via free cloud providers:"),
        Line::from("  └ Vercel (100GB/month free)"),
        Line::from("  └ Netlify (125k calls/month free)"),
        Line::from("  └ Cloudflare Workers (100k calls/day free)"),
        Line::from("• 📁 File Drop - Via encrypted file sharing (Syncthing/Dropbox)"),
        Line::from("• 🌐 Webhook - Via encrypted API endpoints"),
        Line::from(""),
        Line::from("Features:"),
        Line::from("• 🔒 ChaCha20-Poly1305 encryption"),
        Line::from("• 🔐 SHA256 checksums for integrity"),
        Line::from("• ⚔️  Conflict detection and resolution"),
        Line::from("• 📱 QR code pairing"),
        Line::from("• 🆓 Free serverless deployment scripts included!"),
        Line::from(""),
        Line::from(sync_methods),
        Line::from(""),
        Line::from("Press 's' to start setup, Esc to go back"),
    ];

    let paragraph = Paragraph::new(text)
        .block(Block::default().title("Sync Setup").borders(Borders::ALL))
        .style(Style::default().fg(Color::White));

    f.render_widget(paragraph, area);
}

fn render_sync_status(f: &mut Frame, app: &mut App, area: Rect) {
    let status_text = if let Some(ref sync_result) = app.sync_result {
        format!(
            "Last Sync Result:\n\n✅ Synced categories: {}\n⚔️  Conflicts: {}\n❌ Errors: {}\n\n{}",
            sync_result.synced_categories.len(),
            sync_result.conflicts.len(),
            sync_result.errors.len(),
            sync_result.errors.join("\n")
        )
    } else {
        "No sync performed yet".to_string()
    };

    let paragraph = Paragraph::new(status_text)
        .block(Block::default().title("Sync Status").borders(Borders::ALL))
        .style(Style::default().fg(Color::White));

    f.render_widget(paragraph, area);
}

fn render_sync_conflicts(f: &mut Frame, app: &mut App, area: Rect) {
    let conflicts_text = if let Some(ref sync_result) = app.sync_result {
        if sync_result.conflicts.is_empty() {
            "No conflicts detected! 🎉".to_string()
        } else {
            let mut text = String::new();
            text.push_str("Sync Conflicts Detected:\n\n");
            for (i, conflict) in sync_result.conflicts.iter().enumerate() {
                text.push_str(&format!(
                    "{}. {}/{}\n   Local:  {}\n   Remote: {} (from {})\n\n",
                    i + 1, conflict.category, conflict.key,
                    conflict.local_value, conflict.remote_value, conflict.remote_device
                ));
            }
            text
        }
    } else {
        "No sync conflicts to display".to_string()
    };

    let paragraph = Paragraph::new(conflicts_text)
        .block(Block::default().title("Sync Conflicts").borders(Borders::ALL))
        .style(Style::default().fg(Color::White));

    f.render_widget(paragraph, area);
}

fn centered_rect(percent_x: u16, percent_y: u16, r: Rect) -> Rect {
    let popup_layout = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Percentage((100 - percent_y) / 2),
            Constraint::Percentage(percent_y),
            Constraint::Percentage((100 - percent_y) / 2),
        ])
        .split(r);

    Layout::default()
        .direction(Direction::Horizontal)
        .constraints([
            Constraint::Percentage((100 - percent_x) / 2),
            Constraint::Percentage(percent_x),
            Constraint::Percentage((100 - percent_x) / 2),
        ])
        .split(popup_layout[1])[1]
}

fn run_app<B: Backend>(terminal: &mut Terminal<B>, mut app: App) -> Result<()> {
    loop {
        terminal.draw(|f| ui(f, &mut app))?;

        if let Event::Key(key) = event::read()? {
            match app.mode {
                AppMode::MainMenu => match key.code {
                    KeyCode::Char('q') => return Ok(()),
                    KeyCode::Down => {
                        let i = match app.menu_state.selected() {
                            Some(i) => (i + 1) % 5,
                            None => 0,
                        };
                        app.menu_state.select(Some(i));
                    }
                    KeyCode::Up => {
                        let i = match app.menu_state.selected() {
                            Some(i) => (i + 5 - 1) % 5,
                            None => 0,
                        };
                        app.menu_state.select(Some(i));
                    }
                    KeyCode::Enter => {
                        if let Some(selected) = app.menu_state.selected() {
                            match selected {
                                0 => {
                                    app.mode = AppMode::CategoryList;
                                    app.category_state.select(Some(0));
                                }
                                1 => app.mode = AppMode::StatusView,
                                2 => {
                                    app.mode = AppMode::SyncMenu;
                                    app.sync_menu_state.select(Some(0));
                                }
                                3 => app.mode = AppMode::MigrationView,
                                4 => return Ok(()),
                                _ => {}
                            }
                        }
                    }
                    _ => {}
                },
                AppMode::CategoryList => match key.code {
                    KeyCode::Char('q') => return Ok(()),
                    KeyCode::Esc => {
                        app.mode = AppMode::MainMenu;
                        app.menu_state.select(Some(0));
                    }
                    KeyCode::Down => {
                        let i = match app.category_state.selected() {
                            Some(i) => (i + 1) % app.categories.len(),
                            None => 0,
                        };
                        app.category_state.select(Some(i));
                    }
                    KeyCode::Up => {
                        let i = match app.category_state.selected() {
                            Some(i) => (i + app.categories.len() - 1) % app.categories.len(),
                            None => 0,
                        };
                        app.category_state.select(Some(i));
                    }
                    KeyCode::Enter => {
                        if let Some(selected) = app.category_state.selected() {
                            app.selected_category = Some(selected);
                            if let Err(e) = app.load_secrets_for_category(selected) {
                                app.message = Some(format!("Error loading secrets: {}", e));
                            } else {
                                app.mode = AppMode::SecretList;
                            }
                        }
                    }
                    _ => {}
                },
                AppMode::SecretList => match key.code {
                    KeyCode::Char('q') => return Ok(()),
                    KeyCode::Esc => {
                        app.mode = AppMode::CategoryList;
                    }
                    KeyCode::Down => {
                        if !app.secrets.is_empty() {
                            let i = match app.secret_state.selected() {
                                Some(i) => (i + 1) % app.secrets.len(),
                                None => 0,
                            };
                            app.secret_state.select(Some(i));
                        }
                    }
                    KeyCode::Up => {
                        if !app.secrets.is_empty() {
                            let i = match app.secret_state.selected() {
                                Some(i) => (i + app.secrets.len() - 1) % app.secrets.len(),
                                None => 0,
                            };
                            app.secret_state.select(Some(i));
                        }
                    }
                    KeyCode::Enter => {
                        if let Some(selected) = app.secret_state.selected() {
                            if let Some(secret) = app.secrets.get(selected) {
                                app.edit_key = secret.key.clone();
                                app.edit_input = String::new();
                                app.mode = AppMode::SecretEdit;
                            }
                        }
                    }
                    _ => {}
                },
                AppMode::StatusView => match key.code {
                    KeyCode::Char('q') => return Ok(()),
                    KeyCode::Esc => {
                        app.mode = AppMode::MainMenu;
                        app.menu_state.select(Some(1));
                    }
                    KeyCode::Char('r') => {
                        // Refresh status - could reload file info here
                    }
                    _ => {}
                },
                AppMode::MigrationView => match key.code {
                    KeyCode::Char('q') => return Ok(()),
                    KeyCode::Esc => {
                        app.mode = AppMode::MainMenu;
                        app.menu_state.select(Some(2));
                    }
                    KeyCode::Enter => {
                        match app.migrate_from_shared() {
                            Ok(_) => {
                                app.message = Some("Migration completed successfully!".to_string());
                                app.mode = AppMode::MainMenu;
                                app.menu_state.select(Some(0));
                            }
                            Err(e) => {
                                app.message = Some(format!("Migration failed: {}", e));
                            }
                        }
                    }
                    _ => {}
                },
                AppMode::SecretEdit => match key.code {
                    KeyCode::Char('q') | KeyCode::Esc => {
                        app.mode = AppMode::SecretList;
                    }
                    KeyCode::Char(c) => {
                        app.edit_input.push(c);
                    }
                    KeyCode::Backspace => {
                        app.edit_input.pop();
                    }
                    KeyCode::Enter => {
                        // Save secret logic would go here
                        app.message = Some("Secret save not implemented yet".to_string());
                        app.mode = AppMode::SecretList;
                    }
                    _ => {}
                },
                AppMode::SyncMenu => match key.code {
                    KeyCode::Char('q') => return Ok(()),
                    KeyCode::Esc => {
                        app.mode = AppMode::MainMenu;
                        app.menu_state.select(Some(2));
                    }
                    KeyCode::Down => {
                        let max_items = if app.secret_sync.is_some() { 5 } else { 2 };
                        let i = match app.sync_menu_state.selected() {
                            Some(i) => (i + 1) % max_items,
                            None => 0,
                        };
                        app.sync_menu_state.select(Some(i));
                    }
                    KeyCode::Up => {
                        let max_items = if app.secret_sync.is_some() { 5 } else { 2 };
                        let i = match app.sync_menu_state.selected() {
                            Some(i) => (i + max_items - 1) % max_items,
                            None => 0,
                        };
                        app.sync_menu_state.select(Some(i));
                    }
                    KeyCode::Enter => {
                        if let Some(selected) = app.sync_menu_state.selected() {
                            if app.secret_sync.is_some() {
                                match selected {
                                    0 => {
                                        // Sync Now - TODO: Implement async sync
                                        app.message = Some("Sync functionality coming soon!".to_string());
                                    }
                                    1 => app.mode = AppMode::SyncStatus,
                                    2 => app.mode = AppMode::SyncSetup,
                                    3 => app.mode = AppMode::SyncConflicts,
                                    4 => {
                                        app.mode = AppMode::MainMenu;
                                        app.menu_state.select(Some(2));
                                    }
                                    _ => {}
                                }
                            } else {
                                match selected {
                                    0 => app.mode = AppMode::SyncSetup,
                                    1 => {
                                        app.mode = AppMode::MainMenu;
                                        app.menu_state.select(Some(2));
                                    }
                                    _ => {}
                                }
                            }
                        }
                    }
                    _ => {}
                },
                AppMode::SyncSetup => match key.code {
                    KeyCode::Char('q') => return Ok(()),
                    KeyCode::Esc => {
                        app.mode = AppMode::SyncMenu;
                        app.sync_menu_state.select(Some(2));
                    }
                    KeyCode::Char('s') => {
                        app.message = Some("Sync setup functionality coming soon!".to_string());
                    }
                    _ => {}
                },
                AppMode::SyncStatus => match key.code {
                    KeyCode::Char('q') => return Ok(()),
                    KeyCode::Esc => {
                        app.mode = AppMode::SyncMenu;
                        app.sync_menu_state.select(Some(1));
                    }
                    _ => {}
                },
                AppMode::SyncConflicts => match key.code {
                    KeyCode::Char('q') => return Ok(()),
                    KeyCode::Esc => {
                        app.mode = AppMode::SyncMenu;
                        app.sync_menu_state.select(Some(3));
                    }
                    _ => {}
                },
            }

            // Clear message on any key press
            if key.code != KeyCode::Enter && app.message.is_some() {
                app.message = None;
            }
        }
    }
}

#[tokio::main]
async fn main() -> Result<()> {
    let cli = Cli::parse();

    let dotfiles_root = dirs::home_dir()
        .context("Could not find home directory")?
        .join(".dotfiles");

    match &cli.command {
        Some(Commands::Auth { auth_command }) => {
            handle_auth_command(auth_command, dotfiles_root).await?;
        }
        Some(Commands::GitHubActions { gh_command }) => {
            handle_github_actions_command(gh_command).await?;
        }
        Some(Commands::Tui) | None => {
            run_tui(dotfiles_root).await?;
        }
    }

    Ok(())
}

async fn handle_github_actions_command(gh_command: &GitHubActionsCommands) -> Result<()> {
    match gh_command {
        GitHubActionsCommands::Inject { environment, categories } => {
            let mut integration = GitHubActionsIntegration::new().await?;

            // Override environment if specified
            // TODO: Update config with specified environment

            integration.inject_secrets().await?;
        }
        GitHubActionsCommands::Compare { repository } => {
            let integration = GitHubActionsIntegration::new().await?;
            let report = integration.compare_with_github_secrets().await?;

            println!("🔍 Secret Comparison Report:");
            println!("  📈 Only in our system ({} secrets):", report.only_in_our_system.len());
            for secret in &report.only_in_our_system {
                println!("    • {}", secret);
            }
            println!("  📉 Only in GitHub ({} secrets):", report.only_in_github.len());
            for secret in &report.only_in_github {
                println!("    • {}", secret);
            }
            println!("  🤝 In both systems ({} secrets):", report.in_both.len());
            for secret in &report.in_both {
                println!("    • {}", secret);
            }

            if !report.only_in_github.is_empty() {
                println!("\n💡 Consider migrating GitHub secrets with:");
                println!("   secret-tui github-actions migrate");
            }
        }
        GitHubActionsCommands::Workflow { output } => {
            let integration = GitHubActionsIntegration::new().await?;
            let workflow_content = integration.generate_workflow()?;

            // Ensure .github/workflows directory exists
            if let Some(parent) = std::path::Path::new(output).parent() {
                std::fs::create_dir_all(parent)?;
            }

            std::fs::write(output, workflow_content)?;
            println!("✅ Generated GitHub Actions workflow: {}", output);
            println!("💡 Commit this file to enable secret sync in CI/CD!");
        }
        GitHubActionsCommands::Setup { organization, relay_url, environments } => {
            let mut integration = GitHubActionsIntegration::new().await?;

            let org_config = OrganizationSyncConfig {
                organization: organization.clone(),
                relay_url: relay_url.clone(),
                environments: environments.clone(),
                team_access: std::collections::HashMap::new(), // TODO: Configure team access
            };

            integration.setup_organization_sync(org_config).await?;
            println!("✅ Organization secret sync configured for {}", organization);
            println!("🚀 Deploy your serverless relay to: {}", relay_url);
        }
        GitHubActionsCommands::Migrate { repository, dry_run } => {
            println!("🔄 GitHub Secrets migration ({})", if *dry_run { "DRY RUN" } else { "LIVE" });

            if *dry_run {
                println!("⚠️  This would migrate GitHub Secrets to our system");
                println!("   Run without --dry-run to perform actual migration");
            } else {
                // TODO: Implement actual migration logic
                println!("🚧 Migration implementation coming soon!");
                println!("   For now, use 'compare' command to see what needs migrating");
            }
        }
    }

    Ok(())
}

async fn handle_auth_command(auth_command: &AuthCommands, dotfiles_root: PathBuf) -> Result<()> {
    match auth_command {
        AuthCommands::Login { provider } => {
            let auth_provider = match provider.as_str() {
                "github" => AuthProvider::GitHub,
                "google" => AuthProvider::Google,
                "microsoft" => AuthProvider::Microsoft,
                _ => anyhow::bail!("Unsupported provider: {}. Supported: github, google, microsoft", provider),
            };

            let mut auth = SecretAuth::new(dotfiles_root, auth_provider)?;
            auth.login().await?;

            println!("🎉 Authentication successful!");
            println!("   You can now run 'secret-tui' to start syncing secrets.");
        }
        AuthCommands::Status => {
            // Try to load existing auth config
            if let Ok(auth) = SecretAuth::new(dotfiles_root, AuthProvider::GitHub) {
                println!("{}", auth.status());
            } else {
                println!("❌ No authentication found. Run 'secret-tui auth login'");
            }
        }
        AuthCommands::Logout => {
            if let Ok(mut auth) = SecretAuth::new(dotfiles_root, AuthProvider::GitHub) {
                auth.logout()?;
            } else {
                println!("ℹ️  No authentication to log out from");
            }
        }
        AuthCommands::Refresh => {
            if let Ok(mut auth) = SecretAuth::new(dotfiles_root, AuthProvider::GitHub) {
                if auth.refresh_token_if_needed().await? {
                    println!("✅ Token refreshed successfully");
                } else {
                    println!("⚠️  Token refresh failed. Please run 'secret-tui auth login' again");
                }
            } else {
                println!("❌ No authentication found. Run 'secret-tui auth login'");
            }
        }
    }
    Ok(())
}

async fn run_tui(dotfiles_root: PathBuf) -> Result<()> {
    // Setup terminal
    enable_raw_mode()?;
    let mut stdout = io::stdout();
    execute!(stdout, EnterAlternateScreen, EnableMouseCapture)?;
    let backend = CrosstermBackend::new(stdout);
    let mut terminal = Terminal::new(backend)?;

    // Create app and run
    let app = App::new()?;
    let res = run_app(&mut terminal, app);

    // Restore terminal
    disable_raw_mode()?;
    execute!(
        terminal.backend_mut(),
        LeaveAlternateScreen,
        DisableMouseCapture
    )?;
    terminal.show_cursor()?;

    if let Err(err) = res {
        println!("{err:?}");
    }

    Ok(())
}
