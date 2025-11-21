use serde::{Deserialize, Serialize};
use std::fs;
use std::path::PathBuf;
use std::time::{Instant, Duration};
use std::sync::{Arc, Mutex, atomic::{AtomicBool, AtomicUsize, Ordering}};
use rayon::prelude::*;
use crossbeam::channel;
use log::{info, warn, error, debug};
use chrono::Utc;
use colored::*;
use xxhash_rust::xxh3::xxh3_64;
use crate::db;

#[derive(Debug, Deserialize, Clone)]
struct FTPConfig {
    pub server_address: String,
    pub port: u16,
    pub username: String,
    pub password: String,
    pub remote_destination: String, // Remote FTP directory to upload to
    pub local_source_path: String, // Local directory to monitor for files to upload
    pub respect_file_paths: bool,
    pub sync_interval: f64, // How often to run sync cycles (milliseconds from Swift, converted to seconds)
    pub stabilization_interval: u64, // How long to wait for file stabilization (milliseconds from Swift, converted to seconds)
    pub upload_aggressiveness: u32, // Number of parallel connections (from Swift enum)
    pub auto_tune_aggressiveness: bool, // Enable/disable auto-tuning of upload aggressiveness
    pub config_id: String, // Changed from u32 to String to use stable UUID instead of hash
    pub config_name: String,
    pub session_id: String, // Added: Session ID from Swift
}

#[derive(Debug, Serialize)]
struct FTPStatus {
    pub config_id: String,
    pub stage: String,
    pub filename: String,
    pub progress: f64,
    pub timestamp: u64,
    pub file_size: Option<u64>, // bytes
    pub upload_speed_mbps: Option<f64>, // MB/s for completed uploads
    pub upload_time_secs: Option<f64>, // seconds for completed uploads
}

#[derive(Debug, Serialize)]
struct FTPResult {
    pub config_id: String,
    pub success: bool,
    pub message: String,
    pub files_processed: usize,
    pub timestamp: u64,
}

#[derive(Debug, Serialize)]
struct FTPSessionSummary {
    pub config_id: String,
    pub config_name: String,
    pub start_time: u64,
    pub end_time: u64,
    pub total_duration_seconds: f64,
    pub files_processed: usize,
    pub total_bytes_uploaded: u64,
    pub average_upload_speed_mbps: f64,
    pub peak_upload_speed_mbps: f64,
    pub upload_speeds: Vec<f64>, // Individual file speeds for analysis
    pub success: bool,
    pub error_message: Option<String>,
}

#[derive(Debug, Serialize)]
struct FTPNotification {
    pub config_id: String,
    pub notification_type: String, // "success", "info", "warning", "error"
    pub message: String,
    pub timestamp: u64,
    pub filename: Option<String>,
    pub progress: Option<f64>,
}

// Monitor coordination structures for multi-client conflict detection
#[derive(Debug, Deserialize, Serialize, Clone)]
struct MonitorEntry {
    pub ip: String,
    pub hostname: String,
    pub profile_name: String,
    pub mode: String, // "keep" or "delete"
    pub last_seen: String, // ISO 8601 timestamp
}

#[derive(Debug, Deserialize, Serialize)]
struct MonitorFile {
    pub monitors: Vec<MonitorEntry>,
}

// Session state tracking for the entire FTP session
#[derive(Debug)]
struct SessionState {
    start_time: Instant,
    total_files: usize,
    total_bytes: usize,
    total_upload_time: f64, // seconds
    file_speeds: Vec<f64>, // MB/s for each file
    current_operation: String,
    errors: Vec<String>,
}

impl SessionState {
    fn new() -> Self {
        SessionState {
            start_time: Instant::now(),
            total_files: 0,
            total_bytes: 0,
            total_upload_time: 0.0,
            file_speeds: Vec::new(),
            current_operation: "Starting".to_string(),
            errors: Vec::new(),
        }
    }

    fn update_operation(&mut self, operation: &str) {
        self.current_operation = operation.to_string();
    }

    fn add_file_upload(&mut self, bytes: usize, upload_time: f64) {
        self.total_files += 1;
        self.total_bytes += bytes;
        self.total_upload_time += upload_time;

        // Calculate speed for this file
        if upload_time > 0.0 {
            let speed_mbps = (bytes as f64 / 1024.0 / 1024.0) / upload_time;
            self.file_speeds.push(speed_mbps);
        }
    }

    fn add_error(&mut self, error: &str) {
        self.errors.push(error.to_string());
    }

    fn get_average_speed_mbps(&self) -> f64 {
        if self.file_speeds.is_empty() {
            return 0.0;
        }
        self.file_speeds.iter().sum::<f64>() / self.file_speeds.len() as f64
    }

    fn get_peak_speed_mbps(&self) -> f64 {
        self.file_speeds.iter().fold(0.0, |max, &speed| max.max(speed))
    }

    fn get_session_duration(&self) -> f64 {
        self.start_time.elapsed().as_secs_f64()
    }

    fn generate_session_report(&self, config: &FTPConfig) -> SessionReport {
        SessionReport {
            session_id: config.session_id.clone(),
            config_id: config.config_id.clone(),
            total_files: self.total_files,
            total_bytes: self.total_bytes,
            total_time_secs: self.get_session_duration(),
            average_speed_mbps: self.get_average_speed_mbps(),
        }
    }
}

// Session report sent to Swift every 3rd file
#[derive(Debug, Serialize)]
struct SessionReport {
    pub session_id: String,
    pub config_id: String,
    pub total_files: usize,
    pub total_bytes: usize,
    pub total_time_secs: f64,
    pub average_speed_mbps: f64,
}

// Internal status update struct for parallel processing
#[derive(Debug, Clone)]
struct StatusUpdate {
    pub stage: String,
    pub filename: String,
    pub progress: f64,
    pub thread_id: u64,
    pub file_size: Option<u64>, // bytes
}

// Helper function to compute a stable u32 hash from UUID string (for FFI callbacks)
// Uses FNV-1a hash algorithm to match Swift's implementation
fn config_id_to_hash(config_id: &str) -> u32 {
    const FNV_OFFSET_BASIS: u64 = 0xcbf29ce484222325;
    const FNV_PRIME: u64 = 0x100000001b3;

    let mut hash: u64 = FNV_OFFSET_BASIS;
    for byte in config_id.as_bytes() {
        hash ^= *byte as u64;
        hash = hash.wrapping_mul(FNV_PRIME);
    }

    (hash & 0xFFFFFFFF) as u32
}

// Connection error analysis and retry management
#[derive(Debug)]
struct ConnectionManager {
    failed_attempts: AtomicUsize,
    last_failure_time: Arc<Mutex<Option<Instant>>>,
    server_limit_detected: AtomicBool,
}

impl ConnectionManager {
    fn new() -> Self {
        ConnectionManager {
            failed_attempts: AtomicUsize::new(0),
            last_failure_time: Arc::new(Mutex::new(None)),
            server_limit_detected: AtomicBool::new(false),
        }
    }
    
    fn is_server_rejection_error(error_msg: &str) -> bool {
        let error_lower = error_msg.to_lowercase();
        error_lower.contains("too many connections") ||
        error_lower.contains("connection limit") ||
        error_lower.contains("max connections") ||
        error_lower.contains("server full") ||
        error_lower.contains("connection refused") ||
        error_lower.contains("service unavailable") ||
        error_lower.contains("421") || // FTP 421 Service not available
        error_lower.contains("530") || // FTP 530 Not logged in
        error_lower.contains("exceeded") ||
        error_lower.contains("busy")
    }
    
    fn is_network_error(error_msg: &str) -> bool {
        let error_lower = error_msg.to_lowercase();
        error_lower.contains("timeout") ||
        error_lower.contains("connection reset") ||
        error_lower.contains("network unreachable") ||
        error_lower.contains("connection lost") ||
        error_lower.contains("broken pipe") ||
        error_lower.contains("connection aborted")
    }
    
    fn record_failure(&self, error_msg: &str, sync_interval: f64) -> (bool, Duration) {
        let attempts = self.failed_attempts.fetch_add(1, Ordering::SeqCst) + 1;
        *self.last_failure_time.lock().unwrap() = Some(Instant::now());

        let is_server_rejection = Self::is_server_rejection_error(error_msg);
        let is_network_issue = Self::is_network_error(error_msg);

        // DEBUG: Log what type of error we detected
        println!("🔍 CONNECTION DEBUG: Error='{}' ServerRejection={} NetworkIssue={} Attempt={} SyncInterval={}s",
            error_msg, is_server_rejection, is_network_issue, attempts, sync_interval);

        if is_server_rejection {
            self.server_limit_detected.store(true, Ordering::SeqCst);
        }

        // For very fast sync intervals (< 5s), use much shorter retry delays to avoid blocking
        let use_fast_retry = sync_interval < 5.0;

        // Calculate exponential backoff with jitter
        let base_delay = if use_fast_retry {
            // Fast sync mode: use minimal delays
            if is_server_rejection {
                2 // Server rejections need longer waits, but not too long for fast sync
            } else if is_network_issue {
                1 // Network issues can retry sooner
            } else {
                1 // General connection issues - very fast retry for fast sync
            }
        } else {
            // Normal sync mode: use standard delays
            if is_server_rejection {
                30 // Server rejections need longer waits
            } else if is_network_issue {
                5  // Network issues can retry sooner
            } else {
                10 // General connection issues
            }
        };

        let exponential_delay = if use_fast_retry {
            // For fast sync, limit exponential growth
            base_delay * (1.5_f64.powi((attempts - 1).min(3) as i32) as u64).max(1)
        } else {
            // Standard exponential backoff
            base_delay * (2_u64.pow((attempts - 1).min(6) as u32))
        };

        let jitter = (exponential_delay / 4).max(1);
        // Simple random jitter using system time
        let time_jitter = (std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_nanos() as u64) % jitter;
        let delay = Duration::from_secs(exponential_delay + time_jitter);

        // Cap delays based on sync mode
        let max_delay = if use_fast_retry {
            Duration::from_secs(sync_interval.max(5.0) as u64) // Cap at sync interval or 5s minimum
        } else {
            Duration::from_secs(300) // 5 minutes for normal mode
        };

        println!("🔍 RETRY DEBUG: FastRetry={} BaseDelay={}s ExponentialDelay={}s FinalDelay={}s MaxDelay={}s",
            use_fast_retry, base_delay, exponential_delay, delay.as_secs(), max_delay.as_secs());

        (is_server_rejection, delay.min(max_delay))
    }
    
    fn record_success(&self) {
        self.failed_attempts.store(0, Ordering::SeqCst);
        self.server_limit_detected.store(false, Ordering::SeqCst);
        *self.last_failure_time.lock().unwrap() = None;
    }
    
    fn should_reduce_connections(&self) -> bool {
        self.server_limit_detected.load(Ordering::SeqCst)
    }
    
    fn get_failure_count(&self) -> usize {
        self.failed_attempts.load(Ordering::SeqCst)
    }
}

// Helper function to prefix all output with config name
fn config_log(config: &FTPConfig, message: &str) {
    println!("[{}] {}", config.config_name, message);
}

// Read _monitored.json file from remote directory (Phase 1: Read-Only)
// Returns None if file doesn't exist or can't be read
// This function checks the file listing first to see if _monitored.json exists
// before attempting to retrieve it, avoiding unnecessary connection attempts
// NOTE: Using underscore prefix instead of dot so it appears in all FTP server listings
fn read_monitor_file(ftp: &mut ftp::FtpStream, remote_dir: &str, file_listing: &[String]) -> Option<MonitorFile> {
    let monitor_filename = "_monitored.json";

    println!("🔍 DEBUG: Looking for {} in directory listing of {}", monitor_filename, remote_dir);

    // First, check if _monitored.json appears in the file listing
    let found_in_listing = file_listing.iter().any(|entry| {
        // Extract filename from various FTP listing formats
        let trimmed = entry.trim();

        // Check if this entry is for .monitored.json
        // Handle both simple listings (just filename) and detailed listings (permissions, size, etc.)
        if trimmed.ends_with(monitor_filename) {
            true
        } else if trimmed == monitor_filename {
            true
        } else {
            // For detailed listings, filename is usually the last part
            let parts: Vec<&str> = trimmed.split_whitespace().collect();
            parts.last().map(|&name| name == monitor_filename).unwrap_or(false)
        }
    });

    if !found_in_listing {
        println!("ℹ️  DEBUG: {} not found in directory listing of {}", monitor_filename, remote_dir);
        return None;
    }

    println!("✅ DEBUG: {} found in listing, attempting to retrieve", monitor_filename);

    // File exists in listing, now retrieve it using the existing connection
    // Use relative path since we've already done cwd() to the directory
    match ftp.simple_retr(monitor_filename) {
        Ok(cursor) => {
            println!("✅ DEBUG: Successfully retrieved {} from {}", monitor_filename, remote_dir);
            // Read cursor into Vec<u8>
            use std::io::Read;
            let mut data = Vec::new();
            let mut reader = cursor;
            if let Err(e) = reader.read_to_end(&mut data) {
                println!("⚠️  Failed to read {} in {}: {}", monitor_filename, remote_dir, e);
                return None;
            }

            println!("✅ DEBUG: Read {} bytes from monitor file", data.len());

            // Parse JSON
            match serde_json::from_slice::<MonitorFile>(&data) {
                Ok(monitor_file) => {
                    println!("📡 Found monitor file in {}: {} monitors detected", remote_dir, monitor_file.monitors.len());
                    Some(monitor_file)
                }
                Err(e) => {
                    println!("⚠️  Failed to parse {} in {}: {}", monitor_filename, remote_dir, e);
                    println!("⚠️  Raw content: {}", String::from_utf8_lossy(&data));
                    None
                }
            }
        }
        Err(e) => {
            // Retrieval failed even though file was in listing
            println!("⚠️  DEBUG: {} was in listing but retrieval failed in {}: {}", monitor_filename, remote_dir, e);
            None
        }
    }
}

