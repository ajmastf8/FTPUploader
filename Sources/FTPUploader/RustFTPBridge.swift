//
//  RustFTPBridge.swift
//  FTPDownloader
//
//  Swift wrapper for Rust FTP FFI library
//  Provides a clean Swift interface to the statically-linked Rust FTP engine
//

import Foundation

// C function pointer type for Rust notification callbacks
typealias RustNotificationCallback = @convention(c) (
    UInt32,                              // config_id (config hash)
    UnsafePointer<CChar>?,              // notification_type
    UnsafePointer<CChar>?,              // message
    UInt64,                              // timestamp
    UnsafePointer<CChar>?,              // filename (optional)
    Double                               // progress (use -1.0 for None)
) -> Void

// Direct C function declarations from Rust FFI library
@_silgen_name("rust_ftp_init")
func rust_ftp_init() -> Int32

@_silgen_name("rust_ftp_shutdown")
func rust_ftp_shutdown() -> Int32

@_silgen_name("rust_ftp_start")
func rust_ftp_start(
    _ config_path: UnsafePointer<CChar>,
    _ status_path: UnsafePointer<CChar>,
    _ result_path: UnsafePointer<CChar>,
    _ session_path: UnsafePointer<CChar>,
    _ hash_path: UnsafePointer<CChar>,
    _ session_id: UnsafePointer<CChar>,
    _ notification_callback: RustNotificationCallback?
) -> Int32

@_silgen_name("rust_ftp_stop")
func rust_ftp_stop(_ session_id: UnsafePointer<CChar>) -> Int32

@_silgen_name("rust_ftp_get_status")
func rust_ftp_get_status(_ status_path: UnsafePointer<CChar>) -> UnsafeMutablePointer<CChar>?

@_silgen_name("rust_ftp_clear_config_data")
func rust_ftp_clear_config_data(_ config_id: UnsafePointer<CChar>) -> Int32

@_silgen_name("rust_ftp_free_string")
func rust_ftp_free_string(_ s: UnsafeMutablePointer<CChar>)

/// Swift wrapper for the Rust FTP static library
///
/// This class provides a type-safe Swift interface to the Rust FTP engine,
/// which is statically linked into the app bundle. This eliminates the need
/// for a separate rust_ftp helper executable, solving App Store sandbox issues.
class RustFTPBridge {

    private static var isInitialized = false
    private static let initLock = NSLock()

    // Global mapping of config hash to UUID for notification routing
    private static var configHashToUUID: [UInt32: UUID] = [:]
    private static let hashMapLock = NSLock()

    /// Compute a stable hash from a UUID string (matches Rust's config_id_to_hash)
    /// Uses FNV-1a hash algorithm truncated to 32 bits, same as Rust implementation
    static func computeStableHash(from uuidString: String) -> UInt32 {
        // FNV-1a hash (stable and fast, matches Rust implementation)
        var hash: UInt64 = 0xcbf29ce484222325 // FNV offset basis
        let fnvPrime: UInt64 = 0x100000001b3 // FNV prime

        for byte in uuidString.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* fnvPrime
        }

