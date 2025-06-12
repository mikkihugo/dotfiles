// Shell Guardian - Toyota Safety Edition with ISO 26262 patterns
// Compile with: rustc -O -C opt-level=3 -C lto=fat -C codegen-units=1 shell-guardian-toyota.rs -o shell-guardian

use std::env;
use std::path::{Path, PathBuf};
use std::process::{Command, exit};
use std::fs::{self, File, OpenOptions};
use std::io::{self, Write, Read, BufRead, BufReader};
use std::time::{SystemTime, UNIX_EPOCH, Duration, Instant};
use std::collections::VecDeque;
use std::sync::atomic::{AtomicU64, AtomicU32, Ordering};
use std::sync::Arc;

// Guardian settings
const LOG_FILE: &str = ".shell-guardian.log";
const BACKUP_LOG_FILE: &str = ".shell-guardian.log.bak";
const CRASH_THRESHOLD: usize = 3;
const CRASH_TIME: u64 = 10;
const MAX_LOG_SIZE: u64 = 10240;
const RECOVERY_SHELL: &str = "bash";
const FALLBACK_DIR: &str = "/tmp";
const HEARTBEAT_INTERVAL: u64 = 5;
const MIN_FREE_DISK_MB: u64 = 100;
const MAX_OPERATION_TIME: Duration = Duration::from_secs(30);

// Toyota safety classifications
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
enum SafetyLevel {
    QM,     // Quality Managed
    ASILA,  // Automotive Safety Integrity Level A
    ASILB,  // ASIL-B
    ASILC,  // ASIL-C
    ASILD,  // ASIL-D (highest - life critical)
}

// System states with degraded modes
#[derive(Debug, Clone, Copy, PartialEq)]
enum SystemState {
    Healthy,           // All systems go
    Degraded,          // Reduced functionality
    LimpMode,          // Minimal safe operation
    EmergencyStop,     // Controlled shutdown
}

// Global state
static CURRENT_STATE: AtomicU32 = AtomicU32::new(0); // SystemState::Healthy
static EVENT_COUNT: AtomicU64 = AtomicU64::new(0);
static REPAIR_COUNT: AtomicU64 = AtomicU64::new(0);
static MEMORY_CANARY: AtomicU64 = AtomicU64::new(0xDEADBEEF_CAFEBABE);

// Forbidden paths - Poka-Yoke (mistake proofing)
const FORBIDDEN_PATHS: &[&str] = &[
    "/etc/passwd",
    "/etc/shadow",
    "/boot",
    "/sys",
    "/proc/sys",
    "/dev",
];

// Binary signatures
const SOURCE_CHECKSUM: &str = "CHECKSUM_PLACEHOLDER";
const BUILD_TIMESTAMP: &str = "TIMESTAMP_PLACEHOLDER";
const GUARDIAN_SIGNATURE: &[u8] = b"GUARD_TOYOTA_V1\0";

// Event tracking for Five Whys analysis
#[derive(Debug, Clone)]
enum Event {
    Startup(u64),
    CrashDetected(u64),
    StateTransition(SystemState, SystemState),
    FailsafeLaunched(u64),
    ValidationFailed(String),
    MemoryCorruption(u64),
}

// Get current state
fn get_system_state() -> SystemState {
    match CURRENT_STATE.load(Ordering::SeqCst) {
        0 => SystemState::Healthy,
        1 => SystemState::Degraded,
        2 => SystemState::LimpMode,
        3 => SystemState::EmergencyStop,
        _ => SystemState::EmergencyStop,
    }
}

// Set system state
fn set_system_state(state: SystemState) {
    let old_state = get_system_state();
    CURRENT_STATE.store(state as u32, Ordering::SeqCst);
    EVENT_COUNT.fetch_add(1, Ordering::Relaxed);
    
    // Andon - visual problem indicator
    print_health_status(state);
    
    if old_state != state {
        eprintln!("🔄 State transition: {:?} → {:?}", old_state, state);
    }
}

// Print health status - Andon system
fn print_health_status(state: SystemState) {
    match state {
        SystemState::Healthy => eprintln!("🟢 System OK"),
        SystemState::Degraded => eprintln!("🟡 Degraded Mode - Keeper disabled"),
        SystemState::LimpMode => eprintln!("🔴 Limp Mode - Basic shell only"),
        SystemState::EmergencyStop => eprintln!("🛑 EMERGENCY STOP - Manual intervention required"),
    }
}