// Detect conflicts in monitor file and return warning messages
// Returns (conflict_level, message) where conflict_level is "critical", "warning", or "info"
// Excludes the current instance (identified by hostname + profile_name) from conflict detection
fn detect_monitor_conflicts(monitor_file: &MonitorFile, current_mode: &str, current_hostname: &str, current_profile: &str, ftp_directory: &str) -> Option<(String, String)> {
    // Normalize current mode to lowercase for case-insensitive comparison
    let current_mode_lower = current_mode.to_lowercase();

    println!("🔍 MONITOR CONFLICT DEBUG: current_mode='{}' (normalized: '{}')", current_mode, current_mode_lower);
    println!("🔍 MONITOR CONFLICT DEBUG: current_hostname='{}', current_profile='{}'", current_hostname, current_profile);
    println!("🔍 MONITOR CONFLICT DEBUG: Found {} monitors in file", monitor_file.monitors.len());

    // Filter out OUR OWN entry - only look for OTHER instances
    let delete_monitors: Vec<&MonitorEntry> = monitor_file.monitors.iter()
        .filter(|m| {
            let is_ours = m.hostname == current_hostname && m.profile_name == current_profile;
            let is_delete = m.mode.to_lowercase() == "delete";
            println!("🔍 MONITOR DEBUG: '{}' ({}) mode='{}' is_ours={} is_delete={}",
                m.profile_name, m.hostname, m.mode, is_ours, is_delete);
            !is_ours && is_delete  // Exclude ourselves AND must be delete mode
        })
        .collect();
    let keep_monitors: Vec<&MonitorEntry> = monitor_file.monitors.iter()
        .filter(|m| {
            let is_ours = m.hostname == current_hostname && m.profile_name == current_profile;
            let is_keep = m.mode.to_lowercase() == "keep";
            println!("🔍 MONITOR DEBUG: '{}' ({}) mode='{}' is_ours={} is_keep={}",
                m.profile_name, m.hostname, m.mode, is_ours, is_keep);
            !is_ours && is_keep  // Exclude ourselves AND must be keep mode
        })
        .collect();

    println!("🔍 MONITOR CONFLICT DEBUG: OTHER delete_monitors={}, OTHER keep_monitors={}", delete_monitors.len(), keep_monitors.len());

    // Critical: Multiple delete-mode monitors
    if delete_monitors.len() >= 2 {
        println!("🔴 MONITOR CONFLICT: Critical - multiple delete monitors");

        // Format list with each monitor on its own line
        let monitor_list: Vec<String> = delete_monitors.iter()
            .map(|m| format!("  • {} ({}) - DELETE mode", m.profile_name, m.hostname))
            .collect();

        return Some((
            "critical".to_string(),
            format!("Multiple FTPUploaders detected in FTP directory '{}':\n\n{}\n\nCONFLICT: Multiple DELETE-mode instances will cause unpredictable file deletion!",
                ftp_directory, monitor_list.join("\n"))
        ));
    }

    // Warning: One delete + current is keep (or vice versa)
    if !delete_monitors.is_empty() && current_mode_lower == "keep" {
        let monitor = &delete_monitors[0];
        println!("🟡 MONITOR CONFLICT: Warning - delete monitor exists, current is keep");
        return Some((
            "warning".to_string(),
            format!("Another FTPUploader detected in FTP directory '{}':\n\n  • {} ({}) - DELETE mode\n  • This instance - KEEP mode\n\nWARNING: The DELETE-mode instance may remove files before you upload them!",
                ftp_directory, monitor.profile_name, monitor.hostname)
        ));
    }

    if current_mode_lower == "delete" && !keep_monitors.is_empty() {
        println!("🟡 MONITOR CONFLICT: Warning - current is delete, keep monitors exist");

        // Format list with each monitor on its own line
        let monitor_list: Vec<String> = keep_monitors.iter()
            .map(|m| format!("  • {} ({}) - KEEP mode", m.profile_name, m.hostname))
            .collect();

        return Some((
            "warning".to_string(),
            format!("Other FTPUploaders detected in FTP directory '{}':\n\n{}\n  • This instance - DELETE mode\n\nWARNING: Your DELETE mode will affect their downloads!",
                ftp_directory, monitor_list.join("\n"))
        ));
    }

    // Info: Multiple keep-mode monitors (safe but redundant)
    // Note: keep_monitors already excludes ourselves, so >= 1 means at least one OTHER instance
    if keep_monitors.len() >= 1 && current_mode_lower == "keep" {
        println!("🔵 MONITOR CONFLICT: Info - multiple keep monitors (safe)");
        return Some((
            "info".to_string(),
            format!("Multiple FTPUploaders detected in FTP directory '{}' in KEEP mode. This is safe but redundant - all instances will upload the same files.", ftp_directory)
        ));
    }

    println!("✅ MONITOR CONFLICT DEBUG: No conflicts detected");
    None
}

// Get system hostname
fn get_hostname() -> String {
    use std::ffi::CStr;
    use std::os::raw::c_char;

    // Use libc to get hostname (works on Unix systems including macOS)
    #[cfg(unix)]
    {
        let mut buf = vec![0u8; 256];
        unsafe {
            if libc::gethostname(buf.as_mut_ptr() as *mut c_char, buf.len()) == 0 {
                if let Ok(hostname) = CStr::from_ptr(buf.as_ptr() as *const c_char).to_str() {
                    return hostname.to_string();
                }
            }
        }
    }

    // Fallback: try to get from environment or use unknown
    std::env::var("HOSTNAME")
        .or_else(|_| std::env::var("HOST"))
        .unwrap_or_else(|_| "unknown".to_string())
}

// Get local IP address (best effort - returns first non-loopback address)
fn get_local_ip() -> String {
    use std::net::{UdpSocket, IpAddr};

    println!("🔍 DEBUG: Getting local IP address...");

    // Method 1: UDP socket trick - Create a UDP socket and connect to a public IP
    // This doesn't actually send any data, just sets up the route to determine our local IP
    match UdpSocket::bind("0.0.0.0:0") {
        Ok(socket) => {
            println!("🔍 DEBUG: UDP socket bound successfully");
            // Try multiple public IPs in case one is unreachable
            let public_ips = vec!["8.8.8.8:80", "1.1.1.1:80", "208.67.222.222:80"];

            for public_ip in public_ips {
                println!("🔍 DEBUG: Trying to connect to {}", public_ip);
                if socket.connect(public_ip).is_ok() {
                    if let Ok(local_addr) = socket.local_addr() {
                        let ip_str = local_addr.ip().to_string();
                        println!("✅ DEBUG: Got local IP from UDP socket: {}", ip_str);
                        // Don't return localhost IPs
                        if !ip_str.starts_with("127.") && !ip_str.starts_with("::1") {
                            return ip_str;
                        }
                    }
                }
            }
            println!("⚠️  DEBUG: UDP socket method failed to get non-localhost IP");
        }
        Err(e) => {
            println!("⚠️  DEBUG: Failed to bind UDP socket: {}", e);
        }
    }

    // Method 2: Parse `ifconfig` output (macOS/BSD)
    #[cfg(unix)]
    {
        println!("🔍 DEBUG: Trying ifconfig method...");
        // Try ifconfig (macOS/BSD)
        if let Ok(output) = std::process::Command::new("ifconfig").output() {
            if let Ok(output_str) = String::from_utf8(output.stdout) {
                // Look for inet (IPv4) addresses that are not localhost
                for line in output_str.lines() {
                    let trimmed = line.trim();
                    if trimmed.starts_with("inet ") {
                        let parts: Vec<&str> = trimmed.split_whitespace().collect();
                        if parts.len() >= 2 {
                            let ip = parts[1];
                            // Skip localhost and link-local addresses
                            if !ip.starts_with("127.") && !ip.starts_with("169.254.") {
                                println!("✅ DEBUG: Got local IP from ifconfig: {}", ip);
                                return ip.to_string();
                            }
                        }
                    }
                }
            }
        }
        println!("⚠️  DEBUG: ifconfig method failed");
    }

    // Fallback: return "unknown" instead of localhost to make it clear we couldn't determine IP
    println!("⚠️  DEBUG: All methods failed, returning 'unknown'");
    "unknown".to_string()
}

// Write or update _monitored.json file on the FTP server
// Phase 2: Announce our presence by writing our entry to the monitor file
// This function:
// 1. Uploads existing _monitored.json (if exists)
// 2. Parses it and filters out stale entries (>5 minutes old)
// 3. Updates or adds our entry with current timestamp
// 4. Uploads the updated file back to the server
// Returns Ok(true) if write succeeded, Ok(false) if write failed (non-fatal), Err for fatal errors
fn write_monitor_file(
    ftp: &mut ftp::FtpStream,
    remote_dir: &str,
    config: &FTPConfig,
    file_listing: &[String]
) -> Result<bool, Box<dyn std::error::Error>> {
    let monitor_filename = "_monitored.json";

    println!("📝 MONITOR WRITE: Starting monitor file update for {}", remote_dir);

    // Get system info for our entry
    let hostname = get_hostname();
    let ip = get_local_ip();
    let current_time = Utc::now();

    println!("📝 MONITOR WRITE: hostname={}, ip={}, profile={}, mode={}",
        hostname, ip, config.config_name, "upload");

    // Step 1: Read existing monitor file (if it exists)
    let mut monitor_file = if let Some(existing) = read_monitor_file(ftp, remote_dir, file_listing) {
        println!("📝 MONITOR WRITE: Found existing monitor file with {} entries", existing.monitors.len());
        existing
    } else {
        println!("📝 MONITOR WRITE: No existing monitor file, creating new one");
        MonitorFile { monitors: Vec::new() }
    };

    // Step 2: Filter out stale entries (older than 5 minutes)
    let stale_threshold = current_time - chrono::Duration::minutes(5);
    let original_count = monitor_file.monitors.len();
    monitor_file.monitors.retain(|entry| {
        // Parse last_seen timestamp
        if let Ok(last_seen) = chrono::DateTime::parse_from_rfc3339(&entry.last_seen) {
            let is_fresh = last_seen.with_timezone(&Utc) > stale_threshold;
            if !is_fresh {
                println!("🧹 MONITOR WRITE: Removing stale entry: {} ({}), last seen: {}",
                    entry.profile_name, entry.hostname, entry.last_seen);
            }
            is_fresh
        } else {
            // If we can't parse the timestamp, remove it
            println!("🧹 MONITOR WRITE: Removing entry with invalid timestamp: {} ({})",
                entry.profile_name, entry.hostname);
            false
        }
    });

    if monitor_file.monitors.len() < original_count {
        println!("🧹 MONITOR WRITE: Removed {} stale entries", original_count - monitor_file.monitors.len());
    }

    // Step 3: Update or add our entry
    let our_entry = MonitorEntry {
        ip: ip.clone(),
        hostname: hostname.clone(),
        profile_name: config.config_name.clone(),
        mode: "upload".to_string(),
        last_seen: current_time.to_rfc3339(),
    };

    // Check if we already have an entry (match by hostname and profile_name)
    let existing_entry = monitor_file.monitors.iter_mut()
        .find(|e| e.hostname == hostname && e.profile_name == config.config_name);

    if let Some(entry) = existing_entry {
        println!("📝 MONITOR WRITE: Updating existing entry for {} ({})", config.config_name, hostname);
        *entry = our_entry;
    } else {
        println!("📝 MONITOR WRITE: Adding new entry for {} ({})", config.config_name, hostname);
        monitor_file.monitors.push(our_entry);
    }

    println!("📝 MONITOR WRITE: Final monitor file has {} entries", monitor_file.monitors.len());

    // Step 4: Serialize to JSON
    let json_data = match serde_json::to_string_pretty(&monitor_file) {
        Ok(data) => data,
        Err(e) => {
            println!("❌ MONITOR WRITE: Failed to serialize monitor file: {}", e);
            return Ok(false); // Non-fatal: continue without writing
        }
    };

    println!("📝 MONITOR WRITE: Serialized {} bytes of JSON", json_data.len());

    // Step 5: Upload to FTP server
    // First, write to a temporary local file
    let temp_file = std::env::temp_dir().join(format!("monitored_{}.json", config.config_id));
    if let Err(e) = fs::write(&temp_file, &json_data) {
        println!("❌ MONITOR WRITE: Failed to write temporary file {}: {}", temp_file.display(), e);
        return Ok(false); // Non-fatal
    }

    println!("📝 MONITOR WRITE: Wrote temporary file: {}", temp_file.display());

    // Upload the file to FTP server
    use std::io::Read;
    let mut file = match fs::File::open(&temp_file) {
        Ok(f) => f,
        Err(e) => {
            println!("❌ MONITOR WRITE: Failed to open temporary file: {}", e);
            return Ok(false); // Non-fatal
        }
    };

    println!("📝 MONITOR WRITE: Uploading to FTP server: {}", monitor_filename);

    // Use put() to upload the file (overwrites if exists)
    match ftp.put(monitor_filename, &mut file) {
        Ok(_) => {
            println!("✅ MONITOR WRITE: Successfully uploaded monitor file to {}", remote_dir);

            // Clean up temporary file
            let _ = fs::remove_file(&temp_file);

            Ok(true)
        }
        Err(e) => {
            println!("⚠️  MONITOR WRITE: Failed to upload monitor file to {}: {}", remote_dir, e);

            // Clean up temporary file
            let _ = fs::remove_file(&temp_file);

            // Send notification to UI about write failure (non-fatal warning)
            let _ = send_notification(
                &config,
                "info",
                &format!("Could not write monitor file to {}: {}. Monitoring will continue.", remote_dir, e),
                None,
                None
            );

            Ok(false) // Non-fatal: we couldn't announce our presence, but continue monitoring
        }
    }
}

// Remove our entry from _monitored.json file on the FTP server
// Called during cleanup when stopping monitoring or shutting down
fn cleanup_monitor_file(
    ftp: &mut ftp::FtpStream,
    remote_dir: &str,
    config: &FTPConfig,
    file_listing: &[String]
) -> Result<bool, Box<dyn std::error::Error>> {
    let monitor_filename = "_monitored.json";

    println!("🧹 MONITOR CLEANUP: Removing our entry from monitor file in {}", remote_dir);

    // Get system info to match our entry
    let hostname = get_hostname();

    // Step 1: Read existing monitor file
    let mut monitor_file = match read_monitor_file(ftp, remote_dir, file_listing) {
        Some(existing) => {
            println!("🧹 MONITOR CLEANUP: Found existing monitor file with {} entries", existing.monitors.len());
            existing
        }
        None => {
            println!("🧹 MONITOR CLEANUP: No monitor file found, nothing to clean up");
            return Ok(true);
        }
    };

    // Step 2: Remove our entry (match by hostname and profile_name)
    let original_count = monitor_file.monitors.len();
    monitor_file.monitors.retain(|e| {
        let is_ours = e.hostname == hostname && e.profile_name == config.config_name;
        if is_ours {
            println!("🧹 MONITOR CLEANUP: Removing our entry: {} ({})", e.profile_name, e.hostname);
        }
        !is_ours
    });

    if monitor_file.monitors.len() == original_count {
        println!("🧹 MONITOR CLEANUP: Our entry not found in monitor file");
        return Ok(true);
    }

    println!("🧹 MONITOR CLEANUP: {} entries remain after cleanup", monitor_file.monitors.len());

    // Step 3: If no entries remain, delete the monitor file
    if monitor_file.monitors.is_empty() {
        println!("🧹 MONITOR CLEANUP: No entries remain, deleting monitor file");
        match ftp.rm(monitor_filename) {
            Ok(_) => {
                println!("✅ MONITOR CLEANUP: Successfully deleted monitor file from {}", remote_dir);
                return Ok(true);
            }
            Err(e) => {
                println!("⚠️  MONITOR CLEANUP: Failed to delete monitor file: {}", e);
                return Ok(false); // Non-fatal
            }
        }
    }

    // Step 4: Upload updated monitor file (same process as write_monitor_file)
    let json_data = match serde_json::to_string_pretty(&monitor_file) {
        Ok(data) => data,
        Err(e) => {
            println!("❌ MONITOR CLEANUP: Failed to serialize monitor file: {}", e);
            return Ok(false);
        }
    };

    let temp_file = std::env::temp_dir().join(format!("monitored_cleanup_{}.json", config.config_id));
    if let Err(e) = fs::write(&temp_file, &json_data) {
        println!("❌ MONITOR CLEANUP: Failed to write temporary file: {}", e);
        return Ok(false);
    }

    use std::io::Read;
    let mut file = match fs::File::open(&temp_file) {
        Ok(f) => f,
        Err(e) => {
            println!("❌ MONITOR CLEANUP: Failed to open temporary file: {}", e);
            return Ok(false);
        }
    };

    match ftp.put(monitor_filename, &mut file) {
        Ok(_) => {
            println!("✅ MONITOR CLEANUP: Successfully updated monitor file in {}", remote_dir);
            let _ = fs::remove_file(&temp_file);
            Ok(true)
        }
        Err(e) => {
            println!("⚠️  MONITOR CLEANUP: Failed to upload updated monitor file: {}", e);
            let _ = fs::remove_file(&temp_file);
            Ok(false)
        }
    }
}

