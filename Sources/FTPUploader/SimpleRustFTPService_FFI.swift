//
//  SimpleRustFTPService_FFI.swift
//  FTPUploader
//
//  FFI-based version of SimpleRustFTPService using statically-linked Rust library
//  Replaces Process spawning with direct FFI calls to librust_ftp.a
//

import Foundation
import AppKit

// Notification name for Rust output
extension Notification.Name {
    static let rustOutputReceived = Notification.Name("rustOutputReceived")
    static let rustUploadSpeedUpdate = Notification.Name("rustUploadSpeedUpdate")
    static let rustStateUpdate = Notification.Name("rustStateUpdate") // Structured state updates (connected, scanning, error, etc.)
    static let appSystemNotification = Notification.Name("appSystemNotification")
    static let configHashRegistration = Notification.Name("configHashRegistration")
}

// Simple service that communicates with Rust via FFI
@MainActor
class SimpleRustFTPService_FFI: FTPService {
    private var isProcessing = false
    private var statusTimer: Timer?
    private var statusCallback: ((UInt32, String, String, Double) -> Void)?
    private var currentBridge: RustFTPBridge?
    private var currentConfig: FTPConfig?

    private var lastStatusUpdate: Date?
    private var lastStatusContent: String?
    private var cyclingStartTime: Date?
    private var seenFiles: Set<String> = []
    private let stuckTimeoutSeconds: TimeInterval = 30.0
    private let cyclingTimeoutSeconds: TimeInterval = 45.0

    override init() {
        super.init()
        // Initialize Rust FFI library once at startup
        RustFTPBridge.initialize()
    }

    override func testConnection(config: FTPConfig) async throws -> ConnectionTestResult {
        // For now, just return success - actual testing would require implementation
        return ConnectionTestResult(success: true, serverType: "FTP Service (FFI)", isRumpus: false, details: "Ready to process", serverBanner: "FTP Service via Rust FFI")
    }

    override func disconnect() {
        // Not used - Rust handles disconnection
    }

    // Main function to start Rust FTP processing via FFI
    func startFTPProcess(config: FTPConfig, statusCallback: @escaping (UInt32, String, String, Double) -> Void) {
        print("========================================")
        print("🚀🚀🚀 START FTP PROCESS CALLED (FFI) 🚀🚀🚀")
        print("🛡️  GUARD: startFTPProcess called - using FFI bridge")
        print("========================================")

        guard !isProcessing else {
            print("⚠️ FTP process already running")
            return
        }

        // CRITICAL: Clear any existing shutdown file before starting
        let shutdownFile = AppFileManager.shared.getStatusFilePath(for: config.id) + ".shutdown"
        if FileManager.default.fileExists(atPath: shutdownFile) {
            do {
                try FileManager.default.removeItem(atPath: shutdownFile)
                print("🧹 Cleared existing shutdown file: \(shutdownFile)")
            } catch {
                print("⚠️ Failed to clear shutdown file: \(error)")
            }
        }

        isProcessing = true
        self.statusCallback = statusCallback
        self.currentConfig = config

        // Notifications are now delivered via direct FFI callbacks - no timer needed!

        // Generate a new session ID for this FTP process
        let sessionId = UUID().uuidString
        config.sessionId = sessionId

        print("🚀 Starting FTP process (FFI) for config: \(config.name)")
        print("🔍 Debug: Generated session ID: \(sessionId)")

        // Create temporary config file
        let configData = createConfigData(from: config)
        let configFile = createTempConfigFile(with: configData)

        print("📁 Config file: \(configFile)")

        // Start Rust via FFI instead of Process
        startRustViaFFI(configFile: configFile, config: config, sessionId: sessionId)

        // Start status monitoring
        startStatusMonitoring(configFile: configFile, config: config)
    }

