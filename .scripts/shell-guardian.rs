// shell-guardian.rs - Minimal shell monitor
// Compile with: rustc -O shell-guardian.rs

use std::env;
use std::path::Path;
use std::process::{Command, exit};
use std::fs::{self, File};
use std::io::Write;
use std::time::{SystemTime, UNIX_EPOCH};

// Guardian log file
const LOG_FILE: &str = ".shell-guardian.log";

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        eprintln!("Usage: shell-guardian <command> [args...]");
        exit(1);
    }

    // Get home directory
    let home = env::var("HOME").unwrap_or_else(|_| String::from("/tmp"));
    let log_path = Path::new(&home).join(LOG_FILE);

    // Create timestamp
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs();

    // Check for crash pattern - multiple invocations in short time
    let crash_threshold = 3; // Number of crashes
    let crash_time = 10;     // Within N seconds
    let mut crash_count = 0;
    let mut crash_detected = false;

    // Check log file for crash pattern
    if let Ok(content) = fs::read_to_string(&log_path) {
        for line in content.lines().rev().take(crash_threshold) {
            if let Ok(ts) = line.parse::<u64>() {
                if now - ts < crash_time {
                    crash_count += 1;
                }
            }
        }
        
        if crash_count >= crash_threshold - 1 {
            crash_detected = true;
            // Log crash detection
            if let Ok(mut file) = File::create(&log_path) {
                let _ = writeln!(file, "CRASH_DETECTED_{}", now);
            }
        }
    }

    // Build command with all arguments
    let command = &args[1];
    let command_args = args[2..].to_vec();

    if crash_detected {
        // Launch minimal environment instead
        eprintln!("\x1b[31m⚠️  Shell crash detected!\x1b[0m");
        eprintln!("\x1b[33m💡 Launching minimal environment\x1b[0m");
        
        // Launch minimal environment
        let status = Command::new("bash")
            .arg("--norc")
            .env("PS1", "\x1b[31m[FAILSAFE]\x1b[0m \\w\\$ ")
            .env("PATH", "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin")
            .env("TERM", "xterm-256color")
            .env("SHELL_GUARDIAN_ACTIVE", "1")
            .status();
        
        match status {
            Ok(exit_status) => exit(exit_status.code().unwrap_or(0)),
            Err(_) => exit(1),
        }
    } else {
        // Log normal startup
        if let Ok(mut file) = File::options().create(true).append(true).open(&log_path) {
            let _ = writeln!(file, "{}", now);
        }
        
        // Launch normal shell
        let status = Command::new(command)
            .args(command_args)
            .status();
        
        match status {
            Ok(exit_status) => exit(exit_status.code().unwrap_or(0)),
            Err(_) => exit(1),
        }
    }
}