// Cleanup monitor files in all configured directories
// Called when the monitoring session ends (stop sync or app quit)
fn cleanup_all_monitor_files(
    config: &FTPConfig
) -> Result<(), Box<dyn std::error::Error>> {
    println!("🧹 CLEANUP ALL: Starting cleanup for {} directories", config.remote_destination.len());

    // Create new FTP connection for cleanup
    let server_addr = format!("{}:{}", config.server_address, config.port);
    let mut ftp = match ftp::FtpStream::connect(&server_addr) {
        Ok(stream) => stream,
        Err(e) => {
            println!("❌ CLEANUP ALL: Failed to connect to FTP server: {}", e);
            return Err(format!("FTP connection failed: {}", e).into());
        }
    };

    // Login
    if let Err(e) = ftp.login(&config.username, &config.password) {
        println!("❌ CLEANUP ALL: Failed to login to FTP server: {}", e);
        return Err(format!("FTP login failed: {}", e).into());
    }

    // Cleanup the remote destination directory
    let remote_dir = &config.remote_destination;
    println!("🧹 CLEANUP ALL: Processing directory {}", remote_dir);

    // Reset to root and change to directory
    if let Err(e) = ftp.cwd("/") {
        println!("⚠️  CLEANUP ALL: Failed to reset to root: {}", e);
        return Ok(());
    }

    if let Err(e) = ftp.cwd(remote_dir) {
        println!("⚠️  CLEANUP ALL: Failed to change to directory {}: {}", remote_dir, e);
        return Ok(());
    }

    // Get directory listing
    let files = match ftp.list(Some(remote_dir)) {
        Ok(files) => files,
        Err(e) => {
            println!("⚠️  CLEANUP ALL: Failed to list directory {}: {}", remote_dir, e);
            return Ok(());
        }
    };

    // Cleanup monitor file in this directory
    let _ = cleanup_monitor_file(&mut ftp, remote_dir, config, &files);

    println!("✅ CLEANUP ALL: Finished cleaning up all directories");
    Ok(())
}

// Helper function to get hash file path for keep mode
fn get_hash_file_path(hash_file: &str) -> Result<PathBuf, Box<dyn std::error::Error>> {
    let path = PathBuf::from(hash_file);
    
    // Ensure directory exists
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }
    
    Ok(path)
}

// Helper function to get file modification time from FTP server
fn get_file_mod_time(ftp: &mut ftp::FtpStream, filename: &str) -> Result<chrono::DateTime<chrono::Utc>, Box<dyn std::error::Error>> {
    match ftp.mdtm(filename) {
        Ok(Some(time)) => {
            // Convert from chrono v0.2.25 to chrono v0.4.41
            // The FTP crate uses chrono v0.2.25, we use v0.4.41
            let timestamp = time.timestamp();
            let naive = chrono::DateTime::from_timestamp(timestamp, 0)
                .unwrap_or_else(|| chrono::Utc::now())
                .naive_utc();
            Ok(chrono::DateTime::<chrono::Utc>::from_naive_utc_and_offset(naive, chrono::Utc))
        }
        Ok(None) => {
            // If MDTM returns None, return current time as fallback
            Ok(chrono::Utc::now())
        }
        Err(_) => {
            // If MDTM fails, return current time as fallback
            Ok(chrono::Utc::now())
        }
    }
}

// Helper function to compute file metadata hash
fn compute_file_hash(filename: &str, remote_dir: &str, size: u64, mod_time: chrono::DateTime<chrono::Utc>) -> u64 {
    let metadata_string = format!("{}|{}|{}|{}", remote_dir, filename, size, mod_time.timestamp());
    xxh3_64(metadata_string.as_bytes())
}

// Structure to hold complete file metadata for hash tracking
#[derive(Debug, Clone)]
struct FileMetadata {
    hash: u64,
    size: u64,
    mod_time: i64,
}

// Helper function to load existing hashes with full metadata
fn load_existing_hashes(hash_file_path: &PathBuf) -> std::collections::HashMap<String, u64> {
    let mut hashes = std::collections::HashMap::new();
    
    println!("🔍 HASH LOAD DEBUG: Reading file: {}", hash_file_path.display());
    
    if let Ok(content) = fs::read_to_string(hash_file_path) {
        println!("🔍 HASH LOAD DEBUG: File content length: {} bytes", content.len());
        let lines: Vec<&str> = content.lines().collect();
        println!("🔍 HASH LOAD DEBUG: File has {} lines", lines.len());
        
        for (line_num, line) in lines.iter().enumerate() {
            if line_num < 3 {
                println!("🔍 HASH LOAD DEBUG: Line {}: '{}'", line_num, line);
            }
            
            let parts: Vec<&str> = line.split('|').collect();
            println!("🔍 HASH LOAD DEBUG: Line {} has {} parts", line_num, parts.len());
            
            if parts.len() >= 5 {
                // New format: remote_dir|filename|size|mod_time|hash
                let remote_dir = parts[0];
                let filename = parts[1];
                let key = format!("{}|{}", remote_dir, filename);
                if let Ok(hash) = parts[4].parse::<u64>() {
                    hashes.insert(key.clone(), hash);
                    if line_num < 3 {
                        println!("🔍 HASH LOAD DEBUG: Loaded key='{}' hash={}", key, hash);
                    }
                } else {
                    println!("🔍 HASH LOAD DEBUG: Failed to parse hash from '{}'", parts[4]);
                }
            } else if parts.len() >= 3 {
                // Legacy format: remote_dir|filename|hash (for backward compatibility)
                let remote_dir = parts[0];
                let filename = parts[1];
                let key = format!("{}|{}", remote_dir, filename);
                if let Ok(hash) = parts[2].parse::<u64>() {
                    hashes.insert(key.clone(), hash);
                    if line_num < 3 {
                        println!("🔍 HASH LOAD DEBUG: Loaded legacy key='{}' hash={}", key, hash);
                    }
                } else {
                    println!("🔍 HASH LOAD DEBUG: Failed to parse legacy hash from '{}'", parts[2]);
                }
            } else {
                println!("🔍 HASH LOAD DEBUG: Skipping line {} with {} parts", line_num, parts.len());
            }
        }
    } else {
        println!("🔍 HASH LOAD DEBUG: Failed to read file: {}", hash_file_path.display());
    }
    
    println!("🔍 HASH LOAD DEBUG: Final loaded hash count: {}", hashes.len());
    hashes
}

// Helper function to load existing hashes with full metadata preserved
fn load_existing_hashes_with_metadata(hash_file_path: &PathBuf) -> std::collections::HashMap<String, FileMetadata> {
    let mut hashes = std::collections::HashMap::new();
    
    if let Ok(content) = fs::read_to_string(hash_file_path) {
        for line in content.lines() {
            let parts: Vec<&str> = line.split('|').collect();
            if parts.len() >= 5 {
                // New format: remote_dir|filename|size|mod_time|hash
                let remote_dir = parts[0];
                let filename = parts[1];
                let key = format!("{}|{}", remote_dir, filename);
                
                if let (Ok(size), Ok(mod_time), Ok(hash)) = (
                    parts[2].parse::<u64>(),
                    parts[3].parse::<i64>(),
                    parts[4].parse::<u64>()
                ) {
                    hashes.insert(key, FileMetadata { hash, size, mod_time });
                }
            } else if parts.len() >= 3 {
                // Legacy format: remote_dir|filename|hash (for backward compatibility)
                let remote_dir = parts[0];
                let filename = parts[1];
                let key = format!("{}|{}", remote_dir, filename);
                if let Ok(hash) = parts[2].parse::<u64>() {
                    // Use defaults for missing metadata
                    hashes.insert(key, FileMetadata { hash, size: 0, mod_time: 0 });
                }
            }
        }
    }
    
    hashes
}

// Helper function to trim hash file if it's too large
fn trim_hash_file_if_needed(hash_file_path: &PathBuf, max_lines: usize) -> Result<(), Box<dyn std::error::Error>> {
    if let Ok(content) = fs::read_to_string(hash_file_path) {
        let lines: Vec<&str> = content.lines().collect();
        let line_count = lines.len();
        
        if line_count > max_lines {
            // Keep only the most recent entries (last max_lines)
            let trimmed_lines: Vec<&str> = lines.into_iter().rev().take(max_lines).collect();
            let trimmed_count = trimmed_lines.len();
            
            // Write back the trimmed content
            let mut file = fs::OpenOptions::new()
                .write(true)
                .truncate(true)
                .open(hash_file_path)?;
            
            use std::io::Write;
            for line in trimmed_lines.iter().rev() { // Reverse back to original order
                file.write_all(format!("{}\n", line).as_bytes())?;
            }
            
            println!("✂️ Trimmed hash file from {} to {} lines", line_count, trimmed_count);
        }
    }
    
    Ok(())
}

// Helper function to save hash for a file (optimized append-only approach)
fn save_file_hash(hash_file_path: &PathBuf, filename: &str, remote_dir: &str, hash: u64, size: u64, mod_time: chrono::DateTime<chrono::Utc>) -> Result<(), Box<dyn std::error::Error>> {
    use std::sync::{Mutex, OnceLock};
    use std::io::Write;
    
    // Global mutex for hash file operations to prevent race conditions
    static HASH_FILE_MUTEX: OnceLock<Mutex<()>> = OnceLock::new();
    let mutex = HASH_FILE_MUTEX.get_or_init(|| Mutex::new(()));
    let _lock = mutex.lock().unwrap();
    
    println!("🔍 HASH SAVE DEBUG: Saving hash for {}/{}", remote_dir, filename);
    
    // Create the new hash entry
    let new_entry = format!("{}|{}|{}|{}|{}\n", remote_dir, filename, size, mod_time.timestamp(), hash);
    
    // Append-only approach - much faster for large files
    let mut file = fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(hash_file_path)?;
    
    file.write_all(new_entry.as_bytes())?;
    
    println!("🔍 HASH SAVE DEBUG: Successfully appended hash entry");
    Ok(())
}

// Session stats tracking for download speed calculation
#[derive(Debug)]
struct SessionStats {
    total_bytes: usize,
    total_time: f64, // seconds
    file_count: usize,
    session_start_time: u64, // Unix timestamp when session started
}

impl SessionStats {
    fn new() -> Self {
        SessionStats {
            total_bytes: 0,
            total_time: 0.0,
            file_count: 0,
            session_start_time: std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap_or_default()
                .as_secs(),
        }
    }

    fn update(&mut self, bytes: usize, time_secs: f64) {
        self.total_bytes += bytes;
        self.total_time += time_secs;
        self.file_count += 1;
    }

    fn average_speed_mbps(&self) -> f64 {
        if self.total_time > 0.0 {
            (self.total_bytes as f64 / 1024.0 / 1024.0) / self.total_time
        } else {
            0.0
        }
    }
    
    fn write_session_json(&self, session_file: &str, config: &FTPConfig) -> Result<(), Box<dyn std::error::Error>> {
        let report = SessionReport {
            session_id: config.session_id.clone(),
            config_id: config.config_id.clone(),
            total_files: self.file_count,
            total_bytes: self.total_bytes,
            total_time_secs: self.total_time,
            average_speed_mbps: self.average_speed_mbps(),
        };

        let report_json = serde_json::to_string_pretty(&report)?;
        
        // Debug: Print the session report being written
        config_log(config, &format!("📊 Writing session report to {}: {}", session_file, report_json));
        
        fs::write(session_file, report_json)?;
        
        // Log the session report - always show it, even if stats are 0
        if self.file_count > 0 {
            config_log(config, &format!("📊 Session Report: {} files, {:.2} MB/s", 
                self.file_count.to_string().green(),
                self.average_speed_mbps().to_string().cyan()
            ));
    
        } else {
            config_log(config, &format!("📊 Session Report: No files processed (0 files, 0.00 MB/s)"));
    
        }
        
        Ok(())
    }
}