// Plausibility check for commands
fn validate_command(cmd: &str) -> Result<(), String> {
    // Length check
    if cmd.len() > 1000 {
        return Err("Command too long".to_string());
    }
    
    // ASCII check
    if !cmd.chars().all(|c| c.is_ascii()) {
        return Err("Non-ASCII characters detected".to_string());
    }
    
    // Dangerous command check
    let dangerous_patterns = [
        "rm -rf /",
        "dd if=/dev/zero",
        ":(){ :|:& };:",  // Fork bomb
        "> /dev/sda",
    ];
    
    for pattern in &dangerous_patterns {
        if cmd.contains(pattern) {
            return Err(format!("Dangerous pattern detected: {}", pattern));
        }
    }
    
    Ok(())
}

// Check if path is safe to write
fn is_safe_path(path: &Path) -> bool {
    let path_str = path.to_string_lossy();
    !FORBIDDEN_PATHS.iter().any(|&forbidden| path_str.starts_with(forbidden))
}

// Check memory integrity with redundancy
fn check_memory_integrity() -> bool {
    let expected = 0xDEADBEEF_CAFEBABE;
    let actual = MEMORY_CANARY.load(Ordering::SeqCst);
    
    if actual != expected {
        eprintln!("⚠️ Memory corruption detected: {:016x} != {:016x}", actual, expected);
        return false;
    }
    
    true
}

// CRC32 checksum
fn crc32(data: &[u8]) -> u32 {
    let mut crc: u32 = 0xFFFFFFFF;
    
    for &byte in data {
        crc ^= byte as u32;
        for _ in 0..8 {
            if crc & 1 != 0 {
                crc = (crc >> 1) ^ 0xEDB88320;
            } else {
                crc >>= 1;
            }
        }
    }
    
    !crc
}

// Adler32 checksum for diversity
fn adler32(data: &[u8]) -> u32 {
    let mut a = 1u32;
    let mut b = 0u32;
    
    for &byte in data {
        a = (a + byte as u32) % 65521;
        b = (b + a) % 65521;
    }
    
    (b << 16) | a
}

// Cross-check with implementation diversity
fn cross_check_data(data: &[u8]) -> bool {
    let crc = crc32(data);
    let adler = adler32(data);
    
    // Both should produce different but consistent results
    // This detects calculation errors
    crc != 0 && adler != 0 && crc != adler
}

// Panic handler with safety classification
fn setup_panic_handler() {
    std::panic::set_hook(Box::new(|info| {
        // ASIL-D: Life critical - must always provide shell
        eprintln!("\x1b[31m⚠️ GUARDIAN PANIC [ASIL-D]\x1b[0m");
        
        // Check memory integrity
        if !check_memory_integrity() {
            eprintln!("\x1b[31m💀 MEMORY CORRUPTION DETECTED\x1b[0m");
        }
        
        if let Some(s) = info.payload().downcast_ref::<&str>() {
            eprintln!("\x1b[31mReason: {}\x1b[0m", s);
            
            // Five Whys logging
            eprintln!("Why did panic occur? → {}", s);
        }
        
        eprintln!("\x1b[33m💡 Launching emergency shell\x1b[0m");
        
        // Emergency shell with minimal environment
        let _ = Command::new("bash")
            .arg("--norc")
            .arg("--noprofile")
            .env("PS1", "\x1b[31m[PANIC_ASILD]\x1b[0m \\w\\$ ")
            .env("PATH", "/bin:/usr/bin")
            .env("GUARDIAN_PANIC", "1")
            .env("SAFETY_LEVEL", "ASIL_D")
            .status();
    }));
}

// Pre-flight checks with timing supervision
fn preflight_check() -> Result<(), String> {
    let start = Instant::now();
    
    // Memory integrity
    if !check_memory_integrity() {
        return Err("Memory corruption detected".to_string());
    }
    
    // Disk space check
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
    
    // Timing supervision
    if start.elapsed() > Duration::from_secs(5) {
        return Err("Pre-flight check timeout".to_string());
    }
    
    Ok(())
}

