// Ultra-minimal shell-guardian.rs
// Compile with: rustc -O shell-guardian.rs

use std::env;
use std::path::Path;
use std::process::{Command, exit};
use std::fs::{self, File};
use std::io::Write;
use std::time::{SystemTime, UNIX_EPOCH};

// Guardian log file
const LOG_FILE: &str = ".shell-guardian.log";
// Crash detection settings
const CRASH_THRESHOLD: usize = 3;  // Number of crashes
const CRASH_TIME: u64 = 10;        // Within N seconds

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        eprintln!("Usage: shell-guardian <command> [args...]");
        exit(1);
    }

    // Get home directory and command
    let home = env::var("HOME").unwrap_or_else(|_| String::from("/tmp"));
    let log_path = Path::new(&home).join(LOG_FILE);
    let command = &args[1];
    let command_args = args[2..].to_vec();
    
    // Get current timestamp
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs();

    // Check if we're in crash pattern
    if is_crash_pattern(&log_path, now) {
        run_failsafe_shell();
    } else {
        // Log startup time
        if let Ok(mut file) = File::options().create(true).append(true).open(&log_path) {
            let _ = writeln!(file, "{}", now);
        }
        
        // Run normal shell
        let status = Command::new(command)
            .args(command_args)
            .status();
        
        exit(status.map(|s| s.code().unwrap_or(0)).unwrap_or(1));
    }
}

// Check if recent shell invocations show a crash pattern
fn is_crash_pattern(log_path: &Path, now: u64) -> bool {
    // Check log for crash pattern
    if let Ok(content) = fs::read_to_string(log_path) {
        // Count recent timestamps
        let mut crash_count = 0;
        for line in content.lines().rev().take(CRASH_THRESHOLD) {
            if let Ok(ts) = line.parse::<u64>() {
                if now - ts < CRASH_TIME {
                    crash_count += 1;
                }
            }
        }
        
        // If threshold reached, mark as crash pattern
        if crash_count >= CRASH_THRESHOLD - 1 {
            // Log crash detection
            if let Ok(mut file) = File::create(log_path) {
                let _ = writeln!(file, "CRASH_DETECTED_{}", now);
            }
            return true;
        }
    }
    
    false
}

// Launch minimal failsafe shell
fn run_failsafe_shell() {
    eprintln!("\x1b[31m⚠️  Shell crash detected!\x1b[0m");
    eprintln!("\x1b[33m💡 Launching minimal environment\x1b[0m");
    
    // Absolute minimal environment with no rc files
    let status = Command::new("bash")
        .arg("--norc")
        .env("PS1", "\x1b[31m[FAILSAFE]\x1b[0m \\w\\$ ")
        .env("PATH", "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$HOME/.local/bin")
        .env("TERM", "xterm-256color")
        .env("LANG", "en_US.UTF-8")
        .env("SHELL_GUARDIAN_ACTIVE", "1")
        .status();
    
    exit(status.map(|s| s.code().unwrap_or(0)).unwrap_or(1));
}