/// Main FTP engine function that can be called from FFI or binary
///
/// This function contains all the FTP processing logic and can be invoked with
/// custom arguments and shutdown signaling, making it suitable for both
/// standalone binary execution and FFI library integration.
pub fn run_ftp_with_args(
    args: Vec<String>,
    shutdown_flag: Arc<AtomicBool>
) -> Result<(), Box<dyn std::error::Error>> {
    use std::io::Write;

    // Use FTP_TMP_DIR environment variable for sandboxed apps, fallback to /tmp
    let tmp_dir = std::env::var("FTP_TMP_DIR").unwrap_or_else(|_| "/tmp/".to_string());
    let diagnostic_log = format!("{}rust_ftp_startup.log", tmp_dir);

    let mut diag_file = fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(&diagnostic_log)
        .unwrap_or_else(|e| {
            eprintln!("FATAL: Cannot create diagnostic log at {}: {}", diagnostic_log, e);
            std::process::exit(1);
        });

    writeln!(diag_file, "\n========== RUST_FTP STARTUP {} ==========", Utc::now().format("%Y-%m-%d %H:%M:%S")).ok();
    writeln!(diag_file, "PID: {}", std::process::id()).ok();
    writeln!(diag_file, "Current directory: {:?}", std::env::current_dir()).ok();
    writeln!(diag_file, "Executable path: {:?}", std::env::current_exe()).ok();
    writeln!(diag_file, "Environment:").ok();
    for (key, value) in std::env::vars() {
        if key.starts_with("FTP") || key.starts_with("HOME") || key.starts_with("USER") || key.starts_with("TMPDIR") {
            writeln!(diag_file, "  {}: {}", key, value).ok();
        }
    }
    writeln!(diag_file, "Arguments: {:?}", args).ok();
    diag_file.flush().ok();

    writeln!(diag_file, "Initializing env_logger...").ok();
    diag_file.flush().ok();
    // Initialize logging (use try_init for FFI compatibility)
    let _ = env_logger::try_init();
    writeln!(diag_file, "✅ env_logger initialized").ok();
    diag_file.flush().ok();

    writeln!(diag_file, "Parsing command line arguments...").ok();
    diag_file.flush().ok();
    if args.len() < 6 {
        writeln!(diag_file, "❌ ERROR: Not enough arguments! Got {} args, need 6", args.len()).ok();
        diag_file.flush().ok();
        eprintln!("{} Usage: {} <config_file> <status_file> <result_file> <session_file> <hash_file>", "❌".red(), args[0]);
        std::process::exit(1);
    }
    writeln!(diag_file, "✅ Got {} arguments", args.len()).ok();
    diag_file.flush().ok();

    let config_file = &args[1];
    let status_file = &args[2];
    let result_file = &args[3];
    let session_file = &args[4];
    let hash_file = &args[5];

    println!("{}", "=".repeat(80).blue());
    println!("🚀 {} - Production FTP Uploader v1.0.0", "FTP".bold().green());
    println!("{}", "=".repeat(80).blue());
    println!("📁 Config file: {}", config_file.cyan());
    println!("📊 Status file: {}", status_file.cyan());
    println!("✅ Result file: {}", result_file.cyan());
    println!("🕐 Started at: {}", Utc::now().format("%Y-%m-%d %H:%M:%S UTC"));
    println!("{}", "=".repeat(80).blue());

    // Read config
    let mut config: FTPConfig = serde_json::from_str(&fs::read_to_string(config_file)?)?;
    
    // Convert sync_interval from milliseconds to seconds (Swift sends milliseconds)
    config.sync_interval = config.sync_interval / 1000.0;
    
    // Convert stabilization_interval from milliseconds to seconds (Swift sends milliseconds)
    config.stabilization_interval = config.stabilization_interval / 1000;
    
    info!("🔧 Config loaded: {}@{}:{}", config.username, config.server_address, config.port);
    config_log(&config, &format!("🔧 {}@{}:{}", config.username.green(), config.server_address.cyan(), config.port.to_string().cyan()));
    
    // Create shutdown file path for this config
    let shutdown_file = format!("{}.shutdown", status_file);
    
    // Helper function to check shutdown status
    let check_shutdown = || {
        if shutdown_flag.load(Ordering::SeqCst) {
            config_log(&config, &format!("{} Shutdown signal received, exiting gracefully", "🛑".red()));
            true
        } else {
            false
        }
    };
    
    // Helper function to check if this specific config should stop
    let check_config_stop = || {
        if fs::metadata(&shutdown_file).is_ok() {
            config_log(&config, &format!("{} Shutdown file detected for config {}, stopping this config", "⏸️".yellow(), config.config_name));
            true
        } else {
            false
        }
    };
    
    // Log the sync settings
    config_log(&config, &format!("🔧 Sync Interval: {}s (how often to run sync cycles)", config.sync_interval.to_string().green()));
    config_log(&config, &format!("🔧 Stabilization Interval: {}s (file stabilization wait)", config.stabilization_interval.to_string().yellow()));
    config_log(&config, &format!("🔧 Upload Aggressiveness: {} parallel connections", config.upload_aggressiveness.to_string().cyan()));
    config_log(&config, &format!("🔧 Auto-tune Aggressiveness: {}", if config.auto_tune_aggressiveness { "enabled".green() } else { "disabled".red() }));

    // Send sync interval as notification so it appears in UI
    let _ = send_notification(&config, "info", &format!("🔧 Sync Interval: {} seconds", config.sync_interval), None, None);

    if config.sync_interval <= 0.0 {
        config_log(&config, &format!("⚠️ {} Sync interval is 0 - will run once and exit", "WARNING:".red()));
        let _ = send_notification(&config, "warning", "⚠️ Sync interval is 0 - will run once and exit", None, None);
    } else {
        config_log(&config, &format!("🔄 {} Will run continuously every {}s until stopped", "CONTINUOUS MODE:".green(), config.sync_interval.to_string().green()));
        let _ = send_notification(&config, "info", &format!("🔄 Continuous mode: will loop every {} seconds", config.sync_interval), None, None);
    }

    // Check if shutdown file exists at startup (debugging)
    if fs::metadata(&shutdown_file).is_ok() {
        config_log(&config, &format!("⚠️ {} SHUTDOWN FILE STILL EXISTS AT STARTUP - this should not happen!", "WARNING:".red()));
        config_log(&config, &format!("⚠️ Shutdown file path: {}", shutdown_file.yellow()));
        config_log(&config, &format!("⚠️ This will cause immediate exit - Swift should have cleared this file!"));
    } else {
        config_log(&config, &format!("✅ {} No shutdown file detected - ready to start continuous sync", "CLEAR:".green()));
    }

    // Send initial status
    send_status(status_file, &config, "Starting", "", 0.0, None)?;

    // Initialize connection manager for retry logic
    let connection_manager = Arc::new(ConnectionManager::new());

    // Initialize SQLite database for hash tracking
    // Use FTP_DATA_DIR environment variable for sandboxed apps, fallback to tmp dir
    let data_dir_str = std::env::var("FTP_DATA_DIR").unwrap_or_else(|_| {
        // Fallback: try to construct Application Support path
        if let Ok(home) = std::env::var("HOME") {
            format!("{}/Library/Application Support/FTPUploader", home)
        } else {
            "/tmp/FTPUploader".to_string()
        }
    });
    let data_dir = PathBuf::from(data_dir_str);

    // Ensure data directory exists
    if let Err(e) = std::fs::create_dir_all(&data_dir) {
        config_log(&config, &format!("⚠️  Failed to create data directory: {}", e));
    }

    // Use config_id (not session_id) for database path so it persists across restarts
    let db_path = data_dir.join(format!("config_{}.db", config.config_id));

    config_log(&config, &format!("🗄️  Initializing SQLite database at: {}", db_path.display()));
    if let Err(e) = db::init_database(&db_path) {
        config_log(&config, &format!("⚠️  Database initialization failed: {}, falling back to legacy hash files", e));
    } else {
        config_log(&config, &format!("✅ Database initialized successfully"));

        // Attempt to migrate from legacy hash file if it exists
        if let Ok(hash_file_path) = get_hash_file_path(hash_file) {
            if hash_file_path.exists() {
                config_log(&config, &format!("🔄 Found legacy hash file, attempting migration..."));
                match db::migrate_from_hash_file(&config.session_id, &hash_file_path) {
                    Ok(migrated) => {
                        if migrated > 0 {
                            config_log(&config, &format!("✅ Migrated {} entries from legacy hash file", migrated));
                        }
                    }
                    Err(e) => {
                        config_log(&config, &format!("⚠️  Migration failed: {}", e));
                    }
                }
            }
        }
    }

    // Main continuous processing loop
    let mut iteration = 0;
    loop {
        // Check if shutdown signal received (Ctrl-C)
        if check_shutdown() {
            config_log(&config, &format!("{} Ctrl-C received, exiting completely", "🛑".red()));
            break;
        }
        
        // Check if this specific config should stop
        if check_config_stop() {
            config_log(&config, &format!("{} Config {} stopped, exiting gracefully", "⏸️".yellow(), config.config_name));
            break;
        }
        
        iteration += 1;
        let _start_time = Instant::now();
        let start_datetime = Utc::now();
        
        println!("🔄 RUST DEBUG: LOOP CONTINUED - starting iteration {} at {}", iteration, start_datetime.format("%H:%M:%S"));
        config_log(&config, &format!("{} Starting iteration {} at {}", "🔄".blue(), iteration, start_datetime.format("%H:%M:%S")));
        
        // Process one iteration
        let result = process_single_iteration(
            &config,
            status_file,
            result_file,
            session_file,
            hash_file,
            &shutdown_file,
            &shutdown_flag,
            &connection_manager,
            iteration
        );
        
        match result {
            Ok(_) => {
                config_log(&config, &format!("{} Iteration {} completed successfully", "✅".green(), iteration));
            }
            Err(e) => {
                config_log(&config, &format!("{} Iteration {} failed: {}", "❌".red(), iteration, e));
                // Don't exit on errors, just log and continue to next iteration
            }
        }
        
        // Check if we should continue or exit
        config_log(&config, &format!("🔍 DEBUG: Checking sync_interval: {}", config.sync_interval));
        if config.sync_interval <= 0.0 {
            config_log(&config, &format!("{} No sync interval configured ({}), exiting after one iteration", "⏹️".yellow(), config.sync_interval));
            break;
        }
        
        config_log(&config, &format!("✅ DEBUG: Sync interval is positive ({}s), loop will continue", config.sync_interval));

        // Send notification about looping
        let _ = send_notification(&config, "info", &format!("⏳ Waiting {} seconds before next sync cycle...", config.sync_interval), None, None);

        // Wait for the configured sync interval before next iteration
        config_log(&config, &format!("{} Waiting {} seconds before next sync cycle...", "⏳".yellow(), config.sync_interval));
        config_log(&config, &format!("{} Process will stay alive and continue monitoring", "🔄".blue()));
        
        // Check for shutdown during interval wait - check every 100ms for faster response
        let wait_ms = (config.sync_interval * 1000.0) as u64; // Convert to milliseconds
        let mut elapsed_ms = 0;
        
        config_log(&config, &format!("🔍 DEBUG: Starting interval wait for {} ms", wait_ms));
        
        while elapsed_ms < wait_ms {
            if shutdown_flag.load(Ordering::SeqCst) {
                config_log(&config, &format!("{} Shutdown signal received during interval wait, exiting gracefully", "🛑".red()));

                // Cleanup: Remove our entry from monitor files before exiting
                println!("🧹 CLEANUP: Removing monitor entries (shutdown during wait)");
                let _ = cleanup_all_monitor_files(&config);

                return Ok(());
            }
            if fs::metadata(&shutdown_file).is_ok() {
                config_log(&config, &format!("{} Shutdown file detected during interval wait, exiting gracefully", "🛑".red()));

                // Cleanup: Remove our entry from monitor files before exiting
                println!("🧹 CLEANUP: Removing monitor entries (config stopped during wait)");
                let _ = cleanup_all_monitor_files(&config);

                return Ok(());
            }
            std::thread::sleep(std::time::Duration::from_millis(100));
            elapsed_ms += 100;
        }
        
        config_log(&config, &format!("✅ DEBUG: Interval wait completed, continuing to next iteration"));
        
        // Check shutdown flag and shutdown file again after interval
        if shutdown_flag.load(Ordering::SeqCst) {
            config_log(&config, &format!("{} Shutdown signal received after interval, exiting gracefully", "🛑".red()));
            break;
        }
        // Note: We don't check for shutdown file here because it would prevent the loop from working
        // The shutdown file is only checked during the interval wait, not after
        
        // Continue to next iteration
        
        // Continue to next iteration
        config_log(&config, &format!("🔄 Starting next iteration - will rescan directories for new files"));
        config_log(&config, &format!("🔍 DEBUG: About to continue to iteration {}", iteration + 1));
        println!("🔍 RUST DEBUG: About to continue to iteration {}", iteration + 1);
        println!("🔄 RUST DEBUG: LOOP WILL CONTINUE - about to hit the end of loop body");
    }

    println!("🔄 RUST DEBUG: LOOP ENDED - process exiting");
    config_log(&config, &format!("{} Main loop ended, performing cleanup...", "🏁".blue()));

    // Cleanup: Remove our entry from monitor files in all directories
    println!("🧹 CLEANUP: Removing monitor entries from all directories");
    match cleanup_all_monitor_files(&config) {
        Ok(_) => {
            println!("✅ CLEANUP: Successfully removed monitor entries");
            config_log(&config, "✅ Cleanup completed successfully");
        }
        Err(e) => {
            println!("⚠️  CLEANUP: Failed to remove monitor entries: {}", e);
            config_log(&config, &format!("⚠️ Cleanup warning: {}", e));
        }
    }

    Ok(())
}