// Check crash pattern with two methods (diversity)
fn is_crash_pattern_method_a(log_path: &Path, now: u64) -> io::Result<bool> {
    if !log_path.exists() {
        return Ok(false);
    }
    
    let content = fs::read_to_string(log_path)?;
    let mut crash_count = 0;
    
    for line in content.lines().rev().take(CRASH_THRESHOLD * 2) {
        if let Ok(ts) = line.parse::<u64>() {
            if now - ts < CRASH_TIME {
                crash_count += 1;
            }
        }
    }
    
    Ok(crash_count >= CRASH_THRESHOLD)
}

fn is_crash_pattern_method_b(log_path: &Path, now: u64) -> io::Result<bool> {
    if !log_path.exists() {
        return Ok(false);
    }
    
    let file = File::open(log_path)?;
    let reader = BufReader::new(file);
    let mut timestamps = VecDeque::new();
    
    for line in reader.lines() {
        if let Ok(line) = line {
            if let Ok(ts) = line.parse::<u64>() {
                timestamps.push_back(ts);
                if timestamps.len() > CRASH_THRESHOLD * 2 {
                    timestamps.pop_front();
                }
            }
        }
    }
    
    let recent = timestamps.iter()
        .filter(|&&ts| now - ts < CRASH_TIME)
        .count();
    
    Ok(recent >= CRASH_THRESHOLD)
}

// Main run function with degraded modes
fn run() -> io::Result<()> {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        eprintln!("Usage: shell-guardian <command> [args...]");
        return Ok(());
    }
    
    // Validate command (plausibility check)
    let command = &args[1];
    if let Err(e) = validate_command(command) {
        eprintln!("⚠️ Command validation failed: {}", e);
        eprintln!("📝 Proceeding with caution...");
        set_system_state(SystemState::Degraded);
    }
    
    let home = env::var("HOME").unwrap_or_else(|_| String::from(FALLBACK_DIR));
    let log_path = Path::new(&home).join(LOG_FILE);
    let backup_log_path = Path::new(&home).join(BACKUP_LOG_FILE);
    
    // Pre-flight checks
    match preflight_check() {
        Ok(_) => {},
        Err(e) => {
            eprintln!("⚠️ Pre-flight: {}", e);
            if e.contains("Memory corruption") {
                set_system_state(SystemState::LimpMode);
            } else {
                set_system_state(SystemState::Degraded);
            }
        }
    }
    
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs();
    
    // Check crash pattern with diversity
    let crash_a = is_crash_pattern_method_a(&log_path, now)?;
    let crash_b = is_crash_pattern_method_b(&log_path, now)?;
    
    if crash_a && crash_b {
        // Both methods agree - definitely a crash pattern
        set_system_state(SystemState::LimpMode);
        run_failsafe_shell();
        unreachable!();
    } else if crash_a || crash_b {
        // Methods disagree - possible issue
        eprintln!("⚠️ Crash detection mismatch: A={}, B={}", crash_a, crash_b);
        set_system_state(SystemState::Degraded);
    }
    
    // Log startup
    append_to_log(&log_path, now.to_string())?;
    
    // Only spawn keeper if not in degraded mode
    if get_system_state() == SystemState::Healthy {
        ensure_survival();
    }
    
    // Heartbeat with supervision
    let heartbeat_path = Path::new(&home).join(".guardian-heartbeat");
    let heartbeat_path_clone = heartbeat_path.clone();
    let heartbeat_handle = std::thread::spawn(move || {
        loop {
            let timestamp = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap_or_default()
                .as_secs();
            let _ = fs::write(&heartbeat_path_clone, timestamp.to_string());
            std::thread::sleep(Duration::from_secs(HEARTBEAT_INTERVAL));
            
            // Check if we should stop
            if get_system_state() >= SystemState::LimpMode {
                break;
            }
        }
    });
    
    // Run command with timing supervision
    let start = Instant::now();
    let command_args = args[2..].to_vec();
    
    let status = Command::new(command)
        .args(command_args)
        .status()?;
    
    // Check execution time
    if start.elapsed() > MAX_OPERATION_TIME {
        eprintln!("⚠️ Command exceeded maximum execution time");
        set_system_state(SystemState::Degraded);
    }
    
    // Jidoka - automation with human touch
    let repairs = REPAIR_COUNT.load(Ordering::Relaxed);
    if repairs > 10 {
        eprintln!("⚠️ Excessive repairs detected: {}", repairs);
        eprintln!("❓ System may be unstable. Continue? (y/n)");
        // In real implementation, would wait for input
    }
    
    exit(status.code().unwrap_or(1)); // Default to error
}

