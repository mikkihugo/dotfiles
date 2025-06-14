// Key Guardian - Secure credential management
// Fetches secrets from central vault and provides them securely to shells
// Compile: rustc -O key-guardian.rs -o key-guardian

use std::collections::HashMap;
use std::env;
use std::fs;
use std::io::{Read, Write};
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::Path;
use std::process::{Command, exit};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::{Duration, Instant};

const SOCKET_PATH: &str = "/tmp/key-guardian.sock";
const REFRESH_INTERVAL: u64 = 3600; // 1 hour
const DOPPLER_FALLBACK: &str = ".env_tokens"; // Fallback to file if vault unavailable

struct KeyGuardian {
    secrets: Arc<Mutex<HashMap<String, String>>>,
    last_refresh: Arc<Mutex<Instant>>,
    provider: String,
}

impl KeyGuardian {
    fn new(provider: &str) -> Self {
        KeyGuardian {
            secrets: Arc::new(Mutex::new(HashMap::new())),
            last_refresh: Arc::new(Mutex::new(Instant::now())),
            provider: provider.to_string(),
        }
    }
    
    // Fetch secrets from Doppler
    fn fetch_from_doppler(&self) -> Result<HashMap<String, String>, String> {
        let output = Command::new("doppler")
            .args(&["secrets", "download", "--no-file", "--format", "env"])
            .output()
            .map_err(|e| format!("Failed to run doppler: {}", e))?;
            
        if !output.status.success() {
            return Err(format!("Doppler failed: {}", String::from_utf8_lossy(&output.stderr)));
        }
        
        let mut secrets = HashMap::new();
        let content = String::from_utf8_lossy(&output.stdout);
        
        for line in content.lines() {
            if let Some(pos) = line.find('=') {
                let key = line[..pos].to_string();
                let value = line[pos+1..].to_string();
                secrets.insert(key, value);
            }
        }
        
        Ok(secrets)
    }
    
    // Fallback to local file
    fn fetch_from_file(&self) -> Result<HashMap<String, String>, String> {
        let home = env::var("HOME").unwrap_or_else(|_| "/tmp".to_string());
        let token_file = Path::new(&home).join(DOPPLER_FALLBACK);
        
        let content = fs::read_to_string(&token_file)
            .map_err(|e| format!("Failed to read {}: {}", token_file.display(), e))?;
            
        let mut secrets = HashMap::new();
        
        for line in content.lines() {
            let line = line.trim();
            if line.starts_with('#') || line.is_empty() {
                continue;
            }
            
            // Handle "export KEY=value" format
            let line = line.strip_prefix("export ").unwrap_or(line);
            
            if let Some(pos) = line.find('=') {
                let key = line[..pos].to_string();
                let value = line[pos+1..].trim_matches('"').to_string();
                secrets.insert(key, value);
            }
        }
        
        Ok(secrets)
    }
    
    // Refresh secrets from provider
    fn refresh_secrets(&self) -> Result<(), String> {
        let new_secrets = match self.provider.as_str() {
            "doppler" => self.fetch_from_doppler()
                .or_else(|_| {
                    eprintln!("Doppler failed, falling back to file");
                    self.fetch_from_file()
                })?,
            "file" => self.fetch_from_file()?,
            _ => return Err(format!("Unknown provider: {}", self.provider)),
        };
        
        let mut secrets = self.secrets.lock().unwrap();
        *secrets = new_secrets;
        
        let mut last_refresh = self.last_refresh.lock().unwrap();
        *last_refresh = Instant::now();
        
        Ok(())
    }
    
    // Handle client requests
    fn handle_client(&self, mut stream: UnixStream) -> Result<(), String> {
        let mut buffer = [0; 1024];
        let n = stream.read(&mut buffer).map_err(|e| e.to_string())?;
        let request = String::from_utf8_lossy(&buffer[..n]);
        
        let response = if request.starts_with("GET ") {
            let key = request[4..].trim();
            let secrets = self.secrets.lock().unwrap();
            secrets.get(key).cloned().unwrap_or_else(|| "".to_string())
        } else if request.trim() == "GET_ALL" {
            let secrets = self.secrets.lock().unwrap();
            secrets.iter()
                .map(|(k, v)| format!("export {}=\"{}\"", k, v))
                .collect::<Vec<_>>()
                .join("\n")
        } else if request.trim() == "REFRESH" {
            match self.refresh_secrets() {
                Ok(_) => "OK".to_string(),
                Err(e) => format!("ERROR: {}", e),
            }
        } else if request.trim() == "STATUS" {
            let last_refresh = self.last_refresh.lock().unwrap();
            let elapsed = last_refresh.elapsed().as_secs();
            let secrets = self.secrets.lock().unwrap();
            format!("Provider: {}\nKeys: {}\nLast refresh: {} seconds ago", 
                    self.provider, secrets.len(), elapsed)
        } else {
            "ERROR: Unknown command".to_string()
        };
        
        stream.write_all(response.as_bytes()).map_err(|e| e.to_string())?;
        Ok(())
    }
    