// New function to handle a single iteration of the main loop
fn process_single_iteration(
    config: &FTPConfig,
    status_file: &str,
    result_file: &str,
    session_file: &str,
    hash_file: &str,
    shutdown_file: &str,
    shutdown_flag: &Arc<AtomicBool>,
    connection_manager: &Arc<ConnectionManager>,
    iteration: usize
) -> Result<(), Box<dyn std::error::Error>> {
    
    // Connect to FTP for directory scanning
    config_log(&config, &format!("{} Connecting to FTP server...", "🔌".blue()));
    send_status(status_file, &config, "Connecting", "", 0.1, None)?;
    
    let mut ftp = match ftp::FtpStream::connect((config.server_address.clone(), config.port)) {
        Ok(stream) => {
            config_log(&config, &format!("{} Connected to {}:{}", "✅".green(), config.server_address, config.port));
            stream
        },
        Err(e) => {
            let error_msg = format!("Connection failed: {}", e);
            error!("{}", error_msg);
            
            // Analyze error and determine retry strategy
            let (is_server_rejection, retry_delay) = connection_manager.record_failure(&error_msg, config.sync_interval);
            let failure_count = connection_manager.get_failure_count();
            
            if is_server_rejection {
                config_log(&config, &format!("{} SERVER REJECTION detected (attempt {}): {}", "🚫".red(), failure_count, error_msg));
                config_log(&config, &format!("{} Server may have connection limits - using exponential backoff", "⚠️".yellow()));
            } else {
                config_log(&config, &format!("{} Connection failed (attempt {}): {}", "❌".red(), failure_count, error_msg));
            }
            
            config_log(&config, &format!("{} Waiting {:.1} seconds before retry...", "⏳".yellow(), retry_delay.as_secs_f64()));
            send_status(status_file, &config, "Error", &format!("Connection failed (attempt {}), retrying in {:.0}s", failure_count, retry_delay.as_secs_f64()), 0.0, None)?;
            write_result(result_file, &config, false, &error_msg, 0)?;

            // Only send notification if this is the 2nd+ failure (don't spam on initial connection)
            if failure_count >= 2 {
                send_notification(&config, "warning", &format!("Connection failed (attempt {}), retrying...", failure_count), None, None)?;
            }

            std::thread::sleep(retry_delay);
            return Ok(()); // Return Ok to continue to next iteration
        }
    };

    if let Err(e) = ftp.login(&config.username, &config.password) {
        let error_msg = format!("Login failed: {}", e);
        error!("{}", error_msg);
        
        // Analyze error and determine retry strategy
        let (is_server_rejection, retry_delay) = connection_manager.record_failure(&error_msg, config.sync_interval);
        let failure_count = connection_manager.get_failure_count();
        
        if is_server_rejection {
            config_log(&config, &format!("{} LOGIN REJECTION detected (attempt {}): {}", "🚫".red(), failure_count, error_msg));
            config_log(&config, &format!("{} Server may be rejecting logins - using exponential backoff", "⚠️".yellow()));
        } else {
            config_log(&config, &format!("{} Login failed (attempt {}): {}", "❌".red(), failure_count, error_msg));
        }
        
        config_log(&config, &format!("{} Waiting {:.1} seconds before retry...", "⏳".yellow(), retry_delay.as_secs_f64()));
        send_status(status_file, &config, "Error", &format!("Login failed (attempt {}), retrying in {:.0}s", failure_count, retry_delay.as_secs_f64()), 0.0, None)?;

        // Send error notification via FFI callback to Swift
        send_notification(&config, "error", &error_msg, None, None)?;

        write_result(result_file, &config, false, &error_msg, 0)?;
        
        std::thread::sleep(retry_delay);
        return Ok(()); // Return Ok to continue to next iteration
    }

    // Record successful connection
    connection_manager.record_success();
    let failure_count = connection_manager.get_failure_count();
    
    config_log(&config, &format!("{} Logged in as {} (connection restored after {} failures)",
        "🔑".green(), config.username.green(), failure_count));
    send_status(status_file, &config, "Connected", "", 0.2, None)?;

    // Send structured notification
    send_notification(&config, "info", &format!("Connected to {}", config.server_address), None, None)?;

    // Scan local directory for files to upload
    let local_files = scan_local_directory_for_files(&config, status_file, shutdown_file, shutdown_flag, iteration)?;

    config_log(&config, &format!("🔍 DEBUG: Local scan found {} files to upload", local_files.len()));
    // Only show first 10 files to avoid log flooding
    for (i, (relative_path, _full_path, size)) in local_files.iter().enumerate() {
        if i < 10 {
            config_log(&config, &format!("  📄 Found file: {} ({} bytes)", relative_path.cyan(), size));
        } else if i == 10 {
            config_log(&config, &format!("  ... and {} more files", local_files.len() - 10));
            break;
        }
    }

    // Convert to format expected by process_files: (filename, local_path)
    // For uploads, we'll use the relative path as the remote filename
    let all_files: Vec<(String, String)> = local_files.iter()
        .map(|(rel_path, full_path, _)| (rel_path.clone(), full_path.to_string_lossy().to_string()))
        .collect();

    config_log(&config, &format!("🔍 DEBUG: Files will be moved to FTPU-Sent after successful upload"));
    
    if all_files.is_empty() {
        config_log(&config, &format!("{} No files found to process, will wait for interval and retry", "⚠️".yellow()));

        // Send structured notification
        send_notification(&config, "info", "No new files found", None, None)?;

        // Close the main FTP connection since we're not using it
        ftp.quit().ok();

        // Write result for this iteration
        write_result(result_file, &config, true, "No files found, completed scan", 0)?;

        // Send completion status
        send_status(status_file, &config, "Complete", "No files found, will retry after interval", 1.0, None)?;

        config_log(&config, &format!("{} SCAN INTERVAL COMPLETE!", "✅".green()));
        return Ok(());
    }
    
    // Process files if any were found
    config_log(&config, &format!("========================================"));
    config_log(&config, &format!("{} STARTING UPLOAD PHASE - {} files to process", "🚀🚀🚀".green(), all_files.len()));
    config_log(&config, &format!("========================================"));

    // Check if we should reduce parallel connections due to server limits
    let max_connections = if connection_manager.should_reduce_connections() {
        let reduced = (config.upload_aggressiveness as usize / 4).max(1); // Reduce to 1/4 of configured aggressiveness
        config_log(&config, &format!("{} Server limit detected - reducing from {} to {} parallel connections",
            "🔧".yellow(), config.upload_aggressiveness, reduced));
        reduced
    } else {
        // TODO: Implement auto-tuning logic using config.auto_tune_aggressiveness
        // For now, just use the configured aggressiveness
        config.upload_aggressiveness as usize // Use configured aggressiveness
    };

    config_log(&config, &format!("{} Using {} parallel connections for upload", "🔧".blue(), max_connections));

    let files_processed = process_files(
        &mut ftp, 
        &all_files, 
        &config, 
        status_file, 
        session_file, 
        hash_file, 
        shutdown_file,
        shutdown_flag,
        connection_manager,
        max_connections
    )?;
    
    // Close FTP connection
    ftp.quit().ok();
    
    // Write final result
    write_result(result_file, &config, true, "FTP process completed successfully", files_processed)?;
    
    config_log(&config, &format!("{} SCAN INTERVAL COMPLETE!", "✅".green()));
    Ok(())
}

// Function to scan local directory for files to upload
fn scan_local_directory_for_files(
    config: &FTPConfig,
    status_file: &str,
    shutdown_file: &str,
    shutdown_flag: &Arc<AtomicBool>,
    _iteration: usize
) -> Result<Vec<(String, PathBuf, u64)>, Box<dyn std::error::Error>> {

    config_log(&config, &format!("{} Scanning local directory for files to upload...", "🔍".blue()));
    let mut all_files: Vec<(String, PathBuf, u64)> = Vec::new();

    let local_dir = PathBuf::from(&config.local_source_path);

    // Check for shutdown
    if shutdown_flag.load(Ordering::SeqCst) || fs::metadata(shutdown_file).is_ok() {
        config_log(&config, &format!("{} Shutdown during directory scanning, exiting gracefully", "🛑".red()));
        return Ok(all_files);
    }

    let progress = 0.3;
    config_log(&config, &format!("{} Scanning local directory: {}", "📁".blue(), config.local_source_path.cyan()));
    send_status(status_file, &config, "Scanning", &config.local_source_path, progress, None)?;

    // Send structured notification
    send_notification(&config, "info", &format!("Scanning {}", config.local_source_path), None, None)?;

    // Check if local directory exists
    if !local_dir.exists() {
        warn!("Local directory not found: {}", config.local_source_path);
        config_log(&config, &format!("{} Local directory not found: {}", "⚠️".yellow(), config.local_source_path.red()));
        send_notification(&config, "warning", &format!("Directory not found: {}", config.local_source_path), None, None)?;
        return Ok(all_files);
    }

    // Recursively scan local directory
    fn scan_dir_recursive(dir: &PathBuf, base_dir: &PathBuf, files: &mut Vec<(String, PathBuf, u64)>, config: &FTPConfig) -> std::io::Result<()> {
        config_log(&config, &format!("   📂 Scanning: {}", dir.display()));

        if let Ok(entries) = fs::read_dir(dir) {
            let mut file_count = 0;
            let mut dir_count = 0;
            let mut skipped_count = 0;

            for entry in entries.flatten() {
                let path = entry.path();
                let filename = path.file_name()
                    .map(|n| n.to_string_lossy().to_string())
                    .unwrap_or_default();

                // Skip hidden files and FTPU-Sent directory
                if filename.starts_with('.') || filename == "FTPU-Sent" {
                    skipped_count += 1;
                    if filename == "FTPU-Sent" {
                        config_log(&config, &format!("   ⏭️ Skipping FTPU-Sent directory"));
                    }
                    continue;
                }

                if path.is_dir() {
                    dir_count += 1;
                    // Recursively scan subdirectories
                    scan_dir_recursive(&path, base_dir, files, config)?;
                } else if path.is_file() {
                    // Get file size
                    if let Ok(metadata) = fs::metadata(&path) {
                        let size = metadata.len();

                        // Calculate relative path from base directory
                        let relative_path = path.strip_prefix(base_dir)
                            .map(|p| p.to_string_lossy().to_string())
                            .unwrap_or_else(|_| filename.clone());

                        files.push((relative_path, path.clone(), size));
                        file_count += 1;
                    }
                }
            }

            if file_count > 0 || dir_count > 0 {
                config_log(&config, &format!("   📊 In {}: {} files, {} subdirs, {} skipped",
                    dir.file_name().map(|n| n.to_string_lossy().to_string()).unwrap_or_else(|| "root".to_string()),
                    file_count, dir_count, skipped_count));
            }
        } else {
            config_log(&config, &format!("   ⚠️ Could not read directory: {}", dir.display()));
        }
        Ok(())
    }

    scan_dir_recursive(&local_dir, &local_dir, &mut all_files, config)?;

    config_log(&config, &format!("{} Found {} files to upload", "📊".blue(), all_files.len()));
    send_notification(&config, "info", &format!("Found {} files", all_files.len()), None, None)?;

    Ok(all_files)
}

/* Legacy download function - commented out for upload conversion
fn scan_directories_for_files(
    ftp: &mut ftp::FtpStream,
    config: &FTPConfig,
    status_file: &str,
    shutdown_file: &str,
    shutdown_flag: &Arc<AtomicBool>,
    iteration: usize
) -> Result<Vec<(String, String)>, Box<dyn std::error::Error>> {

    config_log(&config, &format!("{} Scanning directories for files...", "🔍".blue()));
    let mut all_files = Vec::new();

    // For upload mode, we scan local directory instead
    // This legacy function is kept for reference but should not be called
    let remote_dir = &config.remote_destination;

    // Check for shutdown during directory scanning
    if shutdown_flag.load(Ordering::SeqCst) {
        if fs::metadata(shutdown_file).is_ok() {
            config_log(&config, &format!("{} Config {} stopped during directory scanning, skipping this directory", "⏸️".yellow(), config.config_name));
        } else {
            config_log(&config, &format!("{} Shutdown during directory scanning, exiting gracefully", "🛑".red()));
            return Ok(all_files); // Return what we have so far
        }
    }

    // Change to remote destination directory
    if let Err(e) = ftp.cwd(&config.remote_destination) {
        config_log(&config, &format!("⚠️ Warning: Failed to change to remote directory: {}", e));
    }

    let progress = 0.3;
    config_log(&config, &format!("{} Scanning directory: {}", "📁".blue(), remote_dir.cyan()));
    send_status(status_file, &config, "Scanning", remote_dir, progress, None)?;

        // Send structured notification
        send_notification(&config, "info", &format!("Scanning {}", remote_dir), None, None)?;

        if let Err(_) = ftp.cwd(remote_dir) {
            warn!("Directory not found: {}", remote_dir);
            config_log(&config, &format!("{} Directory not found: {}", "⚠️".yellow(), remote_dir.red()));
            send_status(status_file, &config, "Warning", &format!("Directory not found: {}", remote_dir), progress, None)?;

            // Send structured notification
            send_notification(&config, "warning", &format!("Directory not found: {}", remote_dir), None, None)?;
            continue;
        }

        // Get directory listing first (we need this for both monitor file and regular files)
        let files = match ftp.list(Some(remote_dir)) {
            Ok(files) => files,
            Err(_) => {
                warn!("Failed to list directory: {}", remote_dir);
                config_log(&config, &format!("{} Failed to list directory: {}", "⚠️".yellow(), remote_dir.red()));
                send_status(status_file, &config, "Warning", &format!("Failed to list: {}", remote_dir), progress, None)?;
                continue;
            }
        };

        // Phase 1: Check for _monitored.json file (read-only detection)
        // Only check every 3 iterations (e.g., every 15 seconds with 5-second sync interval)
        // This reduces FTP server load since monitor conflicts don't change frequently
        if iteration % 3 == 1 {
            // Look for it in the file listing first, then retrieve it if found
            if let Some(monitor_file) = read_monitor_file(ftp, remote_dir, &files) {
                // Get our hostname and profile name to exclude ourselves from conflict detection
                let our_hostname = get_hostname();
                let our_profile = &config.config_name;

                println!("🔍 CALLING detect_monitor_conflicts with upload_mode='{}' hostname='{}' profile='{}'",
                    "upload", our_hostname, our_profile);

                // Detect conflicts based on current upload mode (excluding ourselves)
                if let Some((conflict_level, message)) = detect_monitor_conflicts(&monitor_file, &"upload", &our_hostname, our_profile, remote_dir) {
                    config_log(&config, &message);

                    // Send notification to Swift UI as "monitor_warning" type
                    // This ensures monitor conflicts don't affect connection status
                    send_notification(&config, "monitor_warning", &message, None, None)?;
                } else {
                    // No conflicts detected - send a clear notification
                    // This ensures the warning banner is removed when conflicts resolve
                    println!("✅ No monitor conflicts detected - sending clear notification");
                    send_notification(&config, "monitor_warning", "clear", None, None)?;
                }
            }
        }

        // Phase 2: Skip _monitored.json for uploader (was used for multi-client coordination in downloader)
        // let _ = write_monitor_file(ftp, remote_dir, config, &files);

        // Filter files and collect with directory info
        let filtered: Vec<(String, String)> = files.iter()
            .filter_map(|entry| {
                let trimmed = entry.trim();
                if trimmed.is_empty() {
                    return None;
                }
                
                // Detect listing format based on entry structure (works for Rumpus and other servers)
                let (is_directory, filename) = if trimmed.starts_with('d') {
                    // UNIX-style: drwxr-xr-x 2 user group 4096 Jan 1 12:00 dirname
                    let parts: Vec<&str> = trimmed.split_whitespace().collect();
                    if parts.len() >= 9 {
                        let is_dir = parts[0].starts_with('d');
                        let name = parts[8..].join(" ");
                        (is_dir, name)
                    } else {
                        // Fallback: if it doesn't start with 'd', assume it's a file
                        (false, trimmed.to_string())
                    }
                } else if trimmed.starts_with('-') {
                    // UNIX-style file listing: various formats
                    // Format 1: -rw-r--r-- 1 user group 1234 Oct 26 12:00 filename.txt
                    // Format 2: -rw-rw-rw- 0 3080164 3080164 Jul 11 23:06 filename with spaces.txt
                    let parts: Vec<&str> = trimmed.split_whitespace().collect();

                    // Find where the filename starts by looking for the time field
                    // Time is usually in format HH:MM or YYYY (for old files)
                    let mut filename_start_idx = 8; // Default for standard format

                    for (i, part) in parts.iter().enumerate() {
                        if i >= 5 && (part.contains(':') || (part.len() == 4 && part.chars().all(|c| c.is_digit(10)))) {
                            // Found time field (HH:MM or YYYY), filename starts after it
                            filename_start_idx = i + 1;
                            break;
                        }
                    }

                    if parts.len() > filename_start_idx {
                        // Join all parts from filename_start_idx onwards (handles spaces)
                        let name = parts[filename_start_idx..].join(" ");
                        (false, name)
                    } else if parts.len() >= 6 {
                        // Fallback: last part is filename
                        let name = parts[parts.len() - 1];
                        (false, name.to_string())
                    } else {
                        (false, trimmed.to_string())
                    }
                } else if trimmed.contains(' ') && !trimmed.contains('\t') {
                    // Mac OS-style or simple format: check if it looks like a directory
                    let parts: Vec<&str> = trimmed.split_whitespace().collect();
                    if parts.len() >= 2 {
                        // Check if first part looks like permissions, size, or date
                        let first_part = parts[0];
                        let is_dir = first_part.starts_with('d') || 
                                    first_part.parse::<u64>().is_ok() || // Size
                                    first_part.contains('-') || // Date
                                    first_part.contains('/'); // Date
                        
                        if is_dir {
                            (true, parts[1..].join(" "))
                        } else {
                            (false, trimmed.to_string())
                        }
                    } else {
                        // Single item - assume file if no spaces
                        (false, trimmed.to_string())
                    }
                } else {
                    // Simple format: just the name
                    // Check if it looks like a directory (no extension, no dots)
                    let is_dir = !trimmed.contains('.') && !trimmed.contains('\t');
                    (is_dir, trimmed.to_string())
                };
                
                // Skip directories, hidden files, system files, and monitor coordination file
                if is_directory ||
                   filename == "_monitored.json" ||      // Monitor coordination file (never process/delete)
                   filename.starts_with('.') ||
                   filename.ends_with(".filepart") ||
                   filename.starts_with("._") ||  // macOS resource fork files
                   filename.starts_with("Thumbs.db") ||  // Windows thumbnail cache
                   filename.starts_with(".DS_Store") ||  // macOS system files
                   filename.starts_with(".Trash") ||     // macOS trash
                   filename.starts_with("desktop.ini") || // Windows system files
                   filename.starts_with("~$") ||         // Temporary Office files
                   filename.ends_with(".tmp") ||         // Temporary files
                   filename.ends_with(".temp") {         // Temporary files
                    return None;
                }
                
                Some((filename, remote_dir.clone()))
            })
            .collect();

        let file_count = filtered.len();
        all_files.extend(filtered);
        config_log(&config, &format!("{} Found {} files in {}", "📊".green(), file_count.to_string().green(), remote_dir.cyan()));
        send_status(status_file, &config, "Found files", &format!("{} files in {}", file_count, remote_dir), progress + 0.1, None)?;

        // Send structured notification
        if file_count > 0 {
            send_notification(&config, "info", &format!("Found {} files in {}", file_count, remote_dir), None, None)?;
        }
    }

    config_log(&config, &format!("{} Total files to process: {}", "🎯".blue(), all_files.len().to_string().bold().green()));

    // Mark all discovered files as "seen" in the database
    let scan_timestamp = Utc::now().timestamp();
    config_log(&config, &format!("🗄️  Marking {} files as seen in database (timestamp: {})", all_files.len(), scan_timestamp));

    for (filename, remote_dir) in &all_files {
        // Use config_id (not session_id) so tracking works across restarts
        if let Err(e) = db::mark_file_seen(&config.config_id, remote_dir, filename) {
            config_log(&config, &format!("⚠️  Failed to mark file as seen: {}/{}: {}", remote_dir, filename, e));
        }
    }

    // Cleanup stale files that haven't been seen in this scan
    // Files not seen in the last 60 seconds are considered stale
    let cleanup_threshold = scan_timestamp - 60;
    // Use config_id (not session_id) so cleanup works across restarts
    match db::cleanup_stale_files(&config.config_id, cleanup_threshold) {
        Ok(deleted_count) => {
            if deleted_count > 0 {
                config_log(&config, &format!("🧹 Cleaned up {} files that no longer exist on server", deleted_count));
            }
        }
        Err(e) => {
            config_log(&config, &format!("⚠️  Failed to cleanup stale files: {}", e));
        }
    }

    Ok(all_files)
}
*/ // End of commented-out legacy scan_directories_for_files