    // Function to stop the FTP process via FFI
    func stopFTPProcess(configId: UUID) {
        print("🛑 Stopping FTP process (FFI) for config: \(configId)")

        // Create shutdown file to signal Rust to stop syncing this config
        let shutdownFile = AppFileManager.shared.getStatusFilePath(for: configId) + ".shutdown"
        do {
            try "shutdown".write(toFile: shutdownFile, atomically: true, encoding: .utf8)
            print("🛑 Created shutdown file: \(shutdownFile)")
        } catch {
            print("⚠️ Failed to create shutdown file: \(error)")
        }

        // Unregister config hash
        let configHash = RustFTPBridge.computeStableHash(from: configId.uuidString)
        RustFTPBridge.unregisterConfigHash(configHash)

        // Stop the FFI session
        if let bridge = currentBridge {
            print("🛑 Stopping Rust FFI session")
            _ = bridge.stop()
            currentBridge = nil
        }

        // Stop accessing security-scoped download directory
        currentConfig?.stopAccessingDirectory()

        // Reset state for this specific config
        isProcessing = false
        statusTimer?.invalidate()
        statusTimer = nil
        statusCallback = nil
        currentConfig = nil

        // Post process completion notification
        NotificationCenter.default.post(
            name: .rustOutputReceived,
            object: nil,
            userInfo: [
                "configId": configId,
                "processCompleted": true,
                "isError": false
            ]
        )

        print("✅ FTP process (FFI) terminated")
    }

    // Function to terminate all processes (called when app quits)
    func terminateAllProcesses() {
        print("🛑 Terminating all Rust FFI sessions for app shutdown")

        if let bridge = currentBridge {
            print("🛑 Stopping Rust FFI session")
            _ = bridge.stop()
            currentBridge = nil
        }

        // Clean up state
        isProcessing = false
        statusTimer?.invalidate()
        statusTimer = nil
        statusCallback = nil

        // Shutdown the Rust FFI library
        RustFTPBridge.shutdown()

        print("✅ All FFI sessions terminated for app shutdown")
    }

    private func createConfigData(from config: FTPConfig) -> [String: Any] {
        let configData: [String: Any] = [
            "server_address": config.serverAddress,
            "port": config.port,
            "username": config.username,
            "password": config.password,
            "remote_destination": config.remoteDestination,
            "local_source_path": config.localSourcePath,
            "respect_file_paths": config.respectFilePaths,
            "sync_interval": UInt64(max(1, Int(config.syncInterval * 1000))),
            "stabilization_interval": UInt64(config.stabilizationInterval * 1000),
            "upload_aggressiveness": UInt32(config.uploadAggressiveness.rawValue),
            "auto_tune_aggressiveness": config.autoTuneAggressiveness,
            "config_id": config.id.uuidString, // Use UUID string (stable across restarts)
            "config_name": config.name,
            "session_id": config.sessionId
        ]

        print("🔧 Sending to FTP backend (FFI) - syncInterval: \(config.syncInterval)s")
        print("🔧 Sending to FTP backend (FFI) - stabilizationInterval: \(config.stabilizationInterval)s")
        print("🔧 Sending to FTP backend (FFI) - uploadAggressiveness: \(config.uploadAggressiveness.rawValue) connections")

        return configData
    }

