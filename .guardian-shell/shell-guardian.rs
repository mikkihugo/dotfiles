// Minimal shell guardian that just works
// rustc -O shell-guardian-final.rs -o shell-guardian

use std::env;
use std::fs::{self, OpenOptions};
use std::io::Write;
use std::path::Path;
use std::process::{Command, exit};
use std::time::{SystemTime, UNIX_EPOCH};

const LOG_FILE: &str = ".guardian.log";
const CRASH_THRESHOLD: usize = 3;
const CRASH_WINDOW: u64 = 10; // seconds

fn main() {
    // Panic = give shell
    std::panic::set_hook(Box::new(|_| {
        eprintln!("Guardian panic! Launching backup shell...");
        let _ = Command::new("bash")
            .arg("--norc")
            .env("PS1", "[PANIC] $ ")
            .status();
    }));
    
    if let Err(e) = run() {
        eprintln!("Guardian error: {}", e);
        failsafe_shell();
    }
}

fn run() -> Result<(), Box<dyn std::error::Error>> {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        eprintln!("Usage: shell-guardian <command> [args...]");
        exit(1);
    }
    
    let home = env::var("HOME").unwrap_or_else(|_| "/tmp".to_string());
    let log_path = Path::new(&home).join(LOG_FILE);
    let now = SystemTime::now().duration_since(UNIX_EPOCH)?.as_secs();
    
    // Check crashes
    if is_crashing(&log_path, now)? {
        eprintln!("Crash loop detected!");
        failsafe_shell();
    }
    
    // Log startup
    let mut file = OpenOptions::new()
        .create(true)
        .append(true)
        .open(&log_path)?;
    writeln!(file, "{}", now)?;
    
    // Run command
    let status = Command::new(&args[1])
        .args(&args[2..])
        .status()?;
    
    exit(status.code().unwrap_or(1));
}

fn is_crashing(log_path: &Path, now: u64) -> Result<bool, Box<dyn std::error::Error>> {
    if !log_path.exists() {
        return Ok(false);
    }
    
    let content = fs::read_to_string(log_path)?;
    let recent_count = content.lines()
        .filter_map(|line| line.parse::<u64>().ok())
        .filter(|&ts| now - ts < CRASH_WINDOW)
        .count();
    
    Ok(recent_count >= CRASH_THRESHOLD)
}

fn failsafe_shell() -> ! {
    eprintln!("Launching failsafe shell...");
    
    let result = Command::new("bash")
        .arg("--norc")
        .env("PS1", "[FAILSAFE] $ ")
        .env("PATH", "/bin:/usr/bin")
        .status();
    
    match result {
        Ok(status) => exit(status.code().unwrap_or(1)),
        Err(_) => exit(1),
    }
}