// Function to process files
fn process_files(
    _ftp: &mut ftp::FtpStream, // Unused - each thread creates own connection
    all_files: &[(String, String)],
    config: &FTPConfig,
    status_file: &str,
    session_file: &str,
    hash_file: &str,
    shutdown_file: &str,
    shutdown_flag: &Arc<AtomicBool>,
    connection_manager: &Arc<ConnectionManager>,
    max_parallel_connections: usize
) -> Result<usize, Box<dyn std::error::Error>> {
    
    // Initialize session state tracking
    let session_state = Arc::new(Mutex::new(SessionState::new()));
    
    // Hash-based file discovery for keep mode
    let files_to_process = all_files.to_vec();

    // Load existing hashes for keep mode (used by worker threads later)
    let existing_hashes = if "upload" == "keep" {
        config_log(&config, &format!("🔍 Keep mode enabled - checking existing file hashes..."));

        // Try database first, fallback to hash files
        // Use config_id (not session_id) so hashes persist across restarts
        match db::load_hashes_for_config(&config.config_id) {
            Ok(existing_hashes) => {
                config_log(&config, &format!("📋 Loaded {} existing file hashes from database", existing_hashes.len()));

                // Filter out files that haven't changed based on hash comparison
                let _original_count = files_to_process.len();

                // For keep mode, we need to check each file's current hash against existing hashes
                // This will be done during the parallel processing phase
                config_log(&config, &format!("🔍 Will check {} files against {} existing hashes during processing",
                    files_to_process.len(), existing_hashes.len()));

                existing_hashes
            }
            Err(e) => {
                config_log(&config, &format!("⚠️ Failed to load hashes from database: {}, trying legacy hash file", e));

                // Fallback to legacy hash file loading
                match get_hash_file_path(hash_file) {
                    Ok(hash_file_path) => {
                        let existing_hashes = load_existing_hashes(&hash_file_path);
                        config_log(&config, &format!("📋 Loaded {} existing file hashes from legacy file", existing_hashes.len()));
                        config_log(&config, &format!("🔍 Will check {} files against {} existing hashes during processing",
                            files_to_process.len(), existing_hashes.len()));
                        existing_hashes
                    }
                    Err(e) => {
                        config_log(&config, &format!("⚠️ Failed to create hash file path: {}, continuing without hash tracking", e));
                        std::collections::HashMap::new()
                    }
                }
            }
        }
    } else {
        config_log(&config, &format!("🗑️ Delete mode enabled - will only process files that still exist on server"));
        std::collections::HashMap::new()
    };
    
    send_status(status_file, &config, "Preparing parallel processing", &format!("{} total files", files_to_process.len()), 0.5, None)?;

    // Process files in parallel using rayon
    let files_processed = Arc::new(AtomicUsize::new(0));
    let status_sender = Arc::new(Mutex::new(status_file.to_string()));
    let config_arc = Arc::new(config.clone());
    let status_sender_clone = status_sender.clone();
    let config_arc_clone = config_arc.clone();

    // Create a channel for status updates from parallel workers
    let (status_tx, status_rx) = channel::unbounded::<StatusUpdate>();
    
    // Spawn status receiver thread
    let status_receiver = std::thread::spawn(move || {
        while let Ok(status_update) = status_rx.recv() {
            if let Ok(status_file) = status_sender.lock() {
                
                // Handle FileComplete messages specially - log them instead of overwriting status
                if status_update.stage == "FileComplete" {
                    // Log the completion message (this will be picked up by Swift)
                    config_log(&config_arc, &status_update.filename);
                    
                    // Still send a status update but with a different stage to avoid overwriting
                    let status = FTPStatus {
                        config_id: config_arc.config_id.clone(),
                        stage: "Processing".to_string(), // Don't overwrite main status
                        filename: "Files uploading...".to_string(),
                        progress: status_update.progress,
                        timestamp: std::time::SystemTime::now()
                            .duration_since(std::time::UNIX_EPOCH)
                            .unwrap_or_default()
                            .as_secs(),
                        file_size: status_update.file_size,
                        upload_speed_mbps: None,
                        upload_time_secs: None,
                    };
                    
                    if let Ok(status_json) = serde_json::to_string(&status) {
                        let _ = fs::write(&**status_file, status_json);
                    }
                } else {
                    // Handle normal status updates
                    let status = FTPStatus {
                        config_id: config_arc.config_id.clone(),
                        stage: status_update.stage.clone(),
                        filename: status_update.filename.clone(),
                        progress: status_update.progress,
                        timestamp: std::time::SystemTime::now()
                            .duration_since(std::time::UNIX_EPOCH)
                            .unwrap_or_default()
                            .as_secs(),
                        file_size: status_update.file_size,
                        upload_speed_mbps: None, // Will be filled by specific status updates
                        upload_time_secs: None,  // Will be filled by specific status updates
                    };
                    
                    if let Ok(status_json) = serde_json::to_string(&status) {
                        let _ = fs::write(&**status_file, status_json);
                    }
                }
            }
        }
    });

    // Create custom thread pool with exactly max_parallel_connections threads
    // This ensures we respect the user's download aggressiveness setting
    let pool = rayon::ThreadPoolBuilder::new()
        .num_threads(max_parallel_connections)
        .build()
        .map_err(|e| format!("Failed to create thread pool: {}", e))?;

    config_log(&config, &format!("{} Starting parallel processing with {} worker threads...", "⚡".blue(), max_parallel_connections.to_string().green()));
    config_log(&config, &format!("{}", "=".repeat(80).blue()));

    // PHASE 1: Parallel stabilization monitoring (if enabled)
    let files_to_upload = if config.stabilization_interval > 0 {
        config_log(&config, &format!("{} Phase 1: Monitoring {} files for stability in PARALLEL ({}s interval)...",
            "🔍".cyan(),
            files_to_process.len().to_string().green(),
            config.stabilization_interval.to_string().yellow()
        ));

        let stabilization_start = std::time::Instant::now();
        let config_clone = config.clone();

        // Monitor all files in PARALLEL for stability using custom thread pool
        // Each thread sleeps for the stabilization interval, so all files are monitored simultaneously
        let stable_files: Vec<(String, String)> = pool.install(|| {
            files_to_process
                .par_iter()
                .filter_map(|(filename, remote_dir)| {
                    // Each thread monitors one file independently
                    // Sleep for stabilization interval to let file finish writing
                    std::thread::sleep(std::time::Duration::from_secs(config_clone.stabilization_interval));

                    // After sleep, file should be stable - return it
                    config_log(&config_clone, &format!("✅ {} stable after {}s wait",
                        filename.green(),
                        config_clone.stabilization_interval
                    ));
                    Some((filename.clone(), remote_dir.clone()))
                })
                .collect()
        });

        let stabilization_elapsed = stabilization_start.elapsed();
        let stabilized_count = stable_files.len();

        config_log(&config, &format!("{} Phase 1 complete: {} files stabilized (took {:.1}s with parallel monitoring)",
            "✅".green(),
            stabilized_count.to_string().green(),
            stabilization_elapsed.as_secs_f64()
        ));

        if stabilized_count == 0 {
            config_log(&config, &format!("{} No stable files to upload, ending session", "⚠️".yellow()));
            return Ok(0);
        }

        config_log(&config, &format!("{}", "=".repeat(80).blue()));
        config_log(&config, &format!("{} Phase 2: Parallel uploading {} stable files with {} worker threads...",
            "⬇️".blue(),
            stabilized_count.to_string().green(),
            max_parallel_connections.to_string().yellow()
        ));

        stable_files
    } else {
        // No stabilization - upload all discovered files immediately
        config_log(&config, &format!("{} Parallel uploading {} files with {} worker threads (no stabilization)...",
            "⬇️".blue(),
            files_to_process.len().to_string().green(),
            max_parallel_connections.to_string().yellow()
        ));
        files_to_process.clone()
    };

    // Use the session state tracking already initialized above
    let session_state_clone = session_state.clone();

    // Use the existing_hashes HashMap loaded earlier (from database or legacy file)
    // This will be cloned for each worker thread in the parallel processing below
    let existing_hashes_clone = existing_hashes.clone();

    // Clone shutdown_file for parallel processing
    let shutdown_file_str = shutdown_file.to_string();

    // Configure parallel processing with adaptive connection limits
    config_log(&config, &format!("🔧 Processing with {} parallel connections", max_parallel_connections));

    // Use custom thread pool with exactly max_parallel_connections threads
    let results: Vec<Result<(), String>> = pool.install(|| {
        files_to_upload
            .par_iter()
            .with_max_len(1) // Each file gets its own task
            .enumerate()
            .map(|(file_index, (filename, remote_dir))| {
        // Check for shutdown before processing each file
        if shutdown_flag.load(Ordering::SeqCst) {
            // Only exit if shutdown file also exists for this config
            if fs::metadata(&shutdown_file_str).is_ok() {
                return Err("Shutdown requested".to_string());
            }
            // If only general shutdown flag is set (Ctrl-C), continue processing this iteration
        }
        
        let thread_id = file_index as u64;
        let file_progress = 0.5 + (0.4 * (file_index as f64) / (files_to_upload.len() as f64));
        let existing_hashes = existing_hashes_clone.clone();
        let session_file = session_file.to_string(); // Convert to String for parallel processing
        let _status_sender_local = status_sender_clone.clone();
        let config_arc_local = config_arc_clone.clone();
        let connection_manager_local = connection_manager.clone();
        
        // DEBUG: Log file processing start
        config_log(&config, &format!("🔍 DEBUG: [Thread-{}] Starting to process {} ({}/{})",
            thread_id, filename.cyan(), (file_index + 1), files_to_upload.len()));
        
        // Send status update
        let _ = status_tx.send(StatusUpdate {
            stage: "Processing".to_string(),
            filename: filename.clone(),
            progress: file_progress,
            thread_id,
            file_size: None,
        });

        // DEBUG: Log FTP connection attempt
        // File processing with connection retry loop
        let max_connection_retries = 3;
        let mut connection_attempt = 0;
        
        let file_result = loop {
            connection_attempt += 1;
            
            config_log(&config, &format!("🔗 DEBUG: [Thread-{}] Attempting FTP connection for {} (attempt {})", 
                thread_id, filename.cyan(), connection_attempt));
            
            // Create new FTP connection for this thread
            let mut ftp = match ftp::FtpStream::connect((config.server_address.clone(), config.port)) {
            Ok(stream) => {
                debug!("[Thread-{}] FTP connection established", thread_id);
                config_log(&config, &format!("✅ DEBUG: [Thread-{}] FTP connection successful for {}", thread_id, filename.green()));
                stream
            },
            Err(e) => {
                let error_msg = format!("Failed to connect: {}", e);
                error!("[Thread-{}] {}", thread_id, error_msg);
                
                // Record connection failure in connection manager
                let (is_server_rejection, retry_delay) = connection_manager_local.record_failure(&error_msg, config.sync_interval);
                let failure_count = connection_manager_local.get_failure_count();
                
                if is_server_rejection {
                    config_log(&config, &format!("{} [Thread-{}] SERVER REJECTION on file connection (attempt {}): {}", 
                        "🚫".red(), thread_id, failure_count, error_msg));
                } else {
                    config_log(&config, &format!("{} [Thread-{}] Connection failed (attempt {}): {}", 
                        "❌".red(), thread_id, failure_count, error_msg));
                }
                
                config_log(&config, &format!("❌ DEBUG: [Thread-{}] FTP connection FAILED for {}: {}", thread_id, filename.red(), e));
                let _ = status_tx.send(StatusUpdate {
                    stage: if is_server_rejection { "Server Rejection" } else { "Connection failed" }.to_string(),
                    filename: filename.clone(),
                    progress: file_progress,
                    thread_id,
                    file_size: None,
                });
                
                // Check if we should retry
                if connection_attempt >= max_connection_retries {
                    config_log(&config, &format!("{} [Thread-{}] Max connection retries ({}) reached for {}, giving up", 
                        "❌".red(), thread_id, max_connection_retries, filename.red()));
                    break Err(format!("Failed to connect after {} attempts: {}", max_connection_retries, e));
                }
                
                config_log(&config, &format!("{} [Thread-{}] Will retry connection for {} in {:.1}s", 
                    "🔄".yellow(), thread_id, filename.yellow(), retry_delay.as_secs_f64()));
                std::thread::sleep(retry_delay);
                continue; // Retry the connection
            }
        };

        // DEBUG: Log login attempt
        config_log(&config, &format!("🔐 DEBUG: [Thread-{}] Attempting FTP login for {}", thread_id, filename.cyan()));
        
        if let Err(e) = ftp.login(&config.username, &config.password) {
            let error_msg = format!("Failed to login: {}", e);
            error!("[Thread-{}] {}", thread_id, error_msg);
            
            // Record login failure in connection manager
            let (is_server_rejection, retry_delay) = connection_manager_local.record_failure(&error_msg, config.sync_interval);
            let failure_count = connection_manager_local.get_failure_count();
            
            if is_server_rejection {
                config_log(&config, &format!("{} [Thread-{}] LOGIN REJECTION on file connection (attempt {}): {}", 
                    "🚫".red(), thread_id, failure_count, error_msg));
                config_log(&config, &format!("{} [Thread-{}] 421 Service not available - will logout and reconnect", 
                    "🔄".yellow(), thread_id));
            } else {
                config_log(&config, &format!("{} [Thread-{}] Login failed (attempt {}): {}", 
                    "❌".red(), thread_id, failure_count, error_msg));
            }
            
            config_log(&config, &format!("❌ DEBUG: [Thread-{}] FTP login FAILED for {}: {}", thread_id, filename.red(), e));
            let _ = status_tx.send(StatusUpdate {
                stage: if is_server_rejection { "Login Rejection" } else { "Login failed" }.to_string(),
                filename: filename.clone(),
                progress: file_progress,
                thread_id,
                file_size: None,
            });
            
            // Clean up connection gracefully
            ftp.quit().ok();
            
            // Check if we should retry
            if connection_attempt >= max_connection_retries {
                config_log(&config, &format!("{} [Thread-{}] Max login retries ({}) reached for {}, giving up", 
                    "❌".red(), thread_id, max_connection_retries, filename.red()));
                break Err(format!("Failed to login after {} attempts: {}", max_connection_retries, e));
            }
            
            config_log(&config, &format!("{} [Thread-{}] Will retry login for {} in {:.1}s", 
                "🔄".yellow(), thread_id, filename.yellow(), retry_delay.as_secs_f64()));
            std::thread::sleep(retry_delay);
            continue; // Retry the connection and login
        }
        
        config_log(&config, &format!("✅ DEBUG: [Thread-{}] FTP login successful for {}", thread_id, filename.green()));

        // DEBUG: Log directory change attempt
        // Note: remote_dir contains the LOCAL file path, we use config.remote_destination for FTP directory
        let ftp_remote_dir = &config.remote_destination;
        config_log(&config, &format!("📁 DEBUG: [Thread-{}] Attempting to change to directory '{}' for {}",
            thread_id, ftp_remote_dir.cyan(), filename.cyan()));

        // Change to directory on FTP server (use remote_destination, not local path)
        if let Err(e) = ftp.cwd(ftp_remote_dir) {
            let error_msg = format!("Failed to change to directory: {}", ftp_remote_dir);
            error!("[Thread-{}] {}", thread_id, error_msg);
            config_log(&config, &format!("❌ DEBUG: [Thread-{}] Server rejected CWD to '{}': {}",
                thread_id, ftp_remote_dir.red(), e));
            return Err(error_msg);
        }

        config_log(&config, &format!("✅ DEBUG: [Thread-{}] Successfully changed to directory '{}'",
            thread_id, ftp_remote_dir.green()));

        // Check file size for stabilization
        // CRITICAL FIX: Set to BINARY mode before SIZE command (some servers reject SIZE in ASCII mode)
        if let Err(e) = ftp.transfer_type(ftp::types::FileType::Binary) {
            config_log(&config, &format!("⚠️ DEBUG: [Thread-{}] Failed to set BINARY mode: {}", thread_id, e));
        } else {
            config_log(&config, &format!("✅ DEBUG: [Thread-{}] Set BINARY mode for SIZE command", thread_id));
        }
        
        // DEBUG: Log before file size check
        config_log(&config, &format!("📏 DEBUG: [Thread-{}] Checking file size for {}", thread_id, filename.cyan()));
        
        let initial_size = match ftp.size(filename) {
            Ok(Some(size)) => {
                debug!("[Thread-{}] File {} size: {} bytes", thread_id, filename, size);
                config_log(&config, &format!("✅ DEBUG: [Thread-{}] Server reports {} size: {} bytes",
                    thread_id, filename.green(), size));
                Some(size)
            },
            Ok(None) => {
                // File no longer exists on server - skip it
                config_log(&config, &format!("{} [Thread-{}] {} no longer exists on server, skipping",
                    "⏭️".yellow(),
                    thread_id.to_string().cyan(),
                    filename.green()
                ));
                config_log(&config, &format!("❌ DEBUG: [Thread-{}] Server says {} not found (SIZE returned None)",
                    thread_id, filename.red()));
                return Ok(()); // Skip this file, don't treat as error
            },
            Err(e) => {
                // SIZE command not supported or failed - continue anyway without stabilization
                config_log(&config, &format!("⚠️  [Thread-{}] SIZE command failed for {} ({}), will upload without size check",
                    thread_id, filename.yellow(), e));
                None
            },
        };

            // Hash checking for keep mode - do this BEFORE stabilization
        if "upload" == "keep" {
            let key = format!("{}|{}", remote_dir, filename);
            // Get file modification time for hash computation
            let mod_time = match get_file_mod_time(&mut ftp, filename) {
                Ok(time) => time,
                Err(_) => chrono::Utc::now(), // Fallback to current time
            };
            let size_for_hash = initial_size.unwrap_or(0) as u64;
            let current_hash = compute_file_hash(filename, remote_dir, size_for_hash, mod_time);

            // DEBUG: Log hash comparison details
            config_log(&config, &format!("🔍 HASH DEBUG [Thread-{}]: File: {}", thread_id, filename.cyan()));
            config_log(&config, &format!("🔍 HASH DEBUG [Thread-{}]: Key: {}", thread_id, key.cyan()));
            config_log(&config, &format!("🔍 HASH DEBUG [Thread-{}]: Size: {:?}, ModTime: {}", thread_id, initial_size, mod_time.timestamp()));
            config_log(&config, &format!("🔍 HASH DEBUG [Thread-{}]: Current hash: {}", thread_id, current_hash));
            config_log(&config, &format!("🔍 HASH DEBUG [Thread-{}]: Loaded {} existing hashes", thread_id, existing_hashes.len()));

            // Check if we have an existing hash and if it matches
            if let Some(existing_hash) = existing_hashes.get(&key) {
                config_log(&config, &format!("🔍 HASH DEBUG [Thread-{}]: Existing hash: {}", thread_id, existing_hash));
                config_log(&config, &format!("🔍 HASH DEBUG [Thread-{}]: Hash match: {}", thread_id, *existing_hash == current_hash));
                
                if *existing_hash == current_hash {
                    config_log(&config, &format!("{} [Thread-{}] {} unchanged, skipping upload", 
                        "⏭️".yellow(), 
                        thread_id.to_string().cyan(), 
                        filename.green()
                    ));
                    
                    let _ = status_tx.send(StatusUpdate {
                        stage: "Skipped (unchanged)".to_string(),
                        filename: filename.clone(),
                        progress: file_progress + 0.15,
                        thread_id,
                        file_size: None,
                    });
                    
                    // Increment counter for skipped files
                    files_processed.fetch_add(1, Ordering::SeqCst);
                    
                    // No need to quit here - will be handled at end of retry loop
                    return Ok(()); // Skip this file
                } else {
                    config_log(&config, &format!("{} [Thread-{}] {} hash changed, will upload", 
                        "🔄".blue(), 
                        thread_id.to_string().cyan(), 
                        filename.yellow()
                    ));
                }
            } else {
                config_log(&config, &format!("🔍 HASH DEBUG [Thread-{}]: No existing hash found for key: {}", thread_id, key.cyan()));
            }
        }

        // Stabilization is now handled in Phase 1 before uploading
        // All files in Phase 2 are already stable, so we can proceed directly to upload

        // DEBUG: Log before download attempt
        // For uploads: filename is relative path, remote_dir is full local path
        let local_path = PathBuf::from(remote_dir); // remote_dir contains the full local path
        let relative_path = filename; // filename contains the relative path

        config_log(&config, &format!("⬆️ DEBUG: [Thread-{}] Starting upload of {} ({:?} bytes) to '{}'",
            thread_id, relative_path.cyan(), initial_size, config.remote_destination.cyan()));

        // Upload file to FTP server
        let upload_start = std::time::Instant::now();
        let upload_result = upload_file(&mut ftp, relative_path, &local_path, &config.remote_destination, config.respect_file_paths);
        
        match upload_result {
            Ok(_local_path) => {
                let _ = status_tx.send(StatusUpdate {
                    stage: "Uploaded".to_string(),
                    filename: filename.clone(),
                    progress: file_progress + 0.15,
                    thread_id,
                    file_size: initial_size.map(|s| s as u64),
                });

                let _ = status_tx.send(StatusUpdate {
                    stage: "Verified".to_string(),
                    filename: filename.clone(),
                    progress: file_progress + 0.2,
                    thread_id,
                    file_size: initial_size.map(|s| s as u64),
                });

                // Send structured notification for successful download (no progress bar)
                let _ = send_notification(&config, "success", &format!("Uploaded {}", filename), Some(filename), None);
                
                // Log download completion
                config_log(&config, &format!("{} [Thread-{}] {} downloaded successfully", 
                    "⬇️".blue(), 
                    thread_id.to_string().cyan(), 
                    filename.green()
                ));
                
                // Update session state with download time and file size
                let upload_time = upload_start.elapsed().as_secs_f64();
                if let Ok(mut state) = session_state_clone.lock() {
                    state.add_file_upload(initial_size.unwrap_or(0) as usize, upload_time);
                    
                    // Debug logging for session stats
                    config_log(&config, &format!("📊 [Thread-{}] Session stats updated: {} files, {} bytes, {:.2}s, {:.2} MB/s avg", 
                        thread_id.to_string().cyan(),
                        state.total_files.to_string().green(),
                        state.total_bytes.to_string().blue(),
                        state.total_upload_time.to_string().yellow(),
                        state.get_average_speed_mbps().to_string().cyan()
                    ));
                    
                    // Send session report only when we have meaningful data (files processed)
                    // This preserves the last valid speed until new files are processed
                    if state.total_files > 0 && state.total_files % 3 == 0 {
                        if let Err(e) = send_session_report(&session_file, &config, &state) {
                            config_log(&config, &format!("⚠️ [Thread-{}] Failed to send session report: {}", 
                                thread_id.to_string().yellow(), 
                                e.to_string().yellow()
                            ));
                        }
                    }
                }
                
                // Move local file to FTPU-Sent directory after successful upload
                let local_path = PathBuf::from(remote_dir); // remote_dir actually contains local file path
                match move_to_sent_directory(&local_path, &config.local_source_path) {
                    Ok(sent_path) => {
                        config_log(&config, &format!("{} [Thread-{}] {} moved to FTPU-Sent",
                            "📦".green(),
                            thread_id.to_string().cyan(),
                            filename.green()
                        ));
                        config_log(&config, &format!("   Sent to: {}", sent_path.display()));

                        // Send success notification to Live Notifications UI
                        let _ = send_notification(&config, "success", &format!("✅ Uploaded: {}", filename), Some(filename), None);
                    }
                    Err(e) => {
                        config_log(&config, &format!("{} [Thread-{}] Failed to move {} to FTPU-Sent: {}",
                            "⚠️".yellow(),
                            thread_id.to_string().yellow(),
                            filename.yellow(),
                            e.to_string().yellow()
                        ));

                        // Send warning notification - file uploaded but couldn't be moved
                        let _ = send_notification(&config, "warning", &format!("⚠️ Uploaded {} but failed to move to FTPU-Sent", filename), Some(filename), None);
                    }
                }
                
                // Calculate download speed for this file
                let upload_time = upload_start.elapsed().as_secs_f64();
                let size_mb = initial_size.unwrap_or(0) as f64 / 1024.0 / 1024.0;
                let speed_mbps = if upload_time > 0.0 {
                    size_mb / upload_time
                } else {
                    0.0
                };

                // Log completion for debugging but don't overwrite main status file
                config_log(&config_arc_local, &format!("✅ Uploaded: {} ({:.2} MB at {:.2} MB/s in {:.1}s)",
                    filename,
                    size_mb,
                    speed_mbps,
                    upload_time
                ));
                
                // Send completion via status channel (will be processed by status receiver thread)
                let _ = status_tx.send(StatusUpdate {
                    stage: "FileComplete".to_string(), // Use different stage to avoid confusion
                    filename: format!("✅ Uploaded: {} ({:.2} MB at {:.2} MB/s in {:.1}s)", 
                        filename,
                        initial_size.unwrap_or(0) as f64 / 1024.0 / 1024.0,
                        speed_mbps,
                        upload_time
                    ),
                    progress: file_progress + 0.25,
                    thread_id,
                    file_size: initial_size.map(|s| s as u64),
                });
                
                let _ = status_tx.send(StatusUpdate {
                    stage: "Complete".to_string(),
                    filename: filename.clone(),
                    progress: file_progress + 0.25,
                    thread_id,
                    file_size: initial_size.map(|s| s as u64),
                });
                
                // Increment counter
                let current_count = files_processed.fetch_add(1, Ordering::SeqCst) + 1;
                config_log(&config, &format!("{} [Thread-{}] Progress: {}/{} files completed", 
                    "📈".blue(), 
                    thread_id.to_string().cyan(), 
                    current_count.to_string().green(), 
                    files_to_process.len().to_string().yellow()
                ));
            }
            Err(e) => {
                let error_msg = format!("Download failed: {}", e);
                config_log(&config, &format!("{} [Thread-{}] Download failed for {}: {}", 
                    "❌".red(), 
                    thread_id.to_string().red(), 
                    filename.red(), 
                    e.to_string().red()
                ));
                
                // Record download failure and check if we should retry
                let (is_server_rejection, retry_delay) = connection_manager_local.record_failure(&error_msg, config.sync_interval);
                
                let _ = status_tx.send(StatusUpdate {
                    stage: "Download failed".to_string(),
                    filename: filename.clone(),
                    progress: file_progress,
                    thread_id,
                    file_size: None,
                });
                
                // Clean up connection and check if we should retry
                ftp.quit().ok();
                
                if connection_attempt >= max_connection_retries {
                    config_log(&config, &format!("{} [Thread-{}] Max download retries ({}) reached for {}, giving up", 
                        "❌".red(), thread_id, max_connection_retries, filename.red()));
                    break Err(format!("Download failed after {} attempts: {}", max_connection_retries, e));
                }
                
                config_log(&config, &format!("{} [Thread-{}] Will retry download for {} in {:.1}s (attempt {})", 
                    "🔄".yellow(), thread_id, filename.yellow(), retry_delay.as_secs_f64(), connection_attempt + 1));
                std::thread::sleep(retry_delay);
                continue; // Retry the entire file processing (connection + download)
            }
        }

            // Record successful connection for this file
            connection_manager_local.record_success();
            
            ftp.quit().ok();
            config_log(&config, &format!("{} [Thread-{}] Completed processing {} (connection restored)", 
                "🎉".green(), 
                thread_id.to_string().cyan(), 
                filename.green()
            ));
            break Ok(()); // Successfully processed file, exit retry loop
        };
        
        file_result
        }).collect()
    });  // Close pool.install() - custom thread pool execution

    // Close status channel
    drop(status_tx);
    
    // Wait for status receiver to finish
    let _ = status_receiver.join();

    // Process results to count successes and failures
    let successful_files = results.iter().filter(|r| r.is_ok()).count();
    let failed_files = results.iter().filter(|r| r.is_err()).count();
    
    // Log detailed results for failed files
    let failed_file_names: Vec<String> = results.iter().enumerate()
        .filter_map(|(index, result)| {
            if let Err(error) = result {
                let (filename, _) = &files_to_process[index];
                Some(format!("{} ({})", filename, error))
            } else {
                None
            }
        })
        .collect();
    
    // Get final count from counter (should match successful_files)
    let final_count = files_processed.load(Ordering::SeqCst);

    config_log(&config, &format!("{}", "=".repeat(80).blue()));
    config_log(&config, &format!("{} Processing completed!", "🎯".green()));
    config_log(&config, &format!("{} Files processed: {}/{} ({} successful, {} failed)", 
        "📊".blue(), 
        successful_files.to_string().green(), 
        files_to_process.len().to_string().yellow(),
        successful_files.to_string().green(),
        failed_files.to_string().red()
    ));
    
    // Log failed files if any
    if !failed_file_names.is_empty() {
        config_log(&config, &format!("{} Failed files will be retried in next cycle:", "🔄".yellow()));
        for failed_file in &failed_file_names {
            config_log(&config, &format!("  ❌ {}", failed_file.red()));
        }
    }
    
    config_log(&config, &format!("{}", "=".repeat(80).blue()));
    
    // Send completion status with clear success/failure breakdown
    let status_message = if failed_files > 0 {
        format!("Processed {}/{} files ({} failed, will retry next cycle)", successful_files, files_to_process.len(), failed_files)
    } else {
        format!("Processed {} files successfully", successful_files)
    };
    
    send_status(status_file, &config, "Finished", &status_message, 1.0, None)?;
    
    // Send final session report only if files were processed successfully
    // This preserves the last valid speed until new files are processed
    if let Ok(state) = session_state.lock() {
        if state.total_files > 0 {
            if let Err(e) = send_session_report(session_file, &config, &state) {
                config_log(&config, &format!("⚠️ Failed to send final session report: {}", e.to_string().yellow()));
            }
        } else {
            config_log(&config, &format!("📊 No final session report - no files processed"));
        }
    }
    
    // Return successful count - cycle completes even with failures
    Ok(successful_files)
}

