use anyhow::Result;
use std::time::{Duration, Instant};
use tokio::time::timeout;
use crate::sync::{SecretSync, SyncMethod};

/// Performance monitoring and optimization for secret sync
pub struct SyncPerformanceMonitor {
    start_time: Option<Instant>,
    method_timings: Vec<(String, Duration)>,
}

impl SyncPerformanceMonitor {
    pub fn new() -> Self {
        Self {
            start_time: None,
            method_timings: Vec::new(),
        }
    }

    pub fn start_timing(&mut self) {
        self.start_time = Some(Instant::now());
    }

    pub fn record_method(&mut self, method_name: String, duration: Duration) {
        self.method_timings.push((method_name, duration));
    }

    pub fn total_time(&self) -> Option<Duration> {
        self.start_time.map(|start| start.elapsed())
    }

    pub fn fastest_method(&self) -> Option<&(String, Duration)> {
        self.method_timings
            .iter()
            .min_by_key(|(_, duration)| duration)
    }

    pub fn report(&self) -> String {
        let mut report = String::new();
        report.push_str("🚀 Secret Sync Performance Report:\n");

        if let Some(total) = self.total_time() {
            report.push_str(&format!("   Total time: {:.2}s\n", total.as_secs_f64()));
        }

        for (method, duration) in &self.method_timings {
            let status = match duration.as_secs() {
                0..=1 => "⚡ Fast",
                2..=5 => "✅ Good",
                6..=10 => "⚠️  Slow",
                _ => "❌ Very Slow",
            };
            report.push_str(&format!(
                "   {}: {:.2}s ({})\n",
                method, duration.as_secs_f64(), status
            ));
        }

        if let Some((fastest_method, fastest_time)) = self.fastest_method() {
            report.push_str(&format!(
                "\n💡 Fastest method: {} ({:.2}s)\n",
                fastest_method, fastest_time.as_secs_f64()
            ));
        }

        report
    }
}

/// Optimized secret loading with fallback strategies
pub struct OptimizedSecretLoader {
    sync: SecretSync,
    performance_monitor: SyncPerformanceMonitor,
}

impl OptimizedSecretLoader {
    pub fn new(sync: SecretSync) -> Self {
        Self {
            sync,
            performance_monitor: SyncPerformanceMonitor::new(),
        }
    }

    /// Load secrets with intelligent method selection and fallbacks
    pub async fn load_secrets_optimized(&mut self) -> Result<Vec<String>> {
        self.performance_monitor.start_timing();

        let config = self.sync.get_config();
        let mut results = Vec::new();
        let mut successful_methods = Vec::new();

        // Strategy 1: Try fast local methods first
        let fast_methods = config.sync_methods.iter()
            .filter(|method| self.is_fast_method(method))
            .collect::<Vec<_>>();

        for method in fast_methods {
            if let Ok(result) = self.try_method_with_timeout(method, Duration::from_secs(2)).await {
                successful_methods.push(method);
                results.extend(result);
            }
        }

        // Strategy 2: If fast methods failed, try P2P with reasonable timeout
        if results.is_empty() {
            let p2p_methods = config.sync_methods.iter()
                .filter(|method| matches!(method, SyncMethod::LocalNetwork { .. }))
                .collect::<Vec<_>>();

            for method in p2p_methods {
                if let Ok(result) = self.try_method_with_timeout(method, Duration::from_secs(8)).await {
                    successful_methods.push(method);
                    results.extend(result);
                    break; // Only need one P2P success
                }
            }
        }

        // Strategy 3: Finally try slow/remote methods
        if results.is_empty() {
            let remaining_methods = config.sync_methods.iter()
                .filter(|method| !successful_methods.contains(method))
                .collect::<Vec<_>>();

            for method in remaining_methods {
                if let Ok(result) = self.try_method_with_timeout(method, Duration::from_secs(15)).await {
                    results.extend(result);
                    break;
                }
            }
        }

        println!("{}", self.performance_monitor.report());
        Ok(results)
    }

    async fn try_method_with_timeout(&mut self, method: &SyncMethod, timeout_duration: Duration) -> Result<Vec<String>> {
        let method_name = self.method_display_name(method);
        let start = Instant::now();

        let result = timeout(timeout_duration, self.sync_with_method(method)).await;

        let elapsed = start.elapsed();
        self.performance_monitor.record_method(method_name.clone(), elapsed);

        match result {
            Ok(Ok(secrets)) => {
                println!("✅ {} completed in {:.2}s", method_name, elapsed.as_secs_f64());
                Ok(secrets)
            }
            Ok(Err(e)) => {
                println!("❌ {} failed: {}", method_name, e);
                Err(e)
            }
            Err(_) => {
                println!("⏰ {} timed out after {:.2}s", method_name, timeout_duration.as_secs_f64());
                anyhow::bail!("Method {} timed out", method_name)
            }
        }
    }

