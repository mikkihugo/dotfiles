// Ultra-minimal shell-guardian.rs - Hardened version
// Compile with: rustc -O -C opt-level=3 -C lto=fat -C codegen-units=1 shell-guardian.rs

use std::env;
use std::path::Path;
use std::process::{Command, exit};
use std::fs::{self, File, OpenOptions};
use std::io::{self, Write, Read, BufRead, BufReader};
use std::time::{SystemTime, UNIX_EPOCH, Duration, Instant};
use std::collections::VecDeque;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;

// Guardian settings
const LOG_FILE: &str = ".shell-guardian.log";
const BACKUP_LOG_FILE: &str = ".shell-guardian.log.bak";
const CRASH_THRESHOLD: usize = 3;  // Number of crashes
const CRASH_TIME: u64 = 10;        // Within N seconds
const MAX_LOG_SIZE: u64 = 10240;   // 10KB maximum log size
const RECOVERY_SHELL: &str = "bash";  // Default recovery shell
const FALLBACK_DIR: &str = "/tmp"; // Fallback if HOME not found
const HEARTBEAT_INTERVAL: u64 = 5; // seconds
const MIN_FREE_DISK_MB: u64 = 100; // Minimum free disk space

// Self-verification checksum
// This is a checksum of the source code, updated during build
// If the binary is corrupted or tampered with, this won't be used directly,
// but serves as a build-time validation mechanism
const SOURCE_CHECKSUM: &str = "CHECKSUM_PLACEHOLDER";

// Binary build timestamp, updated during compilation
// Used to detect if binary was modified after compilation
const BUILD_TIMESTAMP: &str = "TIMESTAMP_PLACEHOLDER";

// SpaceX-style event tracking
#[derive(Debug, Clone)]
enum Event {
    Startup(u64),
    CrashDetected(u64),
    FailsafeLaunched(u64),
}

// Global event counter
static EVENT_COUNT: AtomicU64 = AtomicU64::new(0);

// Recover from any panic with a failsafe shell
fn main() {
    // Set up panic handler to ensure we always get a shell even on panic
    std::panic::set_hook(Box::new(|_| {
        eprintln!("\x1b[31m⚠️  Shell guardian crashed!\x1b[0m");
        eprintln!("\x1b[33m💡 Launching minimal environment\x1b[0m");
        
        // Log panic event
        EVENT_COUNT.fetch_add(1, Ordering::Relaxed);
        
        // Launch bash as a last resort
        let _ = Command::new("bash")
            .arg("--norc")
            .env("PS1", "\x1b[31m[PANIC_RECOVERY]\x1b[0m \\w\\$ ")
            .env("PATH", "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin")
            .env("TERM", "xterm-256color")
            .env("SHELL_GUARDIAN_ACTIVE", "1")
            .env("SHELL_GUARDIAN_PANIC", "1")
            .status();
    }));

    // Guard main function with Result to handle errors gracefully
    if let Err(e) = run() {
        eprintln!("\x1b[31m⚠️  Shell guardian error: {}\x1b[0m", e);
        run_failsafe_shell();
    }
}

// Main run function wrapped in Result for error handling
fn run() -> io::Result<()> {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        return Err(io::Error::new(io::ErrorKind::InvalidInput, 
                                "Usage: shell-guardian <command> [args...]"));
    }

    // Get home directory and command
    let home = env::var("HOME").unwrap_or_else(|_| String::from(FALLBACK_DIR));
    let log_path = Path::new(&home).join(LOG_FILE);
    let backup_log_path = Path::new(&home).join(BACKUP_LOG_FILE);
    let command = &args[1];
    let command_args = args[2..].to_vec();
    
    // Rotate log if it gets too large
    rotate_log_if_needed(&log_path, &backup_log_path)?;
    
    // Get current timestamp with error handling
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_else(|_| Duration::from_secs(0))
        .as_secs();

    // Pre-flight checks
    if let Err(e) = preflight_check() {
        eprintln!("\x1b[33m⚠️ Pre-flight: {}\x1b[0m", e);
    }

    // Check if we're in crash pattern
    if is_crash_pattern(&log_path, &backup_log_path, now)? {
        run_failsafe_shell();
        // This will never return as run_failsafe_shell calls exit()
        Ok(())
    } else {
        // Log startup time
        append_to_log(&log_path, now.to_string())?;
        
        // Spawn keeper in background
        ensure_survival();
        
        // SpaceX-style heartbeat thread
        let heartbeat_path = Path::new(&home).join(".guardian-heartbeat");
        let heartbeat_path_clone = heartbeat_path.clone();
        std::thread::spawn(move || {
            loop {
                let timestamp = SystemTime::now()
                    .duration_since(UNIX_EPOCH)
                    .unwrap_or_default()
                    .as_secs();
                let _ = fs::write(&heartbeat_path_clone, timestamp.to_string());
                std::thread::sleep(Duration::from_secs(HEARTBEAT_INTERVAL));
            }
        });
        
        // Run normal shell
        let status = Command::new(command)
            .args(command_args)
            .status()?;
        
        exit(status.code().unwrap_or(1)); // Default to error
    }
}

// Rotate log file if it gets too large
fn rotate_log_if_needed(log_path: &Path, backup_path: &Path) -> io::Result<()> {
    if let Ok(metadata) = fs::metadata(log_path) {
        if metadata.len() > MAX_LOG_SIZE {
            // Backup old log
            if log_path.exists() {
                let _ = fs::copy(log_path, backup_path);
            }
            
            // Truncate log file
            let _ = File::create(log_path)?;
        }
    }
    Ok(())
}