fn send_status(status_file: &str, config: &FTPConfig, stage: &str, filename: &str, progress: f64, file_size: Option<u64>) -> Result<(), Box<dyn std::error::Error>> {
    send_status_with_speed(status_file, config, stage, filename, progress, file_size, None, None)
}

fn send_notification(config: &FTPConfig, notification_type: &str, message: &str, filename: Option<&str>, progress: Option<f64>) -> Result<(), Box<dyn std::error::Error>> {
    use std::ffi::CString;

    // Look up the callback for this config_id
    let callback = {
        let callbacks = crate::NOTIFICATION_CALLBACKS.lock().unwrap();
        callbacks.get(&config.config_id).and_then(|cb| *cb)
    };

    // If callback exists, call it directly (FFI callback to Swift)
    if let Some(callback_fn) = callback {
        // Convert Rust strings to C strings
        let type_cstr = CString::new(notification_type).unwrap_or_else(|_| CString::new("info").unwrap());
        let message_cstr = CString::new(message).unwrap_or_else(|_| CString::new("").unwrap());
        let filename_cstr = filename.and_then(|f| CString::new(f).ok());

        let timestamp = chrono::Utc::now().timestamp_millis() as u64;
        let progress_val = progress.unwrap_or(-1.0);

        // Call the Swift callback function (needs u32 hash for FFI)
        let config_hash = config_id_to_hash(&config.config_id);
        callback_fn(
            config_hash,
            type_cstr.as_ptr(),
            message_cstr.as_ptr(),
            timestamp,
            filename_cstr.as_ref().map(|s| s.as_ptr()).unwrap_or(std::ptr::null()),
            progress_val
        );
    }

    Ok(())
}