    private func createTempConfigFile(with configData: [String: Any]) -> String {
        let tempDir = AppFileManager.shared.tempFilesDirectory
        let configFile = tempDir.appendingPathComponent("ftp_config_\(UUID().uuidString).json")

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: configData, options: .prettyPrinted)
            try jsonData.write(to: configFile)
            print("✅ Config file created: \(configFile.path)")
        } catch {
            print("❌ Failed to create config file: \(error)")
        }

        return configFile.path
    }

    private func startRustViaFFI(configFile: String, config: FTPConfig, sessionId: String) {
        Task.detached {
            let configHash = RustFTPBridge.computeStableHash(from: config.id.uuidString)
            print("🚀 DEBUG: Starting Rust via FFI for config '\(config.name)' (ID: \(config.id), Hash: \(configHash))")

            // CRITICAL: Register the config hash with FileSyncManager
            await MainActor.run {
                NotificationCenter.default.post(
                    name: .configHashRegistration,
                    object: nil,
                    userInfo: [
                        "configId": config.id,
                        "configHash": configHash
                    ]
                )
            }

            // Notifications are now delivered via direct FFI callbacks - no cleanup needed!

            print("🔍 ========== RUST FFI LAUNCH ==========")
            print("🔍 Config file: \(configFile)")

            // Get file paths for Rust FFI
            let statusFile = AppFileManager.shared.getStatusFilePath(for: config.id)
            let resultFile = AppFileManager.shared.getResultFilePath(for: config.id)
            let sessionFile = AppFileManager.shared.getSessionFilePath(for: config.id)
            let hashFile = AppFileManager.shared.getHashFilePath(for: config.id)

            print("🔍 Status file: \(statusFile)")
            print("🔍 Result file: \(resultFile)")
            print("🔍 Session file: \(sessionFile)")
            print("🔍 Hash file: \(hashFile)")

            // CRITICAL: Start accessing security-scoped download directory
            config.startAccessingDirectory()

            // Register config hash with RustFTPBridge for notification routing
            RustFTPBridge.registerConfigHash(configHash, for: config.id)

            // Create RustFTPBridge and start session
            let bridge = RustFTPBridge(sessionId: sessionId)

            let success = bridge.start(
                configPath: configFile,
                statusPath: statusFile,
                resultPath: resultFile,
                sessionPath: sessionFile,
                hashPath: hashFile
            )

            if success {
                print("✅ Rust FFI session started successfully")

                // Store bridge reference
                await MainActor.run {
                    self.currentBridge = bridge
                }
            } else {
                print("❌ Failed to start Rust FFI session")

                await MainActor.run {
                    self.isProcessing = false
                    self.statusCallback?(UInt32(config.id.hashValue & 0xFFFFFFFF), "Error", "Failed to start FFI session", 0.0)
                }
            }
        }
    }

    private func startStatusMonitoring(configFile: String, config: FTPConfig) {
        let statusFile = AppFileManager.shared.getStatusFilePath(for: config.id)
        let resultFile = AppFileManager.shared.getResultFilePath(for: config.id)
        let sessionFile = AppFileManager.shared.getSessionFilePath(for: config.id)

        // CRITICAL: Remove stale result file from previous runs to prevent premature completion detection
        if FileManager.default.fileExists(atPath: resultFile) {
            try? FileManager.default.removeItem(atPath: resultFile)
            print("🧹 Cleared stale result file: \(resultFile)")
        }

        print("🔍 Status monitoring started for config: \(config.name)")

        lastStatusUpdate = Date()
        lastStatusContent = nil
        cyclingStartTime = nil
        seenFiles.removeAll()

        statusTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkStatus(statusFile: statusFile, resultFile: resultFile, sessionFile: sessionFile, config: config)
            }
        }
    }

    private func checkStatus(statusFile: String, resultFile: String, sessionFile: String, config: FTPConfig) {
        // Check for status updates
        if let statusData = try? Data(contentsOf: URL(fileURLWithPath: statusFile)),
           let status = try? JSONSerialization.jsonObject(with: statusData) as? [String: Any],
           let stage = status["stage"] as? String,
           let filename = status["filename"] as? String,
           let progress = status["progress"] as? Double {

            let currentStatusContent = "\(stage): \(filename) (\(Int(progress * 100))%)"
            let now = Date()

            // Detect cycling pattern - but ignore empty filenames (no files to upload is normal)
            if !filename.isEmpty && seenFiles.contains(filename) {
                if cyclingStartTime == nil {
                    cyclingStartTime = now
                    print("🔄 CYCLING DETECTED: File \(filename) seen before")
                } else if let cyclingStart = cyclingStartTime,
                         now.timeIntervalSince(cyclingStart) > cyclingTimeoutSeconds {
                    print("⚠️ CYCLING TIMEOUT: Terminating...")
                    self.stopFTPProcess(configId: config.id)
                    return
                }
            } else if !filename.isEmpty {
                seenFiles.insert(filename)
                cyclingStartTime = nil
            } else {
                // Empty filename = no files to process, reset cycling detection
                cyclingStartTime = nil
            }

            // Check if stuck - but only during active operations, not when idle/scanning
            if currentStatusContent != lastStatusContent {
                lastStatusUpdate = now
                lastStatusContent = currentStatusContent
            } else if let lastUpdate = lastStatusUpdate,
                     now.timeIntervalSince(lastUpdate) > stuckTimeoutSeconds {
                // Only trigger stuck timeout during active uploads, not when idle
                // Idle states: Scanning, Complete, Waiting, Connected, No files
                let idleStages = ["Scanning", "Complete", "Waiting", "Connected", "Finished", "No files"]
                let isIdle = idleStages.contains { stage.contains($0) } || filename.isEmpty

                if !isIdle {
                    print("⚠️ STUCK TIMEOUT: Terminating (stuck on \(stage): \(filename))...")
                    self.stopFTPProcess(configId: config.id)
                    return
                }
                // Reset the timer for idle states so we don't keep checking
                lastStatusUpdate = now
            }

            self.statusCallback?(UInt32(config.id.hashValue & 0xFFFFFFFF), stage, filename, progress)
        }

        // Check for completion
        if let resultData = try? Data(contentsOf: URL(fileURLWithPath: resultFile)),
           let result = try? JSONSerialization.jsonObject(with: resultData) as? [String: Any],
           let success = result["success"] as? Bool {

            if success {
                self.statusCallback?(UInt32(config.id.hashValue & 0xFFFFFFFF), "Completed", "Process finished successfully", 1.0)
            } else {
                let message = result["message"] as? String ?? "Unknown error"
                self.statusCallback?(UInt32(config.id.hashValue & 0xFFFFFFFF), "Error", message, 0.0)
            }

            self.isProcessing = false
            self.statusTimer?.invalidate()
            self.statusTimer = nil

            // Read and report session statistics
            do {
                let sessionData = try Data(contentsOf: URL(fileURLWithPath: sessionFile))
                let sessionReport = try JSONDecoder().decode(SessionReport.self, from: sessionData)
                print("📊 Session file read: \(sessionReport.totalFiles) files, \(sessionReport.averageSpeedMbps) MB/s")
                NotificationCenter.default.post(
                    name: .rustOutputReceived,
                    object: nil,
                    userInfo: [
                        "configId": config.id,
                        "sessionReport": sessionReport
                    ]
                )
            } catch {
                print("⚠️ Failed to read session file: \(error)")
                // Try to show raw content for debugging
                if let rawData = try? Data(contentsOf: URL(fileURLWithPath: sessionFile)),
                   let rawString = String(data: rawData, encoding: .utf8) {
                    print("⚠️ Raw session file content: \(rawString.prefix(500))")
                }
            }

            // Clean up temp files
            self.cleanupTempFiles(for: config.id)
        }
    }

    private func cleanupTempFiles(for configId: UUID) {
        AppFileManager.shared.cleanupTempFiles(for: configId)
        print("🧹 Cleaned up temp files")
    }

    func isCurrentlyProcessing() -> Bool {
        return isProcessing
    }

    func cleanup() {
        isProcessing = false
        statusTimer?.invalidate()
        statusTimer = nil
        statusCallback = nil
    }

    // MARK: - Notification System (REMOVED - no longer needed)
    // All notification file writing code has been removed for performance
    // LiveLogsView now gets logs directly from FileSyncManager.configLogs (in-memory)

    // MARK: - Direct FFI Notification Callbacks
    // Notifications are now delivered directly from Rust via FFI callbacks
    // No file I/O needed - instant delivery with zero overhead!

    deinit {
        isProcessing = false
        statusTimer?.invalidate()
        statusTimer = nil
        statusCallback = nil
    }
}

// MARK: - Rust Notification Structure

struct RustNotification: Codable {
    let config_id: UInt32
    let notification_type: String
    let message: String
    let timestamp: UInt64
    let filename: String?
    let progress: Double?
}
