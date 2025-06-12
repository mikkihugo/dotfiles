// Production-grade Shell Guardian with proper concurrency and error handling
// Compile: rustc -O -C opt-level=3 -C lto=fat -C codegen-units=1 shell-guardian-v2.rs -o shell-guardian

use std::env;
use std::fs::{self, File, OpenOptions};
use std::io::{self, Write, BufRead, BufReader};
use std::path::{Path, PathBuf};
use std::process::{Command, exit};
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{SystemTime, Duration, Instant};
use std::os::unix::fs::PermissionsExt;

#[cfg(unix)]
use std::os::unix::io::AsRawFd;

// Production constants
const LOG_FILE: &str = ".shell-guardian.log";
const LOCK_FILE: &str = ".shell-guardian.lock";
const CRASH_THRESHOLD: usize = 3;
const CRASH_WINDOW: Duration = Duration::from_secs(10);
const MAX_LOG_ENTRIES: usize = 100;
const LOG_ROTATION_SIZE: u64 = 1_048_576; // 1MB
const GUARDIAN_MAGIC: &[u8] = b"GUARD_V2";

// Global crash counter for signal handlers
static CRASH_COUNT: AtomicU64 = AtomicU64::new(0);

#[derive(Debug)]
enum GuardianError {
    Io(io::Error),
    Lock(String),
    InvalidLog,
    ExecFailed(String),
}

impl From<io::Error> for GuardianError {
    fn from(e: io::Error) -> Self {
        GuardianError::Io(e)
    }
}

impl std::fmt::Display for GuardianError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            GuardianError::Io(e) => write!(f, "IO error: {}", e),
            GuardianError::Lock(s) => write!(f, "Lock error: {}", s),
            GuardianError::InvalidLog => write!(f, "Invalid log format"),
            GuardianError::ExecFailed(s) => write!(f, "Exec failed: {}", s),
        }
    }
}

impl std::error::Error for GuardianError {}

// File lock structure for concurrent access
struct FileLock {
    _file: File,
}

impl FileLock {
    fn acquire(path: &Path) -> Result<Self, GuardianError> {
        let file = OpenOptions::new()
            .create(true)
            .write(true)
            .open(path)?;
        
        #[cfg(unix)]
        {
            use libc::{flock, LOCK_EX, LOCK_NB};
            let fd = file.as_raw_fd();
            
            let result = unsafe { flock(fd, LOCK_EX | LOCK_NB) };
            if result != 0 {
                return Err(GuardianError::Lock("Failed to acquire lock".into()));
            }
        }
        
        Ok(FileLock { _file: file })
    }
}

// Log entry with proper serialization
#[derive(Debug)]
struct LogEntry {
    timestamp: SystemTime,
    pid: u32,
    event: LogEvent,
}

#[derive(Debug)]
enum LogEvent {
    Startup,
    CrashDetected,
    FailsafeLaunched,
}

impl LogEntry {
    fn serialize(&self) -> String {
        let ts = self.timestamp.duration_since(SystemTime::UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs();
        
        let event_code = match self.event {
            LogEvent::Startup => "S",
            LogEvent::CrashDetected => "C",
            LogEvent::FailsafeLaunched => "F",
        };
        
        format!("{},{},{}", ts, self.pid, event_code)
    }
    
    fn deserialize(line: &str) -> Option<Self> {
        let parts: Vec<&str> = line.split(',').collect();
        if parts.len() != 3 {
            return None;
        }
        
        let ts = parts[0].parse::<u64>().ok()?;
        let pid = parts[1].parse::<u32>().ok()?;
        let event = match parts[2] {
            "S" => LogEvent::Startup,
            "C" => LogEvent::CrashDetected,
            "F" => LogEvent::FailsafeLaunched,
            _ => return None,
        };
        
        Some(LogEntry {
            timestamp: SystemTime::UNIX_EPOCH + Duration::from_secs(ts),
            pid,
            event,
        })
    }
}

// Circular log buffer with atomic operations
struct GuardianLog {
    path: PathBuf,
    lock_path: PathBuf,
}

impl GuardianLog {
    fn new(home: &str) -> Self {
        let base = Path::new(home);
        GuardianLog {
            path: base.join(LOG_FILE),
            lock_path: base.join(LOCK_FILE),
        }
    }
    