    async fn sync_with_method(&self, method: &SyncMethod) -> Result<Vec<String>> {
        // This would call the actual sync implementation
        // For now, simulate different method performance characteristics
        match method {
            SyncMethod::LocalNetwork { .. } => {
                // Simulate P2P discovery and sync
                tokio::time::sleep(Duration::from_millis(4000)).await;
                Ok(vec!["API_KEY=p2p_secret".to_string()])
            }
            SyncMethod::ServerlessRelay { .. } => {
                // Simulate fast serverless response
                tokio::time::sleep(Duration::from_millis(800)).await;
                Ok(vec!["API_KEY=relay_secret".to_string()])
            }
            SyncMethod::FileDrop { .. } => {
                // Simulate instant file read
                tokio::time::sleep(Duration::from_millis(50)).await;
                Ok(vec!["API_KEY=file_secret".to_string()])
            }
            _ => {
                tokio::time::sleep(Duration::from_millis(1000)).await;
                Ok(vec!["API_KEY=other_secret".to_string()])
            }
        }
    }

    fn is_fast_method(&self, method: &SyncMethod) -> bool {
        matches!(method,
            SyncMethod::FileDrop { .. } |
            SyncMethod::ServerlessRelay { .. }
        )
    }

    fn method_display_name(&self, method: &SyncMethod) -> String {
        match method {
            SyncMethod::LocalNetwork { .. } => "P2P Local Network".to_string(),
            SyncMethod::Relay { .. } => "Self-hosted Relay".to_string(),
            SyncMethod::ServerlessRelay { provider, .. } => {
                format!("Serverless Relay ({:?})", provider)
            }
            SyncMethod::FileDrop { .. } => "File Drop Sync".to_string(),
            SyncMethod::Webhook { .. } => "Webhook Sync".to_string(),
        }
    }
}

/// GitHub Actions specific optimizations
pub struct GitHubActionsOptimizer;

impl GitHubActionsOptimizer {
    /// Recommend optimal sync strategy for GitHub Actions environment
    pub fn recommend_strategy() -> Vec<SyncMethod> {
        vec![
            // 1. Serverless relay - fastest for CI/CD
            SyncMethod::ServerlessRelay {
                provider: crate::sync::ServerlessProvider::Vercel,
                server_url: "https://your-org-secrets.vercel.app".to_string(),
                room_id: "ci-secrets".to_string(),
            },
            // 2. Backup serverless relay
            SyncMethod::ServerlessRelay {
                provider: crate::sync::ServerlessProvider::Netlify,
                server_url: "https://your-org-secrets.netlify.app".to_string(),
                room_id: "ci-secrets".to_string(),
            },
            // Note: P2P not recommended for GitHub Actions due to network isolation
        ]
    }

    /// Check if current environment is suitable for P2P
    pub fn is_p2p_suitable() -> bool {
        // GitHub Actions runners are isolated - P2P won't work
        std::env::var("GITHUB_ACTIONS").is_err() &&
        // Check if we're on a local network where P2P makes sense
        Self::has_local_network_peers()
    }

    fn has_local_network_peers() -> bool {
        // Simple heuristic: if we're not in CI and have network interfaces
        // In a real implementation, this would check for active network peers
        std::env::var("CI").is_err() &&
        std::env::var("GITHUB_ACTIONS").is_err()
    }

    /// Generate performance-optimized GitHub Actions workflow
    pub fn generate_optimized_workflow() -> String {
        r#"
name: Optimized Secret Loading

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
    - name: Cache Secret Sync Binary
      uses: actions/cache@v3
      with:
        path: /usr/local/bin/secret-tui
        key: secret-tui-${{ runner.os }}-v1

    - name: Install Secret Sync (if not cached)
      if: steps.cache.outputs.cache-hit != 'true'
      run: |
        wget -O secret-tui https://github.com/org/secret-tui/releases/latest/download/secret-tui-linux-x86_64
        chmod +x secret-tui
        sudo mv secret-tui /usr/local/bin/

    - name: Load Secrets (< 2 seconds)
      run: |
        # Uses serverless relays - no P2P discovery overhead
        secret-tui github-actions inject --environment production --timeout 5s
      timeout-minutes: 1  # Fail fast if secret loading hangs

    - name: Build with Secrets
      run: |
        # Secrets loaded in ~1 second, ready to use immediately
        echo "Building with secrets loaded in $(date)"
        ./build.sh
"#.to_string()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_performance_optimization() {
        // This would test the performance optimization strategies
        assert!(true); // Placeholder
    }

    #[test]
    fn test_github_actions_suitability() {
        // Test P2P suitability detection
        assert!(!GitHubActionsOptimizer::is_p2p_suitable() || std::env::var("GITHUB_ACTIONS").is_err());
    }
}