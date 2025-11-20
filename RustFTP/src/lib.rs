//!
//! Rust FTP Library - C FFI Interface for Swift Integration
//!
//! This library exposes the Rust FTP functionality via a C-compatible FFI,
//! allowing the Rust code to be statically linked into the Swift executable.
//!
//! The strategy here is to keep the existing async/tokio code mostly intact
//! and run it in background threads managed from the FFI layer.
//!

use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::sync::{Arc, Mutex};
use std::collections::HashMap;
use std::thread;
use std::sync::atomic::{AtomicBool, Ordering};

// Include the existing FTP engine as a module
mod ftp_engine;

// Include the database module
mod db;

// C function pointer type for notification callbacks from Swift
pub type NotificationCallback = Option<extern "C" fn(
    u32,                    // config_id (config hash)
    *const c_char,          // notification_type
    *const c_char,          // message
    u64,                    // timestamp
    *const c_char,          // filename (nullable)
    f64                     // progress (use -1.0 for None)
)>;

// Global registry of running FTP sessions
lazy_static::lazy_static! {
    static ref SESSIONS: Arc<Mutex<HashMap<String, SessionHandle>>> = Arc::new(Mutex::new(HashMap::new()));
    // Global registry mapping config_id (UUID string) to notification callback
    pub(crate) static ref NOTIFICATION_CALLBACKS: Arc<Mutex<HashMap<String, NotificationCallback>>> = Arc::new(Mutex::new(HashMap::new()));
}

struct SessionHandle {
    thread_handle: Option<thread::JoinHandle<()>>,
    shutdown_signal: Arc<AtomicBool>,
    notification_callback: NotificationCallback,
}

/// Start an FTP monitoring session
///
/// Parameters:
///   - config_path: Path to JSON config file
///   - status_path: Path where status updates will be written
///   - result_path: Path where final result will be written
///   - session_path: Path where session summary will be written
///   - hash_path: Path for file hash tracking
///   - session_id: Unique identifier for this session
///   - notification_callback: Optional callback function for real-time notifications
///
/// Returns 0 on success, non-zero on error
#[no_mangle]
pub extern "C" fn rust_ftp_start(
    config_path: *const c_char,
    status_path: *const c_char,
    result_path: *const c_char,
    session_path: *const c_char,
    hash_path: *const c_char,
    session_id: *const c_char,
    notification_callback: NotificationCallback,
) -> i32 {
    // Convert C strings to Rust strings
    let config_str = unsafe {
        if config_path.is_null() {
            return -1;
        }
        match CStr::from_ptr(config_path).to_str() {
            Ok(s) => s.to_string(),
            Err(_) => return -2,
        }
    };

    let status_str = unsafe {
        if status_path.is_null() {
            return -3;
        }
        match CStr::from_ptr(status_path).to_str() {
            Ok(s) => s.to_string(),
            Err(_) => return -4,
        }
    };

    let result_str = unsafe {
        if result_path.is_null() {
            return -5;
        }
        match CStr::from_ptr(result_path).to_str() {
            Ok(s) => s.to_string(),
            Err(_) => return -6,
        }
    };

    let session_str = unsafe {
        if session_path.is_null() {
            return -7;
        }
        match CStr::from_ptr(session_path).to_str() {
            Ok(s) => s.to_string(),
            Err(_) => return -8,
        }
    };

    let hash_str = unsafe {
        if hash_path.is_null() {
            return -9;
        }
        match CStr::from_ptr(hash_path).to_str() {
            Ok(s) => s.to_string(),
            Err(_) => return -10,
        }
    };

    let id_str = unsafe {
        if session_id.is_null() {
            return -11;
        }
        match CStr::from_ptr(session_id).to_str() {
            Ok(s) => s.to_string(),
            Err(_) => return -12,
        }
    };

    // Read the config file to extract config_id for callback registration
    let config_id: Option<String> = if notification_callback.is_some() {
        if let Ok(config_json) = std::fs::read_to_string(&config_str) {
            if let Ok(json_value) = serde_json::from_str::<serde_json::Value>(&config_json) {
                json_value.get("config_id").and_then(|v| v.as_str()).map(|v| v.to_string())
            } else {
                None
            }
        } else {
            None
        }
    } else {
        None
    };

    // Register the callback if both callback and config_id exist
    if let (Some(callback), Some(cid)) = (notification_callback, config_id) {
        let mut callbacks = NOTIFICATION_CALLBACKS.lock().unwrap();
        callbacks.insert(cid.clone(), Some(callback));
        eprintln!("Registered notification callback for config_id: {}", cid);
    }

    // Create shutdown signal
    let shutdown = Arc::new(AtomicBool::new(false));
    let shutdown_clone = shutdown.clone();

    // Spawn FTP session in background thread
    // This will run the existing main() logic
    let handle = thread::spawn(move || {
        let args = vec![
            "rust_ftp".to_string(),
            config_str,
            status_str,
            result_str,
            session_str,
            hash_str,
        ];

        if let Err(e) = ftp_engine::run_ftp_with_args(args, shutdown_clone) {
            eprintln!("FTP session error: {}", e);
        }
    });

    // Store session handle
    let session_handle = SessionHandle {
        thread_handle: Some(handle),
        shutdown_signal: shutdown,
        notification_callback,
    };

    let mut sessions = SESSIONS.lock().unwrap();
    sessions.insert(id_str, session_handle);

    0 // Success
}