    // Start the daemon
    fn daemon(&self) -> Result<(), String> {
        // Remove old socket
        let _ = fs::remove_file(SOCKET_PATH);
        
        // Create Unix socket
        let listener = UnixListener::bind(SOCKET_PATH)
            .map_err(|e| format!("Failed to bind socket: {}", e))?;
            
        println!("Key Guardian started on {}", SOCKET_PATH);
        println!("Provider: {}", self.provider);
        
        // Initial load
        self.refresh_secrets()?;
        println!("Loaded {} secrets", self.secrets.lock().unwrap().len());
        
        // Start refresh thread
        let secrets = self.secrets.clone();
        let last_refresh = self.last_refresh.clone();
        let provider = self.provider.clone();
        
        thread::spawn(move || {
            loop {
                thread::sleep(Duration::from_secs(60)); // Check every minute
                let elapsed = last_refresh.lock().unwrap().elapsed().as_secs();
                
                if elapsed >= REFRESH_INTERVAL {
                    println!("Auto-refreshing secrets...");
                    // Clone self for refresh (simplified)
                    let guardian = KeyGuardian {
                        secrets: secrets.clone(),
                        last_refresh: last_refresh.clone(),
                        provider: provider.clone(),
                    };
                    
                    if let Err(e) = guardian.refresh_secrets() {
                        eprintln!("Auto-refresh failed: {}", e);
                    }
                }
            }
        });
        
        // Handle connections
        for stream in listener.incoming() {
            match stream {
                Ok(stream) => {
                    if let Err(e) = self.handle_client(stream) {
                        eprintln!("Client error: {}", e);
                    }
                }
                Err(e) => eprintln!("Connection error: {}", e),
            }
        }
        
        Ok(())
    }
}

fn main() {
    let args: Vec<String> = env::args().collect();
    
    match args.get(1).map(|s| s.as_str()) {
        Some("daemon") => {
            let provider = args.get(2).unwrap_or(&"file".to_string()).clone();
            let guardian = KeyGuardian::new(&provider);
            
            if let Err(e) = guardian.daemon() {
                eprintln!("Daemon error: {}", e);
                exit(1);
            }
        }
        Some("env") => {
            // Client mode - get all env vars
            match UnixStream::connect(SOCKET_PATH) {
                Ok(mut stream) => {
                    stream.write_all(b"GET_ALL").unwrap();
                    let mut response = String::new();
                    stream.read_to_string(&mut response).unwrap();
                    println!("{}", response);
                }
                Err(_) => {
                    eprintln!("Key guardian not running");
                    exit(1);
                }
            }
        }
        Some("get") => {
            // Client mode - get specific key
            if let Some(key) = args.get(2) {
                match UnixStream::connect(SOCKET_PATH) {
                    Ok(mut stream) => {
                        stream.write_all(format!("GET {}", key).as_bytes()).unwrap();
                        let mut response = String::new();
                        stream.read_to_string(&mut response).unwrap();
                        println!("{}", response);
                    }
                    Err(_) => {
                        eprintln!("Key guardian not running");
                        exit(1);
                    }
                }
            }
        }
        Some("status") => {
            // Client mode - check status
            match UnixStream::connect(SOCKET_PATH) {
                Ok(mut stream) => {
                    stream.write_all(b"STATUS").unwrap();
                    let mut response = String::new();
                    stream.read_to_string(&mut response).unwrap();
                    println!("{}", response);
                }
                Err(_) => {
                    eprintln!("Key guardian not running");
                    exit(1);
                }
            }
        }
        _ => {
            eprintln!("Usage:");
            eprintln!("  key-guardian daemon [provider]  # Start daemon (provider: doppler|file)");
            eprintln!("  key-guardian env               # Get all environment variables");
            eprintln!("  key-guardian get KEY           # Get specific key");
            eprintln!("  key-guardian status            # Check daemon status");
            exit(1);
        }
    }
}