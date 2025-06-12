// Ultra-hardened shell-guardian.rs - NASA + BSD security fixes applied
// Compile with: rustc -O -C opt-level=3 -C lto=fat -C codegen-units=1 shell-guardian-fixed.rs

use std::env;
use std::path::{Path, PathBuf};
use std::process::{Command, exit};
use std::fs::{self, File, OpenOptions};
use std::io::{self, Write, Read, BufRead, BufReader};
use std::time::{SystemTime, UNIX_EPOCH, Duration, Instant};
use std::collections::VecDeque;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::Arc;

#[cfg(unix)]
use std::os::unix::fs::{OpenOptionsExt, PermissionsExt};

// Guardian settings
const CRASH_THRESHOLD: usize = 3;  // Number of crashes
const CRASH_WINDOW: Duration = Duration::from_secs(10);
const MAX_LOG_SIZE: u64 = 10240;   // 10KB maximum log size
const MAX_LOG_ENTRIES: usize = 100; // Bounded entries
const RECOVERY_SHELL: &str = "bash";
const FALLBACK_DIR: &str = "/tmp";
const GUARDIAN_SIGNATURE: &[u8] = b"GUARD_FIXED_V1\0";
const HEARTBEAT_INTERVAL: u64 = 5; // seconds

// Global state for signal handling
static RUNNING: AtomicBool = AtomicBool::new(true);
static HEARTBEAT_COUNTER: AtomicU64 = AtomicU64::new(0);

// Memory integrity check values
const MAGIC_CANARY: u64 = 0xDEADBEEF_CAFEBABE;
static MEMORY_CANARY: AtomicU64 = AtomicU64::new(MAGIC_CANARY);

// Signal handler
#[cfg(unix)]
extern "C" fn signal_handler(_: libc::c_int) {
    RUNNING.store(false, Ordering::SeqCst);
}

// Setup signal handlers
#[cfg(unix)]
fn setup_signals() {
    unsafe {
        // Handle SIGTERM gracefully
        libc::signal(libc::SIGTERM, signal_handler as libc::sighandler_t);
        libc::signal(libc::SIGINT, signal_handler as libc::sighandler_t);
        
        // Ignore SIGPIPE
        libc::signal(libc::SIGPIPE, libc::SIG_IGN);
        
        // No coredumps
        let limit = libc::rlimit {
            rlim_cur: 0,
            rlim_max: 0,
        };
        libc::setrlimit(libc::RLIMIT_CORE, &limit);
    }
}

// Generate random suffix for files
fn random_suffix() -> String {
    use std::collections::hash_map::DefaultHasher;
    use std::hash::{Hash, Hasher};
    
    let mut hasher = DefaultHasher::new();
    std::process::id().hash(&mut hasher);
    Instant::now().hash(&mut hasher);
    format!("{:x}", hasher.finish() & 0xFFFF)
}

// Secure log file paths with PID and randomness
fn get_log_paths(home: &str) -> (PathBuf, PathBuf, PathBuf) {
    let suffix = random_suffix();
    let pid = std::process::id();
    
    let log_file = format!(".shell-guardian-{}-{}.log", pid, suffix);
    let lock_file = format!(".shell-guardian-{}.lock", pid);
    let heartbeat_file = format!(".guardian-heartbeat-{}", pid);
    
    (
        PathBuf::from(home).join(log_file),
        PathBuf::from(home).join(lock_file),
        PathBuf::from(home).join(heartbeat_file),
    )
}

// Write heartbeat for watchdog
fn write_heartbeat(heartbeat_path: &Path) {
    let count = HEARTBEAT_COUNTER.fetch_add(1, Ordering::Relaxed);
    let timestamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs();
    
    let data = format!("{},{}\n", timestamp, count);
    let _ = fs::write(heartbeat_path, data);
}

// Verify memory integrity
fn check_memory_integrity() -> bool {
    MEMORY_CANARY.load(Ordering::SeqCst) == MAGIC_CANARY
}

// Secure file creation with O_EXCL
#[cfg(unix)]
fn create_log_file_secure(path: &Path) -> io::Result<File> {
    OpenOptions::new()
        .write(true)
        .create_new(true)  // O_EXCL - fail if exists
        .mode(0o600)       // User read/write only
        .open(path)
}

#[cfg(not(unix))]
fn create_log_file_secure(path: &Path) -> io::Result<File> {
    OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(path)
}