    fn write_entry(&self, entry: LogEntry) -> Result<(), GuardianError> {
        let _lock = FileLock::acquire(&self.lock_path)?;
        
        // Rotate if needed
        if let Ok(metadata) = fs::metadata(&self.path) {
            if metadata.len() > LOG_ROTATION_SIZE {
                let backup = self.path.with_extension("old");
                let _ = fs::rename(&self.path, backup);
            }
        }
        
        // Append with O_SYNC for crash safety
        let mut file = OpenOptions::new()
            .create(true)
            .append(true)
            .open(&self.path)?;
        
        writeln!(file, "{}", entry.serialize())?;
        file.sync_all()?;
        
        Ok(())
    }
    
    fn read_recent_entries(&self, window: Duration) -> Result<Vec<LogEntry>, GuardianError> {
        let _lock = FileLock::acquire(&self.lock_path)?;
        
        if !self.path.exists() {
            return Ok(Vec::new());
        }
        
        let file = File::open(&self.path)?;
        let reader = BufReader::new(file);
        let now = SystemTime::now();
        let cutoff = now - window;
        
        let mut entries = Vec::new();
        for line in reader.lines() {
            if let Ok(line) = line {
                if let Some(entry) = LogEntry::deserialize(&line) {
                    if entry.timestamp > cutoff {
                        entries.push(entry);
                    }
                }
            }
        }
        
        // Only keep last MAX_LOG_ENTRIES
        if entries.len() > MAX_LOG_ENTRIES {
            entries.drain(0..entries.len() - MAX_LOG_ENTRIES);
        }
        
        Ok(entries)
    }
    
    fn detect_crash_pattern(&self) -> Result<bool, GuardianError> {
        let entries = self.read_recent_entries(CRASH_WINDOW)?;
        
        let startup_count = entries.iter()
            .filter(|e| matches!(e.event, LogEvent::Startup))
            .count();
        
        Ok(startup_count >= CRASH_THRESHOLD)
    }
}

// Signal-safe panic handler
fn setup_panic_handler() {
    std::panic::set_hook(Box::new(|info| {
        // Increment crash counter atomically
        CRASH_COUNT.fetch_add(1, Ordering::SeqCst);
        
        // Try to log panic info to stderr (signal-safe)
        if let Some(s) = info.payload().downcast_ref::<&str>() {
            eprintln!("\x1b[31mGUARDIAN PANIC: {}\x1b[0m", s);
        } else {
            eprintln!("\x1b[31mGUARDIAN PANIC: Unknown error\x1b[0m");
        }
        
        // Launch emergency shell directly
        let _ = Command::new("/bin/sh")
            .arg("-c")
            .arg("exec /bin/bash --norc")
            .env("PS1", r"\[\033[31m\][PANIC]\[\033[0m\] \w \$ ")
            .env("GUARDIAN_PANIC", "1")
            .status();
    }));
}

// Main entry point with proper error propagation
fn main() {
    setup_panic_handler();
    
    match run() {
        Ok(code) => exit(code),
        Err(e) => {
            eprintln!("\x1b[31mGuardian error: {}\x1b[0m", e);
            launch_failsafe_shell();
        }
    }
}

fn run() -> Result<i32, GuardianError> {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        eprintln!("Usage: {} <command> [args...]", args[0]);
        return Ok(1);
    }
    
    let home = env::var("HOME")
        .unwrap_or_else(|_| String::from("/tmp"));
    
    let log = GuardianLog::new(&home);
    let my_pid = std::process::id();
    
    // Check for crash pattern
    if log.detect_crash_pattern()? {
        log.write_entry(LogEntry {
            timestamp: SystemTime::now(),
            pid: my_pid,
            event: LogEvent::CrashDetected,
        })?;
        
        launch_failsafe_shell();
        unreachable!();
    }
    
    // Log startup
    log.write_entry(LogEntry {
        timestamp: SystemTime::now(),
        pid: my_pid,
        event: LogEvent::Startup,
    })?;
    