        return UInt32(hash & 0xFFFFFFFF)
    }

    /// Register a config UUID with its hash for notification routing
    static func registerConfigHash(_ hash: UInt32, for uuid: UUID) {
        hashMapLock.lock()
        defer { hashMapLock.unlock() }
        configHashToUUID[hash] = uuid
        print("🔗 Registered config hash \(hash) -> \(uuid)")
    }

    /// Unregister a config hash
    static func unregisterConfigHash(_ hash: UInt32) {
        hashMapLock.lock()
        defer { hashMapLock.unlock() }
        configHashToUUID.removeValue(forKey: hash)
        print("🔓 Unregistered config hash \(hash)")
    }

    /// Get UUID for a config hash
    static func getUUID(for hash: UInt32) -> UUID? {
        hashMapLock.lock()
        defer { hashMapLock.unlock() }
        return configHashToUUID[hash]
    }

    /// Initialize the Rust FTP library
    /// Should be called once at app startup
    static func initialize() {
        initLock.lock()
        defer { initLock.unlock() }

        guard !isInitialized else { return }

        // Set FTP_TMP_DIR environment variable to match Swift's temporary directory
        // This ensures Rust writes notification files to the same location Swift reads from
        let tempDir = FileManager.default.temporaryDirectory.path
        setenv("FTP_TMP_DIR", tempDir, 1)
        print("🔧 Set FTP_TMP_DIR environment variable to: \(tempDir)")

        // Set FTP_DATA_DIR environment variable for database storage
        // For sandboxed apps, use Application Support directory in the container
        let dataDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("FTPUploader")
            .path ?? "\(tempDir)/FTPUploader"

        // Create data directory if it doesn't exist
        try? FileManager.default.createDirectory(atPath: dataDir, withIntermediateDirectories: true)
        setenv("FTP_DATA_DIR", dataDir, 1)
        print("🔧 Set FTP_DATA_DIR environment variable to: \(dataDir)")

        // Clean up old notification files (>2 days old)
        cleanupOldNotificationFiles(in: tempDir)

        let result = rust_ftp_init()
        if result == 0 {
            isInitialized = true
            print("✅ Rust FTP library initialized successfully")
        } else {
            print("❌ Failed to initialize Rust FTP library: \(result)")
        }
    }

    /// Clean up notification files older than 2 days
    private static func cleanupOldNotificationFiles(in directory: String) {
        let fileManager = FileManager.default
        let directoryURL = URL(fileURLWithPath: directory)
        let twoDaysAgo = Date().addingTimeInterval(-2 * 24 * 60 * 60)

        do {
            let files = try fileManager.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )

            let notificationFiles = files.filter { $0.lastPathComponent.hasPrefix("ftp_notifications_") && $0.pathExtension == "jsonl" }

            var removedCount = 0
            var totalSize: UInt64 = 0

            for file in notificationFiles {
                let attributes = try fileManager.attributesOfItem(atPath: file.path)
                if let modificationDate = attributes[.modificationDate] as? Date,
                   modificationDate < twoDaysAgo {

                    if let fileSize = attributes[.size] as? UInt64 {
                        totalSize += fileSize
                    }

                    try fileManager.removeItem(at: file)
                    removedCount += 1
                }
            }

            if removedCount > 0 {
                let sizeMB = Double(totalSize) / 1_000_000.0
                print("🧹 Cleaned up \(removedCount) old notification file(s) (>2 days old), freed \(String(format: "%.2f", sizeMB)) MB")
            } else {
                print("✅ No old notification files to clean up")
            }

        } catch {
            print("⚠️ Failed to clean up old notification files: \(error)")
        }
    }

    /// Shutdown the Rust FTP library
    /// Should be called at app shutdown
    static func shutdown() {
        initLock.lock()
        defer { initLock.unlock() }

        guard isInitialized else { return }

        let result = rust_ftp_shutdown()
        if result == 0 {
            isInitialized = false
            print("✅ Rust FTP library shut down successfully")
        } else {
            print("❌ Failed to shutdown Rust FTP library: \(result)")
        }
    }

    /// Clear all downloaded file hashes for a specific configuration
    /// This will cause all files to be re-downloaded on the next sync
    /// - Parameter configId: UUID of the configuration
    /// - Returns: true on success, false on error
    @discardableResult
    static func clearConfigData(for configId: UUID) -> Bool {
        let configIdString = configId.uuidString
        let result = configIdString.withCString { idPtr in
            rust_ftp_clear_config_data(idPtr)
        }

        if result == 0 {
            print("✅ Successfully cleared config data for: \(configId)")
            return true
        } else {
            print("❌ Failed to clear config data for \(configId): error code \(result)")
            return false
        }
    }

    private let sessionId: String
    private var isRunning = false
    private let statusLock = NSLock()
    private var callback: RustNotificationCallback? // Store callback to keep it alive

    /// Initialize a new FTP session bridge
    /// - Parameter sessionId: Unique identifier for this session
    init(sessionId: String = UUID().uuidString) {
        self.sessionId = sessionId
    }

    /// Start an FTP monitoring session
    ///
    /// - Parameters:
    ///   - configPath: Path to JSON configuration file
    ///   - statusPath: Path where status updates will be written
    ///   - resultPath: Path where final result will be written
    ///   - sessionPath: Path where session summary will be written
    ///   - hashPath: Path for file hash tracking
    /// - Returns: true on success, false on error
    @discardableResult
    func start(
        configPath: String,
        statusPath: String,
        resultPath: String,
        sessionPath: String,
        hashPath: String
    ) -> Bool {
        statusLock.lock()
        defer { statusLock.unlock() }

        guard !isRunning else {
            print("⚠️ Session \(sessionId) is already running")
            return false
        }

        // Ensure library is initialized
        RustFTPBridge.initialize()

        // Define the Swift callback that Rust will call
        // CRITICAL: Store in instance variable to keep it alive!
        self.callback = { configHash, typePtr, messagePtr, timestamp, filenamePtr, progress in
            // Convert C strings to Swift strings
            guard let typePtr = typePtr, let messagePtr = messagePtr else { return }

            let notificationType = String(cString: typePtr)
            let message = String(cString: messagePtr)
            let filename = filenamePtr.map { String(cString: $0) }

            // Look up the UUID for this config hash
            guard let configId = RustFTPBridge.getUUID(for: configHash) else {
                print("⚠️ Received notification for unregistered config hash: \(configHash)")
                return
            }

            // Post to NotificationCenter on main thread
            DispatchQueue.main.async {
                // Determine state from message content
                // FileSyncManager expects: "connected", "scanning", "waiting", "warning", "error", "monitor_warning"
                let state: String
                let messageLower = message.lowercased()
                if messageLower.contains("connected to") {
                    state = "connected"
                } else if messageLower.contains("scanning") || messageLower.contains("found files") {
                    state = "scanning"
                } else if messageLower.contains("waiting") || messageLower.contains("no new files") {
                    state = "waiting"
                } else if notificationType == "monitor_warning" {
                    state = "monitor_warning"  // Special state for monitor conflicts (doesn't affect connection status)
                } else if notificationType == "warning" {
                    state = "warning"
                } else if notificationType == "error" {
                    state = "error"
                } else {
                    state = "info"
                }

                var userInfo: [String: Any] = [
                    "configId": configId,
                    "notificationType": notificationType,
                    "state": state,  // Add state key for FileSyncManager
                    "message": message,
                    "timestamp": timestamp
                ]

                // Only add optional fields if they exist
                if let fn = filename {
                    userInfo["filename"] = fn
                }
                if progress >= 0.0 {
                    userInfo["progress"] = progress
                }

                // Post appropriate notification based on type
                if notificationType == "success" && message.hasPrefix("Downloaded ") {
                    print("🔔 RustFTPBridge: Posting .rustDownloadSpeedUpdate notification")
                    print("🔔 RustFTPBridge: filename in userInfo: \(userInfo["filename"] ?? "NONE")")
                    NotificationCenter.default.post(
                        name: .rustUploadSpeedUpdate,
                        object: nil,
                        userInfo: userInfo
                    )
                } else {
                    print("🔕 RustFTPBridge: NOT posting .rustDownloadSpeedUpdate (type=\(notificationType), message=\(message))")
                }

                // Always post state update for all notifications
                NotificationCenter.default.post(
                    name: .rustStateUpdate,
                    object: nil,
                    userInfo: userInfo
                )
            }
        }

        let result = configPath.withCString { configPtr in
            statusPath.withCString { statusPtr in
                resultPath.withCString { resultPtr in
                    sessionPath.withCString { sessionPtr in
                        hashPath.withCString { hashPtr in
                            sessionId.withCString { idPtr in
                                rust_ftp_start(
                                    configPtr,
                                    statusPtr,
                                    resultPtr,
                                    sessionPtr,
                                    hashPtr,
                                    idPtr,
                                    self.callback
                                )
                            }
                        }
                    }
                }
            }
        }

        if result == 0 {
            isRunning = true
            print("✅ Started Rust FTP session: \(sessionId)")
            return true
        } else {
            print("❌ Failed to start Rust FTP session \(sessionId): error code \(result)")
            printErrorCode(result)
            return false
        }
    }

    /// Stop the FTP monitoring session
    /// - Returns: true on success, false on error
    @discardableResult
    func stop() -> Bool {
        statusLock.lock()
        defer { statusLock.unlock() }

        guard isRunning else {
            print("⚠️ Session \(sessionId) is not running")
            return false
        }

        let result = sessionId.withCString { idPtr in
            rust_ftp_stop(idPtr)
        }

        if result == 0 {
            isRunning = false
            callback = nil // Clear callback to release closure
            print("✅ Stopped Rust FTP session: \(sessionId)")
            return true
        } else {
            print("❌ Failed to stop Rust FTP session \(sessionId): error code \(result)")
            if result == -3 {
                print("   Session not found in Rust registry")
            }
            return false
        }
    }

    /// Get current status for the session
    ///
    /// - Parameter statusPath: Path to the status file
    /// - Returns: Status JSON string, or nil on error
    func getStatus(statusPath: String) -> String? {
        let cString = statusPath.withCString { statusPtr in
            rust_ftp_get_status(statusPtr)
        }

        guard let cString = cString else {
            return nil
        }

        let swiftString = String(cString: cString)
        rust_ftp_free_string(UnsafeMutablePointer(mutating: cString))

        return swiftString
    }

    /// Check if the session is currently running
    var running: Bool {
        statusLock.lock()
        defer { statusLock.unlock() }
        return isRunning
    }

    // MARK: - Error Handling

    private func printErrorCode(_ code: Int32) {
        switch code {
        case -1: print("   Error: config_path is null")
        case -2: print("   Error: config_path encoding error")
        case -3: print("   Error: status_path is null")
        case -4: print("   Error: status_path encoding error")
        case -5: print("   Error: result_path is null")
        case -6: print("   Error: result_path encoding error")
        case -7: print("   Error: session_path is null")
        case -8: print("   Error: session_path encoding error")
        case -9: print("   Error: hash_path is null")
        case -10: print("   Error: hash_path encoding error")
        case -11: print("   Error: session_id is null")
        case -12: print("   Error: session_id encoding error")
        default: print("   Error: Unknown error code \(code)")
        }
    }

    deinit {
        // Ensure session is stopped when object is deallocated
        if isRunning {
            _ = stop()
        }
    }
}

// MARK: - Convenience Extensions

extension RustFTPBridge {
    /// Start a session with an FTPConfig object
    /// - Parameters:
    ///   - config: The FTP configuration
    ///   - baseDir: Base directory for status/result files (defaults to /tmp)
    /// - Returns: true on success, false on error
    @discardableResult
    func start(with config: FTPConfig, baseDir: String = "/tmp") -> Bool {
        // Create temporary directory for this session
        let sessionDir = "\(baseDir)/ftp_\(sessionId)"
        try? FileManager.default.createDirectory(atPath: sessionDir, withIntermediateDirectories: true)

        let configPath = "\(sessionDir)/config.json"
        let statusPath = "\(sessionDir)/status.json"
        let resultPath = "\(sessionDir)/result.json"
        let sessionPath = "\(sessionDir)/session.json"
        let hashPath = "\(sessionDir)/hashes.json"

        // Write config to file
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(config)
            try data.write(to: URL(fileURLWithPath: configPath))
        } catch {
            print("❌ Failed to write config file: \(error)")
            return false
        }

        return start(
            configPath: configPath,
            statusPath: statusPath,
            resultPath: resultPath,
            sessionPath: sessionPath,
            hashPath: hashPath
        )
    }
}