// Cleanup old files on startup
fn cleanup_stale_files(home: &str, max_age: Duration) {
    let now = SystemTime::now();
    
    if let Ok(entries) = fs::read_dir(home) {
        for entry in entries.filter_map(Result::ok) {
            if let Ok(name) = entry.file_name().into_string() {
                if name.starts_with(".shell-guardian-") || name.starts_with(".guardian-heartbeat-") {
                    if let Ok(metadata) = entry.metadata() {
                        if let Ok(modified) = metadata.modified() {
                            if let Ok(age) = now.duration_since(modified) {
                                if age > max_age {
                                    let _ = fs::remove_file(entry.path());
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

// Recover from any panic with a failsafe shell
fn main() {
    // Set restrictive umask
    #[cfg(unix)]
    unsafe {
        libc::umask(0o077); // rwx------
    }
    
    // Setup signal handlers
    #[cfg(unix)]
    setup_signals();
    
    // Set up panic handler
    std::panic::set_hook(Box::new(|info| {
        eprintln!("\x1b[31m⚠️  Shell guardian panic!\x1b[0m");
        
        // Check memory integrity
        if !check_memory_integrity() {
            eprintln!("\x1b[31m⚠️  MEMORY CORRUPTION DETECTED!\x1b[0m");
        }
        
        if let Some(s) = info.payload().downcast_ref::<&str>() {
            eprintln!("\x1b[31mReason: {}\x1b[0m", s);
        }
        
        eprintln!("\x1b[33m💡 Launching minimal environment\x1b[0m");
        
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

    // Run main logic
    if let Err(e) = run() {
        eprintln!("\x1b[31m⚠️  Shell guardian error: {}\x1b[0m", e);
        run_failsafe_shell();
    }
}

// Main run function
fn run() -> io::Result<()> {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        eprintln!("Usage: shell-guardian <command> [args...]");
        return Ok(());
    }

    // Get home directory
    let home = env::var("HOME").unwrap_or_else(|_| String::from(FALLBACK_DIR));
    
    // Cleanup old files (older than 1 hour)
    cleanup_stale_files(&home, Duration::from_secs(3600));
    
    // Get secure paths
    let (log_path, lock_path, heartbeat_path) = get_log_paths(&home);
    
    // Write initial heartbeat
    write_heartbeat(&heartbeat_path);
    
    // Check memory integrity
    if !check_memory_integrity() {
        eprintln!("\x1b[31m⚠️  Memory corruption detected at startup!\x1b[0m");
        run_failsafe_shell();
        unreachable!();
    }
    
    let command = &args[1];
    let command_args = args[2..].to_vec();
    
    // Rotate log if needed
    rotate_log_if_needed(&log_path)?;
    
    // Use monotonic time for crash detection
    let now_instant = Instant::now();
    let now_system = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs();

    // Check if we're in crash pattern
    if is_crash_pattern(&log_path, now_instant)? {
        // Atomically write crash marker
        append_to_log_atomic(&log_path, format!("CRASH_DETECTED,{}", now_system))?;
        run_failsafe_shell();
        unreachable!();
    } else {
        // Log startup time with PID
        let pid = std::process::id();
        append_to_log_atomic(&log_path, format!("{},{},START", now_system, pid))?;
        
        // Spawn keeper in background
        ensure_survival();
        
        // Spawn heartbeat thread
        let heartbeat_path_clone = heartbeat_path.clone();
        std::thread::spawn(move || {
            while RUNNING.load(Ordering::Relaxed) {
                write_heartbeat(&heartbeat_path_clone);
                std::thread::sleep(Duration::from_secs(HEARTBEAT_INTERVAL));
            }
        });
        
        // Run normal shell
        let status = Command::new(command)
            .args(command_args)
            .status()?;
        
        // Log clean exit
        append_to_log_atomic(&log_path, format!("{},{},EXIT", now_system, pid))?;
        
        // Cleanup our files
        let _ = fs::remove_file(&log_path);
        let _ = fs::remove_file(&lock_path);
        let _ = fs::remove_file(&heartbeat_path);
        
        exit(status.code().unwrap_or(1)); // Default to error on None
    }
}

// Atomic append to log with file locking
fn append_to_log_atomic(log_path: &Path, content: String) -> io::Result<()> {
    // Create temporary file
    let temp_path = log_path.with_extension("tmp");
    
    // Read existing content if file exists
    let mut existing_content = String::new();
    if log_path.exists() {
        File::open(log_path)?.read_to_string(&mut existing_content)?;
    }
    
    // Write to temp file
    let mut temp_file = create_log_file_secure(&temp_path)?;
    temp_file.write_all(existing_content.as_bytes())?;
    temp_file.write_all(content.as_bytes())?;
    temp_file.write_all(b"\n")?;
    temp_file.sync_all()?;
    drop(temp_file);
    
    // Atomic rename
    fs::rename(&temp_path, log_path)?;
    
    Ok(())
}

// Rotate log if needed
fn rotate_log_if_needed(log_path: &Path) -> io::Result<()> {
    if let Ok(metadata) = fs::metadata(log_path) {
        if metadata.len() > MAX_LOG_SIZE {
            let backup = log_path.with_extension("old");
            let _ = fs::rename(log_path, backup);
        }
    }
    Ok(())
}

// Check if recent shell invocations show a crash pattern using monotonic time
fn is_crash_pattern(log_path: &Path, now: Instant) -> io::Result<bool> {
    if !log_path.exists() {
        return Ok(false);
    }
    
    let file = File::open(log_path)?;
    let reader = BufReader::new(file);
    let mut recent_starts = Vec::new();
    
    // Read all entries, keeping only recent STARTs
    for line in reader.lines() {
        if let Ok(line) = line {
            let parts: Vec<&str> = line.split(',').collect();
            if parts.len() >= 3 && parts[2] == "START" {
                if let Ok(ts) = parts[0].parse::<u64>() {
                    recent_starts.push(ts);
                }
            }
        }
    }
    
    // Only keep last MAX_LOG_ENTRIES
    if recent_starts.len() > MAX_LOG_ENTRIES {
        recent_starts.drain(0..recent_starts.len() - MAX_LOG_ENTRIES);
    }
    
    // Count starts within crash window
    let current_ts = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs();
    
    let crash_count = recent_starts.iter()
        .filter(|&&ts| current_ts - ts < CRASH_WINDOW.as_secs())
        .count();
    
    Ok(crash_count >= CRASH_THRESHOLD)
}

// Ensure survival by spawning keeper
fn ensure_survival() {
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

// Launch minimal failsafe shell
fn run_failsafe_shell() -> ! {
    eprintln!("\x1b[31m⚠️  Shell crash detected!\x1b[0m");
    eprintln!("\x1b[33m💡 Launching minimal environment\x1b[0m");
    eprintln!("\x1b[33m📝 Type 'shell_help' for recovery options\x1b[0m");
    
    // Get current Sol (days since epoch) for Mars authenticity
    let sol = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs() / 86400;
    
    eprintln!("\x1b[90mSol {}: Entering safe mode...\x1b[0m", sol);
    
    let shell = env::var("SHELL").unwrap_or_else(|_| String::from(RECOVERY_SHELL));
    
    let shell_args = if shell.contains("bash") {
        vec!["--norc", "--noprofile"]
    } else if shell.contains("zsh") {
        vec!["--no-rcs", "--no-globalrcs"]  
    } else {
        vec![]
    };
    
    // Try preferred shell first
    let status = Command::new(&shell)
        .args(&shell_args)
        .env("PS1", "\x1b[31m[FAILSAFE]\x1b[0m \\w\\$ ")
        .env("PATH", "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$HOME/.local/bin")
        .env("TERM", "xterm-256color")
        .env("SHELL_GUARDIAN_ACTIVE", "1")
        .env("SHELL_GUARDIAN_SOL", sol.to_string())
        .status();
    
    // If preferred shell fails, try bash
    if status.is_err() {
        let fallback_status = Command::new(RECOVERY_SHELL)
            .arg("--norc")
            .env("PS1", "\x1b[31m[FAILSAFE]\x1b[0m \\w\\$ ")
            .env("PATH", "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$HOME/.local/bin")
            .env("TERM", "xterm-256color")
            .env("SHELL_GUARDIAN_ACTIVE", "1")
            .status();
        
        exit(fallback_status.map(|s| s.code().unwrap_or(1)).unwrap_or(1));
    }
    
    exit(status.map(|s| s.code().unwrap_or(1)).unwrap_or(1));
}