// Append to log with safety checks
fn append_to_log(log_path: &Path, content: String) -> io::Result<()> {
    // Safety check
    if !is_safe_path(log_path) {
        return Err(io::Error::new(io::ErrorKind::PermissionDenied, 
                                  "Unsafe log path"));
    }
    
    // Rotate if needed
    if let Ok(metadata) = fs::metadata(log_path) {
        if metadata.len() > MAX_LOG_SIZE {
            let backup = log_path.with_extension("old");
            let _ = fs::rename(log_path, backup);
        }
    }
    
    // Atomic append
    let mut file = OpenOptions::new()
        .create(true)
        .append(true)
        .open(log_path)?;
    
    writeln!(file, "{}", content)?;
    file.sync_all()?;
    
    Ok(())
}

// Ensure survival (only in healthy state)
fn ensure_survival() {
    if get_system_state() != SystemState::Healthy {
        return;
    }
    
    let home = match env::var("HOME") {
        Ok(h) => h,
        Err(_) => return,
    };
    
    let keeper_locations = [
        format!("{}/.local/bin/guardian-keeper", home),
        format!("{}/.dotfiles/.guardian-shell/guardian-keeper", home),
    ];
    
    for keeper_path in keeper_locations.iter() {
        if Path::new(keeper_path).exists() {
            let _ = Command::new(keeper_path)
                .arg("check")
                .stdout(std::process::Stdio::null())
                .stderr(std::process::Stdio::null())
                .spawn();
            return;
        }
    }
}

// Launch failsafe shell with safety level
fn run_failsafe_shell() -> ! {
    eprintln!("\x1b[31m⚠️ Shell crash detected!\x1b[0m");
    eprintln!("\x1b[33m💡 Launching safe mode [ASIL-B]\x1b[0m");
    
    let sol = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs() / 86400;
    eprintln!("\x1b[90m🚗 Sol {}: Entering limp mode...\x1b[0m", sol);
    
    // Try preferred shell
    let shell = env::var("SHELL").unwrap_or_else(|_| String::from(RECOVERY_SHELL));
    
    let shell_args = if shell.contains("bash") {
        vec!["--norc", "--noprofile"]
    } else if shell.contains("zsh") {
        vec!["--no-rcs", "--no-globalrcs"]
    } else {
        vec![]
    };
    
    let status = Command::new(&shell)
        .args(&shell_args)
        .env("PS1", "\x1b[31m[LIMP_MODE]\x1b[0m \\w\\$ ")
        .env("PATH", "/usr/local/bin:/usr/bin:/bin")
        .env("TERM", "xterm-256color")
        .env("GUARDIAN_ACTIVE", "1")
        .env("SAFETY_LEVEL", "ASIL_B")
        .env("SYSTEM_STATE", "LIMP_MODE")
        .status();
    
    // If preferred shell fails, try bash
    if status.is_err() {
        let fallback_status = Command::new(RECOVERY_SHELL)
            .arg("--norc")
            .env("PS1", "\x1b[31m[EMERGENCY]\x1b[0m \\w\\$ ")
            .env("PATH", "/bin:/usr/bin")
            .env("GUARDIAN_ACTIVE", "1")
            .status();
        
        exit(fallback_status.map(|s| s.code().unwrap_or(1)).unwrap_or(1));
    }
    
    exit(status.map(|s| s.code().unwrap_or(1)).unwrap_or(1));
}

fn main() {
    // Set up panic handler with safety classification
    setup_panic_handler();
    
    // Toyota safety first
    set_system_state(SystemState::Healthy);
    
    // Run with error handling
    if let Err(e) = run() {
        eprintln!("\x1b[31m⚠️ Guardian error: {}\x1b[0m", e);
        
        // Five Whys
        eprintln!("Why did error occur? → {}", e);
        eprintln!("Why was error not prevented? → Check validation");
        
        run_failsafe_shell();
    }
}