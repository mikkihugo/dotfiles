// Ultra-minimal guardian with built-in survival mechanism
// This is the simplest possible guardian that can survive and recover
// Compile: rustc -O minimal-guardian.rs -o shell-guardian

use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, exit};
use std::time::{SystemTime, UNIX_EPOCH};

// Survival locations - absolute minimum needed
const SURVIVAL_LOCATIONS: [&str; 3] = [
    ".local/bin/shell-guardian",
    ".dotfiles/.guardian-shell/shell-guardian.bin",
    ".config/.guardian"
];

// Simple crash detection
const LOG_FILE: &str = ".guardian.log";
const CRASH_THRESHOLD: u64 = 3;  // Number of crashes
const CRASH_TIME: u64 = 10;      // Within N seconds

fn main() {
    // Check for self-repair request
    let args: Vec<String> = env::args().collect();
    if args.len() > 1 && args[1] == "repair" {
        repair();
        return;
    }
    
    // Normal shell guardian operation
    if args.len() < 2 {
        eprintln!("Usage: shell-guardian <command> [args...]");
        exit(1);
    }
    
    // Get home directory and command
    let home = env::var("HOME").unwrap_or_else(|_| String::from("/tmp"));
    let log_path = Path::new(&home).join(LOG_FILE);
    let command = &args[1];
    let command_args = args[2..].to_vec();
    
    // Check for crash pattern
    if is_crash_pattern(&log_path, &home) {
        run_failsafe();
    } else {
        // Ensure survival (repair in background)
        ensure_survival(&home);
        
        // Log startup time
        log_startup(&log_path);
        
        // Run requested command
        let status = Command::new(command)
            .args(command_args)
            .status()
            .unwrap_or_else(|_| std::process::ExitStatus::from_raw(1));
        
        exit(status.code().unwrap_or(1));
    }
}

// Check if we're in a crash pattern
fn is_crash_pattern(log_path: &Path, home: &str) -> bool {
    // Current time
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs();
    
    // Try to read log file
    if let Ok(content) = fs::read_to_string(log_path) {
        let mut timestamps = Vec::new();
        
        // Parse timestamps from log
        for line in content.lines() {
            if let Ok(ts) = line.parse::<u64>() {
                timestamps.push(ts);
            }
        }
        
        // Count recent timestamps
        let mut recent_count = 0;
        for ts in &timestamps {
            if now - ts < CRASH_TIME {
                recent_count += 1;
                if recent_count >= CRASH_THRESHOLD as usize {
                    // Log crash detection
                    let _ = fs::write(log_path, format!("CRASH_{}", now));
                    return true;
                }
            }
        }
    }
    
    false
}

// Log startup time
fn log_startup(log_path: &Path) {
    // Current time
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs();
    
    // Try to read existing log
    let mut timestamps = Vec::new();
    if let Ok(content) = fs::read_to_string(log_path) {
        for line in content.lines() {
            if let Ok(ts) = line.parse::<u64>() {
                timestamps.push(ts);
            }
        }
    }
    
    // Add current timestamp
    timestamps.push(now);
    
    // Keep only last 10 timestamps
    if timestamps.len() > 10 {
        timestamps = timestamps[timestamps.len() - 10..].to_vec();
    }
    
    // Write back to log
    let _ = fs::write(log_path, timestamps.iter()
        .map(|ts| ts.to_string())
        .collect::<Vec<_>>()
        .join("\n"));
}

// Ensure survival by checking and repairing survival copies
fn ensure_survival(home: &str) {
    // Run repair in background to avoid blocking
    let self_path = env::current_exe().unwrap_or_else(|_| PathBuf::from("./shell-guardian"));
    let home_owned = home.to_string();
    
    // Spawn repair process in background
    let _ = Command::new(self_path)
        .arg("repair")
        .env("HOME", home_owned)
        .spawn();
}

// Self-repair function
fn repair() {
    let home = match env::var("HOME") {
        Ok(h) => h,
        Err(_) => return, // Can't do anything without HOME
    };
    
    // Get source binary path
    let self_path = match env::current_exe() {
        Ok(p) => p,
        Err(_) => return, // Can't get own path
    };
    
    // Get source content
    let self_content = match fs::read(&self_path) {
        Ok(c) => c,
        Err(_) => return, // Can't read own content
    };
    
    // Check and repair each survival location
    for location in SURVIVAL_LOCATIONS.iter() {
        let target_path = PathBuf::from(&home).join(location);
        
        // Skip if same as source
        if target_path == self_path {
            continue;
        }
        
        // Check if needs repair
        let needs_repair = match fs::metadata(&target_path) {
            Ok(meta) => {
                // Check size
                if meta.len() != self_content.len() as u64 {
                    true
                } else {
                    // Check content
                    match fs::read(&target_path) {
                        Ok(content) => content != self_content,
                        Err(_) => true
                    }
                }
            },
            Err(_) => true // Missing or can't access
        };
        
        // Repair if needed
        if needs_repair {
            // Create parent directory
            if let Some(parent) = target_path.parent() {
                let _ = fs::create_dir_all(parent);
            }
            
            // Copy file
            let _ = fs::write(&target_path, &self_content);
            
            // Set executable permission
            #[cfg(unix)]
            {
                use std::os::unix::fs::PermissionsExt;
                let mut perms = fs::metadata(&target_path).ok()
                    .and_then(|m| Some(m.permissions()))
                    .unwrap_or_else(|| fs::Permissions::from_mode(0o755));
                perms.set_mode(0o755);
                let _ = fs::set_permissions(&target_path, perms);
            }
        }
    }
}

// Run failsafe shell
fn run_failsafe() {
    eprintln!("\x1b[31m⚠️  Shell crash detected!\x1b[0m");
    eprintln!("\x1b[33m💡 Launching minimal environment\x1b[0m");
    
    // Run bash with minimal environment
    let status = Command::new("bash")
        .arg("--norc")
        .env("PS1", "\x1b[31m[FAILSAFE]\x1b[0m \\w\\$ ")
        .env("PATH", "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$HOME/.local/bin")
        .env("TERM", "xterm-256color")
        .env("SHELL_GUARDIAN_ACTIVE", "1")
        .status()
        .unwrap_or_else(|_| std::process::ExitStatus::from_raw(1));
    
    exit(status.code().unwrap_or(1));
}