fn send_status_with_speed(status_file: &str, config: &FTPConfig, stage: &str, filename: &str, progress: f64, file_size: Option<u64>, upload_speed_mbps: Option<f64>, upload_time_secs: Option<f64>) -> Result<(), Box<dyn std::error::Error>> {
    let status = FTPStatus {
        config_id: config.config_id.clone(),
        stage: stage.to_string(),
        filename: filename.to_string(),
        progress,
        timestamp: std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)?
            .as_secs(),
        file_size,
        upload_speed_mbps,
        upload_time_secs,
    };

    let status_json = serde_json::to_string(&status)?;
    fs::write(status_file, status_json)?;
    
    // Only log to console for important stages
    if stage == "Complete" || stage == "Error" || stage == "Warning" {
        info!("[{}] {} → {} ({:.1}%)", config.config_name, stage, filename, progress * 100.0);
    }
    Ok(())
}

fn send_session_report(session_file: &str, config: &FTPConfig, session_state: &SessionState) -> Result<(), Box<dyn std::error::Error>> {
    let report = SessionReport {
        session_id: config.session_id.clone(),
        config_id: config.config_id.clone(),
        total_files: session_state.total_files,
        total_bytes: session_state.total_bytes,
        total_time_secs: session_state.total_upload_time,
        average_speed_mbps: session_state.get_average_speed_mbps(),
    };

    let report_json = serde_json::to_string_pretty(&report)?;
    fs::write(session_file, report_json)?;
    
    // Log the session report - always show it, even if stats are 0
    if session_state.total_files > 0 {
        config_log(config, &format!("📊 Session Report: {} files, {:.2} MB/s", 
            session_state.total_files.to_string().green(),
            session_state.get_average_speed_mbps().to_string().cyan()
        ));

        println!("🔄 LOOP RESTART: Session complete, restarting loop for next iteration");
    } else {
        config_log(config, &format!("📊 Session Report: No files processed (0 files, 0.00 MB/s)"));

        println!("🔄 LOOP RESTART: No files processed, restarting loop for next iteration");
    }
    
    Ok(())
}

fn write_result(result_file: &str, config: &FTPConfig, success: bool, message: &str, files_processed: usize) -> Result<(), Box<dyn std::error::Error>> {
    let result = FTPResult {
        config_id: config.config_id.clone(),
        success,
        message: message.to_string(),
        files_processed,
        timestamp: std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)?
            .as_secs(),
    };

    let result_json = serde_json::to_string(&result)?;
    fs::write(result_file, result_json)?;
    Ok(())
}

// Move file to FTPU-Sent directory after successful upload
fn move_to_sent_directory(local_path: &PathBuf, base_dir: &str) -> Result<PathBuf, Box<dyn std::error::Error>> {
    let base_path = PathBuf::from(base_dir);
    let sent_dir = base_path.join("FTPU-Sent");

    // Create FTPU-Sent directory if it doesn't exist
    if !sent_dir.exists() {
        fs::create_dir_all(&sent_dir)?;
    }

    // Preserve directory structure within FTPU-Sent
    let relative_path = local_path.strip_prefix(&base_path)
        .unwrap_or(local_path.as_path());
    let dest_path = sent_dir.join(relative_path);

    // Create parent directories in FTPU-Sent if needed
    if let Some(parent) = dest_path.parent() {
        fs::create_dir_all(parent)?;
    }

    // Move the file
    fs::rename(local_path, &dest_path)?;

    Ok(dest_path)
}

// Create remote directory on FTP server (recursive mkdir)
fn create_remote_directory(ftp: &mut ftp::FtpStream, remote_path: &str) -> Result<(), Box<dyn std::error::Error>> {
    // Split path into components and create each level
    let components: Vec<&str> = remote_path.trim_matches('/').split('/').filter(|s| !s.is_empty()).collect();

    let mut current_path = String::new();
    for component in components {
        current_path = if current_path.is_empty() {
            format!("/{}", component)
        } else {
            format!("{}/{}", current_path, component)
        };

        // Try to create directory (ignore error if it already exists)
        match ftp.mkdir(&current_path) {
            Ok(_) => {
                println!("📁 Created remote directory: {}", current_path);
            },
            Err(e) => {
                // Check if error is "directory already exists" - that's ok
                let err_str = e.to_string();
                if !err_str.contains("550") && !err_str.contains("exists") {
                    // Only log as debug, don't fail - directory might already exist
                    println!("📁 Note: mkdir {} - {}", current_path, err_str);
                }
            }
        }
    }

    Ok(())
}

// Helper function to upload files to FTP server
fn upload_file(ftp: &mut ftp::FtpStream, filename: &str, local_path: &PathBuf, remote_dir: &str, respect_file_paths: bool) -> Result<PathBuf, Box<dyn std::error::Error>> {
    println!("🔍 UPLOAD DEBUG: Starting upload_file for {} to {}", filename, remote_dir);

    // Detect if file is likely text or binary based on extension
    let is_text_file = is_likely_text_file(filename);

    println!("🔍 UPLOAD DEBUG: File {} detected as {}", filename, if is_text_file { "TEXT" } else { "BINARY" });

    // Set transfer mode based on file type
    if is_text_file {
        println!("🔍 UPLOAD DEBUG: Setting ASCII mode for {}", filename);
        ftp.transfer_type(ftp::types::FileType::Ascii(ftp::types::FormatControl::Default))?;
    } else {
        println!("🔍 UPLOAD DEBUG: Setting BINARY mode for {}", filename);
        ftp.transfer_type(ftp::types::FileType::Binary)?;
    }

    // Determine remote path based on respect_file_paths setting
    let remote_filename = if respect_file_paths {
        // Preserve directory structure - extract relative path from local_path
        filename.to_string()
    } else {
        // Flat structure - just use filename
        local_path.file_name()
            .map(|n| n.to_string_lossy().to_string())
            .unwrap_or_else(|| filename.to_string())
    };

    // Create parent directories if respect_file_paths is enabled and filename contains path
    if respect_file_paths && remote_filename.contains('/') {
        // Extract directory part from the remote filename
        if let Some(parent_dir) = PathBuf::from(&remote_filename).parent() {
            let parent_str = parent_dir.to_string_lossy().to_string();
            if !parent_str.is_empty() {
                // Build full remote path
                let full_remote_dir = if remote_dir == "/" {
                    format!("/{}", parent_str)
                } else {
                    format!("{}/{}", remote_dir.trim_end_matches('/'), parent_str)
                };

                println!("📁 UPLOAD DEBUG: Creating remote directory: {}", full_remote_dir);

                // Create directories recursively
                let components: Vec<&str> = full_remote_dir.trim_matches('/').split('/').filter(|s| !s.is_empty()).collect();
                let mut current_path = String::new();

                for component in components {
                    current_path = if current_path.is_empty() {
                        format!("/{}", component)
                    } else {
                        format!("{}/{}", current_path, component)
                    };

                    // Try to create directory (ignore error if it already exists)
                    match ftp.mkdir(&current_path) {
                        Ok(_) => {
                            println!("📁 Created remote directory: {}", current_path);
                        },
                        Err(_) => {
                            // Directory likely already exists - that's OK
                        }
                    }
                }
            }
        }
    }

    // Read local file
    let file_data = fs::read(local_path)?;
    let file_size = file_data.len();

    println!("🔍 UPLOAD DEBUG: Read {} bytes from local file {}", file_size, local_path.display());
    println!("🔍 UPLOAD DEBUG: About to send STOR command for {}", remote_filename);

    // Upload file using put()
    let mut cursor = std::io::Cursor::new(file_data);
    match ftp.put(&remote_filename, &mut cursor) {
        Ok(_) => {
            println!("🔍 UPLOAD DEBUG: STOR successful for {}, uploaded {} bytes", remote_filename, file_size);
        },
        Err(e) => {
            println!("❌ UPLOAD DEBUG: STOR FAILED for {}: {}", remote_filename, e);
            return Err(Box::new(e));
        }
    };

    // Reset to binary mode for next file
    ftp.transfer_type(ftp::types::FileType::Binary)?;

    Ok(local_path.clone())
}

// Helper function to get unique filename (append _# if file exists)
fn get_unique_filename(path: &PathBuf) -> PathBuf {
    if !path.exists() {
        return path.clone();
    }
    
    let mut counter = 1;
    let stem = path.file_stem().unwrap().to_string_lossy();
    let extension = path.extension().map(|ext| format!(".{}", ext.to_string_lossy())).unwrap_or_default();
    
    loop {
        let new_name = format!("{}_{}{}", stem, counter, extension);
        let new_path = path.with_file_name(new_name);
        
        if !new_path.exists() {
            return new_path;
        }
        
        counter += 1;
        
        // Prevent infinite loop (max 999 files)
        if counter > 999 {
            break;
        }
    }
    
    // Fallback: append timestamp
    let timestamp = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_secs();
    let new_name = format!("{}_{}{}", stem, timestamp, extension);
    path.with_file_name(new_name)
}

// Helper function to detect if a file is likely text
fn is_likely_text_file(filename: &str) -> bool {
    let text_extensions = [
        "txt", "md", "json", "xml", "html", "htm", "css", "js", "py", "rs", "swift", "java", "c", "cpp", "h", "hpp",
        "sh", "bash", "zsh", "fish", "ps1", "bat", "cmd", "ini", "cfg", "conf", "log", "csv", "tsv", "sql", "r", "m",
        "tex", "bib", "tex", "sty", "cls", "ltx", "dtx", "ins", "fdt", "fdb", "aux", "bbl", "blg", "idx", "ind", "glo",
        "acn", "alg", "ist", "loa", "lot", "out", "toc", "lof", "lol", "nav", "snm", "vrb", "synctex.gz"
    ];
    
    if let Some(extension) = filename.split('.').last() {
        text_extensions.contains(&extension.to_lowercase().as_str())
    } else {
        false
    }
}

// Binary entry point - thin wrapper around run_ftp_with_args()
fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Collect arguments
    let args: Vec<String> = std::env::args().collect();

    // Create shutdown signal for Ctrl-C handling
    let shutdown_flag = Arc::new(AtomicBool::new(false));
    let shutdown_flag_clone = shutdown_flag.clone();

    // Set up Ctrl-C handler for binary mode
    ctrlc::set_handler(move || {
        println!("{} Received shutdown signal, finishing current iteration...", "🛑".red());
        shutdown_flag_clone.store(true, Ordering::SeqCst);
    }).expect("Error setting Ctrl-C handler");

    // Run the FTP engine
    run_ftp_with_args(args, shutdown_flag)
}