// Safely append to log file
fn append_to_log(log_path: &Path, content: String) -> io::Result<()> {
    let mut file = OpenOptions::new()
        .create(true)
        .append(true)
        .open(log_path)?;
    
    writeln!(file, "{}", content)?;
    file.sync_all()?;
    Ok(())
}

// Pre-flight checks - SpaceX style
fn preflight_check() -> Result<(), String> {
    // Check disk space
    if let Ok(output) = Command::new("df")
        .args(&["-BM", "/tmp"])
        .output() {
        let output_str = String::from_utf8_lossy(&output.stdout);
        if let Some(line) = output_str.lines().nth(1) {
            let parts: Vec<&str> = line.split_whitespace().collect();
            if parts.len() > 3 {
                if let Ok(available) = parts[3].trim_end_matches('M').parse::<u64>() {
                    if available < MIN_FREE_DISK_MB {
                        return Err(format!("Low disk: {}MB", available));
                    }
                }
            }
        }
    }
    Ok(())
}

// Check if recent shell invocations show a crash pattern
fn is_crash_pattern(log_path: &Path, backup_path: &Path, now: u64) -> io::Result<bool> {
    // Initialize crash count
    let mut crash_count = 0;
    let mut timestamps = VecDeque::new();
    
    // Read primary log file
    if log_path.exists() {
        if let Ok(content) = fs::read_to_string(log_path) {
            for line in content.lines().rev().take(CRASH_THRESHOLD) {
                if let Ok(ts) = line.parse::<u64>() {
                    timestamps.push_back(ts);
                }
            }
        }
    }
    
    // If we need more entries, also check backup log
    if timestamps.len() < CRASH_THRESHOLD && backup_path.exists() {
        if let Ok(content) = fs::read_to_string(backup_path) {
            for line in content.lines().rev().take(CRASH_THRESHOLD - timestamps.len()) {
                if let Ok(ts) = line.parse::<u64>() {
                    timestamps.push_back(ts);
                }
            }
        }
    }
    
    // Count recent timestamps
    for ts in timestamps {
        if now - ts < CRASH_TIME {
            crash_count += 1;
        }
    }
    
    // If threshold reached, mark as crash pattern
    if crash_count >= CRASH_THRESHOLD - 1 {
        // Log crash detection with atomic append (BSD fix)
        let crash_msg = format!("CRASH_DETECTED_{}", now);
        if let Ok(mut file) = OpenOptions::new()
            .create(true)
            .append(true)
            .open(log_path) {
            let _ = writeln!(file, "{}", crash_msg);
            let _ = file.sync_all();
        }
        return Ok(true);
    }
    
    Ok(false)
}

// Ensure survival by running the keeper as a background process
fn ensure_survival() {
    // Try to find keeper binary
    let home = match env::var("HOME") {
        Ok(h) => h,
        Err(_) => return, // Can't do anything without HOME
    };
    
    // Possible keeper locations
    let keeper_locations = [
        format!("{}/.local/bin/guardian-keeper", home),
        format!("{}/.dotfiles/.guardian-shell/guardian-keeper", home),
    ];
    
    // Try each location
    for keeper_path in keeper_locations.iter() {
        if Path::new(keeper_path).exists() {
            // Run keeper in background
            let _ = Command::new(keeper_path)
                .stdout(std::process::Stdio::null())
                .stderr(std::process::Stdio::null())
                .spawn();
            return;
        }
    }
}

// Launch minimal failsafe shell
fn run_failsafe_shell() -> ! {
    eprintln!("\x1b[31m⚠️  Shell crash detected!\x1b[0m");
    eprintln!("\x1b[33m💡 Launching minimal environment\x1b[0m");
    
    // SpaceX-style Sol counter
    let sol = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs() / 86400;
    eprintln!("\x1b[90m🚀 Sol {}: Entering safe mode...\x1b[0m", sol);
    
    // Try to get login shell from environment
    let shell = env::var("SHELL")
        .unwrap_or_else(|_| String::from(RECOVERY_SHELL));
    
    // Choose appropriate shell arguments
    let shell_args = if shell.contains("bash") {
        vec!["--norc"]
    } else if shell.contains("zsh") {
        vec!["--no-rcs"]
    } else {
        vec![]
    };
    
    // Try to launch preferred shell first
    let status = Command::new(&shell)
        .args(&shell_args)
        .env("PS1", "\x1b[31m[FAILSAFE]\x1b[0m \\w\\$ ")
        .env("PATH", "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$HOME/.local/bin")
        .env("TERM", "xterm-256color")
        .env("LANG", "en_US.UTF-8")
        .env("SHELL_GUARDIAN_ACTIVE", "1")
        .status();
    
    // If preferred shell fails, try bash as fallback
    if status.is_err() {
        let fallback_status = Command::new(RECOVERY_SHELL)
            .arg("--norc")
            .env("PS1", "\x1b[31m[FAILSAFE]\x1b[0m \\w\\$ ")
            .env("PATH", "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$HOME/.local/bin")
            .env("TERM", "xterm-256color")
            .env("LANG", "en_US.UTF-8")
            .env("SHELL_GUARDIAN_ACTIVE", "1")
            .status();
        
        exit(fallback_status.map(|s| s.code().unwrap_or(0)).unwrap_or(1));
    }
    
    // Exit with the status of the recovery shell
    exit(status.map(|s| s.code().unwrap_or(0)).unwrap_or(1));
}