    // Execute requested command
    let mut cmd = Command::new(&args[1]);
    if args.len() > 2 {
        cmd.args(&args[2..]);
    }
    
    // Spawn keeper process in background (non-blocking)
    spawn_keeper(&home);
    
    // Execute and return status
    match cmd.status() {
        Ok(status) => Ok(status.code().unwrap_or(1)),
        Err(e) => Err(GuardianError::ExecFailed(e.to_string())),
    }
}

// Spawn keeper process without blocking
fn spawn_keeper(home: &str) {
    let keeper_paths = [
        format!("{}/.local/bin/guardian-keeper", home),
        format!("{}/.dotfiles/.guardian-shell/guardian-keeper", home),
    ];
    
    for path in &keeper_paths {
        if Path::new(path).exists() {
            let _ = Command::new(path)
                .arg("check")
                .stdin(std::process::Stdio::null())
                .stdout(std::process::Stdio::null())
                .stderr(std::process::Stdio::null())
                .spawn();
            break;
        }
    }
}

// Launch failsafe shell with proper environment
fn launch_failsafe_shell() -> ! {
    eprintln!("\x1b[31m╔══════════════════════════════════╗\x1b[0m");
    eprintln!("\x1b[31m║     SHELL GUARDIAN FAILSAFE      ║\x1b[0m");
    eprintln!("\x1b[31m╚══════════════════════════════════╝\x1b[0m");
    eprintln!("\x1b[33m│ Crash loop detected              │\x1b[0m");
    eprintln!("\x1b[33m│ Launching minimal environment    │\x1b[0m");
    eprintln!("\x1b[33m│ Type 'shell_help' for recovery   │\x1b[0m");
    eprintln!("\x1b[33m╰──────────────────────────────────╯\x1b[0m");
    
    // Essential PATH only
    let safe_path = "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin";
    
    // Try multiple shells in order
    let shells = ["/bin/bash", "/bin/sh", "/usr/bin/bash", "/usr/bin/sh"];
    
    for shell in &shells {
        if Path::new(shell).exists() {
            let result = Command::new(shell)
                .arg("--norc")
                .arg("--noprofile")
                .env_clear()
                .env("PATH", safe_path)
                .env("HOME", env::var("HOME").unwrap_or_default())
                .env("USER", env::var("USER").unwrap_or_default())
                .env("TERM", "xterm-256color")
                .env("PS1", r"\[\033[31m\][FAILSAFE]\[\033[0m\] \w \$ ")
                .env("SHELL_GUARDIAN_FAILSAFE", "1")
                .status();
            
            if let Ok(status) = result {
                exit(status.code().unwrap_or(1));
            }
        }
    }
    
    // Ultimate fallback
    eprintln!("\x1b[31mFATAL: No shell found! System is broken!\x1b[0m");
    exit(255);
}

// Signal handler for clean shutdown
#[cfg(unix)]
extern "C" fn signal_handler(_: i32) {
    // Just increment counter, let main loop handle it
    CRASH_COUNT.fetch_add(1, Ordering::SeqCst);
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;
    
    #[test]
    fn test_log_serialization() {
        let entry = LogEntry {
            timestamp: SystemTime::UNIX_EPOCH + Duration::from_secs(1234567890),
            pid: 12345,
            event: LogEvent::Startup,
        };
        
        let serialized = entry.serialize();
        assert_eq!(serialized, "1234567890,12345,S");
        
        let deserialized = LogEntry::deserialize(&serialized).unwrap();
        assert_eq!(deserialized.pid, 12345);
    }
    
    #[test]
    fn test_crash_detection() {
        let temp_dir = TempDir::new().unwrap();
        let home = temp_dir.path().to_str().unwrap();
        let log = GuardianLog::new(home);
        
        // Write multiple startups
        for i in 0..5 {
            let entry = LogEntry {
                timestamp: SystemTime::now(),
                pid: 1000 + i,
                event: LogEvent::Startup,
            };
            log.write_entry(entry).unwrap();
        }
        
        // Should detect crash pattern
        assert!(log.detect_crash_pattern().unwrap());
    }
}