/// Stop an FTP monitoring session
/// Returns 0 on success, non-zero on error
#[no_mangle]
pub extern "C" fn rust_ftp_stop(session_id: *const c_char) -> i32 {
    let id_str = unsafe {
        if session_id.is_null() {
            return -1;
        }
        match CStr::from_ptr(session_id).to_str() {
            Ok(s) => s.to_string(),
            Err(_) => return -2,
        }
    };

    let mut sessions = SESSIONS.lock().unwrap();

    if let Some(mut session) = sessions.remove(&id_str) {
        // Signal shutdown
        session.shutdown_signal.store(true, Ordering::SeqCst);

        // DO NOT wait for thread - let it clean up asynchronously
        // Waiting here blocks the UI thread and can cause 60+ second hangs
        // when Rust worker threads are in the middle of parallel operations
        // The thread will exit on its own when it detects the shutdown signal
        drop(session.thread_handle);

        0 // Success
    } else {
        -3 // Session not found
    }
}

/// Get status for a session by reading the status file
/// Returns JSON string (must be freed with rust_ftp_free_string)
/// Returns null pointer on error
#[no_mangle]
pub extern "C" fn rust_ftp_get_status(status_path: *const c_char) -> *mut c_char {
    let path_str = unsafe {
        if status_path.is_null() {
            return std::ptr::null_mut();
        }
        match CStr::from_ptr(status_path).to_str() {
            Ok(s) => s.to_string(),
            Err(_) => return std::ptr::null_mut(),
        }
    };

    // Read status file
    match std::fs::read_to_string(&path_str) {
        Ok(content) => {
            match CString::new(content) {
                Ok(c_str) => c_str.into_raw(),
                Err(_) => std::ptr::null_mut(),
            }
        }
        Err(_) => std::ptr::null_mut(),
    }
}

/// Free a string allocated by Rust
#[no_mangle]
pub extern "C" fn rust_ftp_free_string(s: *mut c_char) {
    if !s.is_null() {
        unsafe {
            let _ = CString::from_raw(s);
        }
    }
}

/// Initialize the Rust FTP library
/// Should be called once at app startup
#[no_mangle]
pub extern "C" fn rust_ftp_init() -> i32 {
    // Initialize logging
    let _ = env_logger::try_init();
    0
}

/// Shutdown the Rust FTP library
/// Should be called at app shutdown
#[no_mangle]
pub extern "C" fn rust_ftp_shutdown() -> i32 {
    // Stop all sessions
    let mut sessions = SESSIONS.lock().unwrap();
    for (_id, mut session) in sessions.drain() {
        session.shutdown_signal.store(true, Ordering::SeqCst);
        if let Some(handle) = session.thread_handle.take() {
            let _ = handle.join();
        }
    }
    0
}

/// Clear all downloaded file hashes for a specific configuration
/// This will cause all files to be re-downloaded on the next sync
/// Returns 0 on success, non-zero on error
#[no_mangle]
pub extern "C" fn rust_ftp_clear_config_data(config_id: *const c_char) -> i32 {
    // Convert C string to Rust string
    let config_id_str = unsafe {
        if config_id.is_null() {
            return -1;
        }
        match CStr::from_ptr(config_id).to_str() {
            Ok(s) => s,
            Err(_) => return -2,
        }
    };

    // Call the database function to delete all data for this config
    match db::delete_config_data(config_id_str) {
        Ok(deleted_count) => {
            println!("✅ Cleared {} hash entries for config: {}", deleted_count, config_id_str);
            0
        }
        Err(e) => {
            eprintln!("❌ Failed to clear config data: {}", e);
            -3
        }
    }
}
