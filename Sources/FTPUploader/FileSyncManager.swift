import Foundation
import Combine

// MARK: - FTP Status Models
struct FTPStatus: Codable {
    let configId: UInt32
    let stage: String
    let filename: String
    let progress: Double
    let timestamp: UInt64
    let fileSize: UInt64? // bytes
    
    // Phase 4: Real-time performance tracking
    let downloadSpeedMbps: Double? // Current download speed in MB/s
    let downloadTimeSecs: Double? // Download time for completed files
    
    enum CodingKeys: String, CodingKey {
        case configId = "config_id"
        case stage
        case filename
        case progress
        case timestamp
        case fileSize = "file_size"
        case downloadSpeedMbps = "download_speed_mbps"
        case downloadTimeSecs = "download_time_secs"
    }
}

// Session report from Rust
struct SessionReport: Codable {
    let sessionId: String
    let configId: String  // Changed from UInt32 to match Rust String type
    let totalFiles: Int
    let totalBytes: Int
    let totalTimeSecs: Double
    let averageSpeedMbps: Double

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case configId = "config_id"
        case totalFiles = "total_files"
        case totalBytes = "total_bytes"
        case totalTimeSecs = "total_time_secs"
        case averageSpeedMbps = "average_speed_mbps"
    }
}

// Phase 4: Real-time performance metrics
struct PerformanceMetrics: Codable {
    let totalFilesCompleted: Int
    let totalBytesDownloaded: UInt64
    let currentDownloadSpeedMbps: Double
    let averageFileSizeMB: Double
    let filesPerMinuteEstimate: Double
    let sessionDurationSeconds: Double
    let overallSpeedMbps: Double
    
    enum CodingKeys: String, CodingKey {
        case totalFilesCompleted = "total_files_completed"
        case totalBytesDownloaded = "total_bytes_downloaded"
        case currentDownloadSpeedMbps = "current_download_speed_mbps"
        case averageFileSizeMB = "average_file_size_mb"
        case filesPerMinuteEstimate = "files_per_minute_estimate"
        case sessionDurationSeconds = "session_duration_seconds"
        case overallSpeedMbps = "overall_speed_mbps"
    }
}

@MainActor
class FileSyncManager: ObservableObject {
    @Published var syncStatus = "Idle"
    @Published var syncStats = SyncStats()
    
    // Per-configuration tracking
    @Published var configSyncStatus: [UUID: String] = [:]
    @Published var configFiles: [UUID: [FTPFile]] = [:]
    @Published var configDownloadProgress: [UUID: [UUID: Double]] = [:]
    @Published var configIsSyncing: [UUID: Bool] = [:]
    @Published var configConnectionTimes: [UUID: String] = [:]
    @Published var configDownloadSpeeds: [UUID: String] = [:]
    @Published var configFileCounters: [UUID: Int] = [:] // Track downloaded file count for current session

    // Connection state tracking - separate from "is syncing"
    @Published var configConnectionState: [UUID: ConnectionState] = [:] // Actual FTP connection state
    @Published var configConnectionError: [UUID: String] = [:] // Last error message for failed connections

    // Monitor conflict tracking - separate from connection errors
    @Published var configMonitorWarning: [UUID: (level: String, message: String)?] = [:] // Monitor conflict warnings (level: "critical", "warning", "info")

    enum ConnectionState {
        case idle           // Not started
        case connecting     // Process started, attempting connection
        case connected      // FTP authentication successful
        case warning        // Non-critical issues (retries, directory not found, etc.)
        case error          // FTP authentication failed or connection lost
    }

    // Track which notification timestamps have been counted to prevent double-counting
    var configProcessedNotificationTimestamps: [UUID: Set<UInt64>] = [:]

    // Session download speed tracking
    @Published var configSessionSpeeds: [UUID: [Double]] = [:] // MB/s values for current session
    @Published var configSessionStartTime: [UUID: Date] = [:] // When current session started
    
    // Session reports from Rust
    @Published var configSessionReports: [UUID: SessionReport] = [:] // Final session statistics
    
    // Phase 4: Real-time performance tracking
    @Published var configPerformanceMetrics: [UUID: PerformanceMetrics] = [:] // Live performance data
    @Published var configFilesPerMinuteEstimate: [UUID: Double] = [:] // Realistic files/min estimates
    
    // Log parsing and status tracking
    @Published var configLogs: [UUID: [String]] = [:]
    @Published var configCurrentOperation: [UUID: String] = [:]
    @Published var configLastUpdate: [UUID: Date] = [:]

    // Sleep/wake tracking - configs that should resume after wake
    private var configsShouldResumeAfterWake: Set<UUID> = []

    // Prevent multiple simultaneous restart operations
    private var isRestartInProgress = false

    // UUID to config_id hash mapping (must match Rust's hash calculation)
    // This is critical because Swift's UUID.hashValue is not stable across calls
    private var configHashMap: [UUID: UInt32] = [:]

    private var ftpServices: [UUID: FTPService] = [:]
    private var syncTimers: [UUID: Timer] = [:]
    private var sessionPollingTimers: [UUID: Timer] = [:] // Timers to poll session file for accurate counts
    private var cancellables = Set<AnyCancellable>()

    // Static flag to ensure notification observers are only registered once
    private static var hasRegisteredObservers = false
    
    struct SyncStats {
        var totalFilesProcessed = 0
        var filesDownloaded = 0
        var filesDeleted = 0
        var failedDownloads = 0
        var lastSyncDate: Date?
    }
    
    init(ftpService: FTPService) {
        // Keep the old constructor for backward compatibility

        print("🔄 FileSyncManager initializing - ensuring NO automatic connections")
        print("🔍 DEBUG: init() called - hasRegisteredObservers = \(FileSyncManager.hasRegisteredObservers)")
        
        // Reset all sync states on initialization to prevent automatic connections
        resetAllSyncStates()
        
        // Additional cleanup on app launch to clear any residual notification files
        cleanupResidualFiles()

        // Add explicit guard to prevent any automatic processes
        print("🛡️  GUARD: All automatic sync processes are DISABLED")
        print("🛡️  GUARD: Configurations will ONLY start when Start button is pressed")

        // CRITICAL: Only register notification observers ONCE to prevent duplicate notifications
        guard !FileSyncManager.hasRegisteredObservers else {
            print("⚠️  Notification observers already registered, skipping re-registration")
            return
        }
        FileSyncManager.hasRegisteredObservers = true
        print("✅ Registering notification observers (first time only)")

        // Listen for Rust output notifications
        NotificationCenter.default.addObserver(
            forName: .rustOutputReceived,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                if let configId = notification.userInfo?["configId"] as? UUID {
                    // Phase 4: Handle performance update messages
                    if let messageType = notification.userInfo?["type"] as? String, messageType == "performance" {
                        if let message = notification.userInfo?["message"] as? String {
                            // Parse performance update from Rust
                            // Format: "📊 Performance Update: X files, Y.Y MB/s avg, Z files/min est"
                            if message.contains("📊 Performance Update:") {
                                let parts = message.split(separator: ": ").last?.split(separator: ", ")
                                
                                if let parts = parts, parts.count >= 3 {
                                    // Extract files completed
                                    if let filesStr = parts[0].split(separator: " ").first,
                                       let filesCompleted = Int(filesStr) {
                                        
                                        // Extract speed
                                        if let speedStr = parts[1].split(separator: " ").first,
                                           let speedMbps = Double(speedStr) {
                                            
                                            // Extract files per minute estimate
                                            if let fpmStr = parts[2].split(separator: " ").first,
                                               let filesPerMin = Double(fpmStr) {
                                                
                                                // Update performance metrics
                                                self?.configFilesPerMinuteEstimate[configId] = filesPerMin
                                                
                                                // Log the performance update
                                                self?.addConfigLog(configId, message: "📊 Live Performance: \(filesCompleted) files, \(String(format: "%.1f", speedMbps)) MB/s, \(String(format: "%.0f", filesPerMin)) files/min est")
                                                
                                                print("📊 Performance Update for \(configId): \(filesCompleted) files, \(speedMbps) MB/s, \(filesPerMin) files/min")
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        return
                    }
                    
                    // DEPRECATED: This old string parsing path is kept for backward compatibility
                    // but is no longer used with FFI - structured state updates are now used instead
                    // via .rustStateUpdate notification (see below)
                    if let output = notification.userInfo?["output"] as? String {
                        // Only log connection errors for debugging
                        if output.contains("Login failed") || output.contains("Error") || output.contains("Failed") {
                            self?.addConfigLog(configId, message: output)
                        }
                    }
                    
                    // Handle session report
                    if let sessionReport = notification.userInfo?["sessionReport"] as? SessionReport {
                        // Store all session reports - Rust now only sends meaningful ones
                        self?.configSessionReports[configId] = sessionReport

                        // Don't update file counter here - it's updated per file in rustDownloadSpeedUpdate
                        // NOTE: No longer adding log entries - LiveLogsView will collect logs directly
                        if sessionReport.averageSpeedMbps > 0.0 {
                            print("📊 Session report stored for config \(configId): \(sessionReport.totalFiles) files, \(String(format: "%.2f", sessionReport.averageSpeedMbps)) MB/s")
                        } else {
                            print("📊 Session report stored for config \(configId): \(sessionReport.totalFiles) files, 0.00 MB/s (no files processed)")
                        }
                    }
                }
            }
        }
        
        // Listen for file download completions from Rust
        // Rust sends this notification ONLY for actually downloaded files (not skipped)
        NotificationCenter.default.addObserver(
            forName: .rustUploadSpeedUpdate,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                if let configId = notification.userInfo?["configId"] as? UUID {
                    let filename = notification.userInfo?["filename"] as? String ?? "unknown"
                    // Increment file counter - Rust only sends this for successful downloads
                    let currentCount = self?.configFileCounters[configId] ?? 0
                    self?.configFileCounters[configId] = currentCount + 1
                    self?.addFileCompletionTime(for: configId)
                    print("📊 ✅ File download notification received for '\(filename)' - Count: \(currentCount + 1) for config \(configId)")
                }
            }
        }

        // Listen for structured state updates from Rust (PERFORMANCE: replaces string parsing)
        // SimpleRustFTPService_FFI sends these for key events: connected, scanning, waiting, error
        NotificationCenter.default.addObserver(
            forName: .rustStateUpdate,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                guard let configId = notification.userInfo?["configId"] as? UUID,
                      let state = notification.userInfo?["state"] as? String,
                      let message = notification.userInfo?["message"] as? String else {
                    return
                }

                print("🔔 State update for \(configId): \(state)")

                // Parse the message for monitor warnings and other important info
                // This ensures monitor conflict banners appear in the UI
                self?.parseLogMessage(configId: configId, message: message)

                // Update connection state and operation based on structured state
                // NOTE: We don't add logs here to reduce CPU usage and memory consumption
                // LiveLogsView will subscribe to .rustStateUpdate directly when window is open
                switch state {
                case "connected":
                    if self?.configConnectionState[configId] != .connected {
                        self?.configConnectionState[configId] = .connected
                        self?.configConnectionError[configId] = nil
                        self?.configCurrentOperation[configId] = "Connected"
                        print("🔌 Connection state: CONNECTED for config \(configId)")
                        self?.objectWillChange.send()
                        NotificationCenter.default.post(name: NSNotification.Name("SyncStatusChanged"), object: nil)
                    }

                case "scanning":
                    self?.configCurrentOperation[configId] = "Scanning files..."

                case "waiting":
                    self?.configCurrentOperation[configId] = "Waiting for next sync..."

                case "monitor_warning":
                    // Monitor warnings are handled separately via parseLogMessage
                    // They don't affect connection status - only populate the banner
                    break

                case "warning":
                    if self?.configConnectionState[configId] != .warning {
                        self?.configConnectionState[configId] = .warning
                        self?.configConnectionError[configId] = message
                        self?.configCurrentOperation[configId] = "Warning"
                        print("⚠️ Connection state: WARNING for config \(configId) - \(message)")
                        self?.objectWillChange.send()
                        NotificationCenter.default.post(name: NSNotification.Name("SyncStatusChanged"), object: nil)
                    }

                case "error":
                    if self?.configConnectionState[configId] != .error {
                        self?.configConnectionState[configId] = .error
                        self?.configConnectionError[configId] = message
                        self?.configCurrentOperation[configId] = "Error occurred"
                        print("🔌 Connection state: ERROR for config \(configId) - \(message)")
                        self?.objectWillChange.send()
                        NotificationCenter.default.post(name: NSNotification.Name("SyncStatusChanged"), object: nil)
                    }

                default:
                    break
                }
            }
        }

        // Listen for config hash registration from SimpleRustFTPService
        NotificationCenter.default.addObserver(
            forName: .configHashRegistration,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                if let configId = notification.userInfo?["configId"] as? UUID,
                   let configHash = notification.userInfo?["configHash"] as? UInt32 {
                    self?.registerConfigHash(configId, hash: configHash)
                }
            }
        }

        print("✅ FileSyncManager initialization complete - NO automatic connections enabled")
    }
    
    /// Clean up any residual files on app launch
    private func cleanupResidualFiles() {
        print("🧹 Cleaning up residual files on app launch")
        
        let appSupportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let ftpDir = appSupportDir.appendingPathComponent("FTPUploader")
        
        do {
            // Clear any existing notification files
            if FileManager.default.fileExists(atPath: ftpDir.path) {
                let fileURLs = try FileManager.default.contentsOfDirectory(at: ftpDir, includingPropertiesForKeys: nil)
                let notificationFiles = fileURLs.filter { $0.lastPathComponent.hasPrefix("notifications_") && $0.lastPathComponent.hasSuffix(".json") }
                
                for fileURL in notificationFiles {
                    try FileManager.default.removeItem(at: fileURL)
                    print("🧹 Cleaned up residual notification file: \(fileURL.path)")
                }
            }
            
            print("✅ Residual file cleanup complete")
        } catch {
            print("⚠️ Failed to clean up residual files: \(error)")
        }
    }
    
    // Helper methods for current configuration
    var isSyncing: Bool {
        return configIsSyncing.values.contains(true)
    }
    
    // Get or create FTP service for a specific configuration
    private func getFTPService(for config: FTPConfig) -> FTPService {
        if let existingService = ftpServices[config.id] {
            return existingService
        } else {
            let newService = SimpleRustFTPService_FFI()
            ftpServices[config.id] = newService
            print("🔧 Created new FTP service for config: \(config.name)")
            return newService
        }
    }
    
    func isConfigSyncing(_ configId: UUID) -> Bool {
        return configIsSyncing[configId] ?? false
    }
    
    func getConfigFiles(_ configId: UUID) -> [FTPFile] {
        return configFiles[configId] ?? []
    }
    
    func getConfigDownloadProgress(_ configId: UUID) -> [UUID: Double] {
        return configDownloadProgress[configId] ?? [:]
    }
    
    func getConfigSyncStatus(_ configId: UUID) -> String {
        return configSyncStatus[configId] ?? "Idle"
    }

    /// Get unified connection status for a specific configuration
    /// This is the single source of truth for connection state across all UI components
    func getConnectionStatus(for configId: UUID) -> ConnectionState {
        return configConnectionState[configId] ?? .idle
    }

    /// Get overall connection status across all configurations
    /// Used by menu bar icon to show global state
    /// Priority: error/warning > connected > idle
    func getOverallStatus() -> ConnectionState {
        let states = configConnectionState.values

        // HIGHEST PRIORITY: Check for CRITICAL monitor conflicts FIRST (even if connected successfully)
        // This ensures menu bar icon shows red when there are critical monitor conflicts
        for (configId, warning) in configMonitorWarning {
            if let (level, message) = warning, level == "critical" {
                print("🔴 getOverallStatus: Found CRITICAL monitor warning for \(configId) - returning .error")
                return .error  // Treat critical monitor conflicts as errors for menu bar
            }
        }

        // Second priority: any connection error or warning
        if states.contains(.error) || states.contains(.warning) {
            return states.contains(.error) ? .error : .warning
        }

        // Third priority: any connected
        if states.contains(.connected) {
            return .connected
        }

        // Fourth priority: any connecting
        if states.contains(.connecting) {
            return .connecting
        }

        // Default: idle
        return .idle
    }

    // Log parsing methods
    func getConfigLogs(_ configId: UUID) -> [String] {
        let logs = configLogs[configId] ?? []
        // Return logs in reverse order so newest appear at top
        return Array(logs.reversed())
    }
    
    /// Clear live notifications/logs for a specific configuration
    func clearConfigLogs(_ configId: UUID) {
        print("🧹 Clearing live notifications for config: \(configId)")
        configLogs[configId] = []
        objectWillChange.send()
    }
    
    /// Clear all live notifications/logs for all configurations
    func clearAllConfigLogs() {
        print("🧹 Clearing all live notifications for all configurations")
        configLogs.removeAll()
        objectWillChange.send()
    }
    
    /// Clear notification files on disk for a specific configuration
    func clearNotificationFiles(_ configId: UUID) {
        print("🧹 Clearing notification files on disk for config: \(configId)")
        
        let appSupportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let ftpDir = appSupportDir.appendingPathComponent("FTPUploader")
        let notificationFile = ftpDir.appendingPathComponent("notifications_\(configId.uuidString).json")
        
        do {
            // First try to delete the file completely
            if FileManager.default.fileExists(atPath: notificationFile.path) {
                try FileManager.default.removeItem(at: notificationFile)
                print("✅ Deleted notification file: \(notificationFile.path)")
            }
            
            // Then create a completely empty file with just an empty array
            let emptyNotifications: [String] = []
            let data = try JSONSerialization.data(withJSONObject: emptyNotifications, options: .prettyPrinted)
            try data.write(to: notificationFile)
            print("✅ Created empty notification file: \(notificationFile.path)")
            
            // Force UI update
            objectWillChange.send()
        } catch {
            print("⚠️ Failed to clear notification file: \(error)")
        }
    }
    
    /// Clear all notification files on disk for all configurations
    func clearAllNotificationFiles() {
        print("🧹 Clearing all notification files on disk")
        
        let appSupportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let ftpDir = appSupportDir.appendingPathComponent("FTPUploader")
        
        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(at: ftpDir, includingPropertiesForKeys: nil)
            let notificationFiles = fileURLs.filter { $0.lastPathComponent.hasPrefix("notifications_") && $0.lastPathComponent.hasSuffix(".json") }
            
            for fileURL in notificationFiles {
                // Delete the file completely
                try FileManager.default.removeItem(at: fileURL)
                print("✅ Deleted notification file: \(fileURL.path)")
            }
            
            // Force UI update
            objectWillChange.send()
        } catch {
            print("⚠️ Failed to clear notification files: \(error)")
        }
    }
    
    // Phase 4: Performance tracking methods
    /// Update performance metrics for a configuration based on FTP status updates
    func updatePerformanceMetrics(for configId: UUID, status: FTPStatus) {
        // Handle performance update messages from Rust
        if status.stage == "PerformanceUpdate" {
            print("📊 DEBUG: Received PerformanceUpdate - filename: '\(status.filename)'")
            
            // Parse performance data from the filename
            // Format: "Performance: X files, Y.Y MB/s, Z files/min"
            let parts = status.filename.split(separator: ": ").last?.split(separator: ", ")
            
            print("📊 DEBUG: Parsed parts: \(parts?.map { String($0) } ?? [])")
            
            if let parts = parts, parts.count >= 3 {
                // Extract files completed
                if let filesStr = parts[0].split(separator: " ").first,
                   let filesCompleted = Int(filesStr) {
                    
                    print("📊 DEBUG: Files completed: \(filesCompleted)")
                    
                    // Extract speed
                    if let speedStr = parts[1].split(separator: " ").first,
                       let speedMbps = Double(speedStr) {
                        
                        print("📊 DEBUG: Speed: \(speedMbps) MB/s")
                        
                        // Extract files per minute estimate
                        if let fpmStr = parts[2].split(separator: " ").first,
                           let filesPerMin = Double(fpmStr) {
                            
                            print("📊 DEBUG: Files per minute: \(filesPerMin)")
                            
                            // Calculate average file size from total bytes and file count
                            let totalBytes = status.fileSize ?? 0
                            let avgFileSizeMB = filesCompleted > 0 ? Double(totalBytes) / 1024.0 / 1024.0 / Double(filesCompleted) : 0.0
                            
                            let metrics = PerformanceMetrics(
                                totalFilesCompleted: filesCompleted,
                                totalBytesDownloaded: totalBytes,
                                currentDownloadSpeedMbps: speedMbps,
                                averageFileSizeMB: avgFileSizeMB,
                                filesPerMinuteEstimate: filesPerMin,
                                sessionDurationSeconds: status.downloadTimeSecs ?? 0.0,
                                overallSpeedMbps: speedMbps
                            )
                            
                            configPerformanceMetrics[configId] = metrics
                            configFilesPerMinuteEstimate[configId] = filesPerMin
                            
                            print("📊 Performance Update for \(configId): \(filesCompleted) files, \(speedMbps) MB/s, \(filesPerMin) files/min")
                            print("📊 DEBUG: Stored files per minute estimate: \(configFilesPerMinuteEstimate[configId] ?? 0)")
                        } else {
                            print("📊 DEBUG: Failed to parse files per minute from: '\(parts[2])'")
                        }
                    } else {
                        print("📊 DEBUG: Failed to parse speed from: '\(parts[1])'")
                    }
                } else {
                    print("📊 DEBUG: Failed to parse files completed from: '\(parts[0])'")
                }
            } else {
                print("📊 DEBUG: Not enough parts: \(parts?.count ?? 0)")
            }
        }
        
        // Also track individual file downloads for speed calculations
        if let fileSize = status.fileSize, let downloadTime = status.downloadTimeSecs, downloadTime > 0 {
            let speedMbps = Double(fileSize) / 1024.0 / 1024.0 / downloadTime
            
            // Update session speeds for this configuration
            if configSessionSpeeds[configId] == nil {
                configSessionSpeeds[configId] = []
            }
            configSessionSpeeds[configId]?.append(speedMbps)
            
            // Keep only last 10 speed measurements for rolling average
            if let speeds = configSessionSpeeds[configId], speeds.count > 10 {
                configSessionSpeeds[configId] = Array(speeds.suffix(10))
            }
        }
    }
    
    /// Get realistic files per second estimate for a configuration
    func getRealisticFilesPerSecond(for configId: UUID) -> Double {
        // Use a proper rolling window approach to calculate REAL recent FPS
        // This tracks actual file completion times instead of misleading cumulative averages
        
        let rollingWindowSeconds: TimeInterval = 10.0 // Look at last 10 seconds
        
        if let startTime = configSessionStartTime[configId] {
            let currentTime = Date()
            let sessionDuration = currentTime.timeIntervalSince(startTime)
            
            // For very short sessions (< 5 seconds), use simple calculation
            if sessionDuration < 5.0 {
                if let fileCount = configFileCounters[configId], fileCount > 0 {
                    let simpleFPS = Double(fileCount) / sessionDuration
                    // print("📊 Very short session FPS: \(fileCount) files in \(String(format: "%.1f", sessionDuration))s = \(String(format: "%.2f", simpleFPS)) files/sec")
                    return simpleFPS
                }
            }
            
            // For longer sessions, use rolling window approach
            if sessionDuration >= rollingWindowSeconds {
                // Calculate the cutoff time for our rolling window
                let cutoffTime = currentTime.addingTimeInterval(-rollingWindowSeconds)
                
                // Get files completed in the last rolling window
                let recentFiles = getFilesCompletedInTimeWindow(configId: configId, since: cutoffTime)
                
                if recentFiles > 0 {
                    // Calculate FPS over the rolling window
                    let rollingFPS = Double(recentFiles) / rollingWindowSeconds
                    
                    // print("📊 Rolling window FPS: \(recentFiles) files in last \(String(format: "%.1f", rollingWindowSeconds))s = \(String(format: "%.2f", rollingFPS)) files/sec")
                    
                    return rollingFPS
                } else {
                    // No recent files - check if we have any files at all
                    if let fileCount = configFileCounters[configId], fileCount > 0 {
                        // Use overall session FPS as fallback
                        let overallFPS = Double(fileCount) / sessionDuration
                        // print("📊 No recent files, using overall FPS: \(String(format: "%.2f", overallFPS)) files/sec")
                        return overallFPS
                    }
                }
            } else {
                // Session is shorter than rolling window, use cumulative
                if let fileCount = configFileCounters[configId], fileCount > 0 {
                    let cumulativeFPS = Double(fileCount) / sessionDuration
                    // print("📊 Short session FPS: \(fileCount) files in \(String(format: "%.1f", sessionDuration))s = \(String(format: "%.2f", cumulativeFPS)) files/sec")
                    return cumulativeFPS
                }
            }
        }
        
        // Fallback to performance metrics from Rust if available
        if let estimate = configFilesPerMinuteEstimate[configId], estimate > 0 {
            let fpsEstimate = estimate / 60.0
            // print("📊 Using Rust FPS estimate: \(String(format: "%.2f", fpsEstimate)) (converted from \(String(format: "%.0f", estimate)) files/min)")
            return fpsEstimate
        }
        
        // Default fallback
        // print("📊 No FPS data available, returning 0")
        return 0.0
    }
    
    // MARK: - File Completion Tracking for Accurate FPS
    
    /// Track file completion timestamps for accurate FPS calculation
    private var configFileCompletionTimes: [UUID: [Date]] = [:]

    /// Increment file counter and explicitly trigger UI updates
    func incrementFileCounter(for configId: UUID) {
        let currentCount = configFileCounters[configId] ?? 0
        configFileCounters[configId] = currentCount + 1
        // Explicitly notify observers of the change
        objectWillChange.send()
    }

    /// Add a file completion timestamp for accurate FPS tracking
    func addFileCompletionTime(for configId: UUID) {
        let now = Date()
        if configFileCompletionTimes[configId] == nil {
            configFileCompletionTimes[configId] = []
        }
        configFileCompletionTimes[configId]?.append(now)
        
        // Keep only last 1000 timestamps to prevent memory bloat
        if let times = configFileCompletionTimes[configId], times.count > 1000 {
            configFileCompletionTimes[configId] = Array(times.suffix(1000))
        }
    }
    
    /// Get the number of files completed in a specific time window
    private func getFilesCompletedInTimeWindow(configId: UUID, since: Date) -> Int {
        guard let completionTimes = configFileCompletionTimes[configId] else {
            return 0
        }

        // Count files completed since the cutoff time
        let recentFiles = completionTimes.filter { $0 >= since }.count
        return recentFiles
    }

    /// Calculate active download time (time between first and last file completion)
    /// This excludes idle time before first download and between downloads
    func getActiveDownloadTime(for configId: UUID) -> TimeInterval {
        guard let completionTimes = configFileCompletionTimes[configId],
              completionTimes.count >= 2 else {
            return 0.0
        }

        // Active time is from first file to last file completion
        let firstDownload = completionTimes.first!
        let lastDownload = completionTimes.last!
        return lastDownload.timeIntervalSince(firstDownload)
    }

    /// Get files per minute based on active download time only
    func getActiveFilesPerMinute(for configId: UUID) -> Double {
        let fileCount = configFileCounters[configId] ?? 0
        guard fileCount > 0 else { return 0.0 }

        let activeTime = getActiveDownloadTime(for: configId)
        guard activeTime > 0 else {
            // Only 1 file downloaded, no active time yet
            return 0.0
        }

        // Convert to files per minute
        return (Double(fileCount) / activeTime) * 60.0
    }

    /// Get average download speed from most recent session report
    func getSessionAverageSpeed(for configId: UUID) -> Double {
        return configSessionReports[configId]?.averageSpeedMbps ?? 0.0
    }
    
    func getConfigCurrentOperation(_ configId: UUID) -> String {
        return configCurrentOperation[configId] ?? "Idle"
    }
    
    func getConfigLastUpdate(_ configId: UUID) -> Date {
        return configLastUpdate[configId] ?? Date()
    }
    
    func getConfigSyncStartTime(_ configId: UUID) -> Date {
        return configSessionStartTime[configId] ?? Date()
    }
    
    func getConfigDownloadSpeed(_ configId: UUID) -> String {
        return configDownloadSpeeds[configId] ?? "0 KB/s"
    }
    
    func getConfigSpeedAndFileCount(_ configId: UUID) -> String {
        let speed = configDownloadSpeeds[configId] ?? "0 KB/s"
        let fileCount = configFileCounters[configId] ?? 0
        
        if fileCount > 0 && speed != "0 KB/s" {
            return "\(speed) (\(fileCount) files)"
        } else if fileCount > 0 {
            return "(\(fileCount) files)"
        } else {
            return speed
        }
    }
    
    func getConfigSessionAverageSpeed(_ configId: UUID) -> String {
        guard let speeds = configSessionSpeeds[configId], !speeds.isEmpty else {
            return "0 MB/s"
        }
        
        let averageSpeed = speeds.reduce(0.0, +) / Double(speeds.count)
        
        if averageSpeed >= 1.0 {
            return String(format: "%.2f MB/s", averageSpeed)
        } else if averageSpeed >= 0.001 {
            return String(format: "%.2f KB/s", averageSpeed * 1024.0)
        } else {
            return String(format: "%.0f B/s", averageSpeed * 1024.0 * 1024.0)
        }
    }
    
    func getLastValidSessionReport(_ configId: UUID) -> SessionReport? {
        // Only return session reports with meaningful speed (greater than 0.00)
        // This ensures we preserve the last valid speed during idle times
        if let report = configSessionReports[configId], report.averageSpeedMbps > 0.0 {
            return report
        }
        return nil
    }
    
    // Get session stats display with fallback to last valid data
    func getConfigSessionStatsDisplay(_ configId: UUID) -> String {
        if let report = configSessionReports[configId] {
            if report.averageSpeedMbps > 0.0 {
                // Current meaningful data
                let totalMB = Double(report.totalBytes) / 1024.0 / 1024.0
                let timeStr = String(format: "%.1f", report.totalTimeSecs)
                let speedStr = String(format: "%.2f", report.averageSpeedMbps)
                return "Batch Speed Average: \(speedStr) MB/s (\(report.totalFiles) files, \(String(format: "%.1f", totalMB)) MB, \(timeStr)s)"
            } else {
                // Current data has 0.00 speed, try to show last valid data
                if let lastReport = getLastValidSessionReport(configId) {
                    let totalMB = Double(lastReport.totalBytes) / 1024.0 / 1024.0
                    let timeStr = String(format: "%.1f", lastReport.totalTimeSecs)
                    let speedStr = String(format: "%.2f", lastReport.averageSpeedMbps)
                    return "Batch Speed Average: \(speedStr) MB/s (Last batch: \(lastReport.totalFiles) files, \(String(format: "%.1f", totalMB)) MB, \(timeStr)s)"
                } else {
                    // No valid speed data available, show current report info
                    let totalMB = Double(report.totalBytes) / 1024.0 / 1024.0
                    let timeStr = String(format: "%.1f", report.totalTimeSecs)
                    return "Batch Speed Average: 0.00 MB/s (\(report.totalFiles) files, \(String(format: "%.1f", totalMB)) MB, \(timeStr)s)"
                }
            }
        } else {
            return "Batch Speed Average: No data"
        }
    }
    
    func getConfigSessionTotalSpeed(_ configId: UUID) -> String {
        guard let speeds = configSessionSpeeds[configId], !speeds.isEmpty else {
            return "0 MB/s"
        }
        
        let totalSpeed = speeds.reduce(0.0, +)
        
        if totalSpeed >= 1.0 {
            return String(format: "%.2f MB/s", totalSpeed)
        } else if totalSpeed >= 0.001 {
            return String(format: "%.2f KB/s", totalSpeed * 1024.0)
        } else {
            return String(format: "%.0f B/s", totalSpeed * 1024.0 * 1024.0)
        }
    }
    
    /// Register the config_id hash for a configuration
    /// This must be called when starting a sync to establish the UUID→hash mapping
    /// that Rust uses for notification files
    func registerConfigHash(_ configId: UUID, hash: UInt32) {
        configHashMap[configId] = hash
        let tempDir = FileManager.default.temporaryDirectory.path
        print("✅ Registered config hash: UUID \(configId) → hash \(hash)")
        print("✅ Notification file will be: \(tempDir)/ftp_notifications_\(hash).jsonl")
    }

    func addConfigLog(_ configId: UUID, message: String) {
        if configLogs[configId] == nil {
            configLogs[configId] = []
        }
        configLogs[configId]?.append(message)

        // Keep only last 100 log entries per config
        if let logs = configLogs[configId], logs.count > 100 {
            configLogs[configId] = Array(logs.suffix(100))
        }

        // Update last update time
        configLastUpdate[configId] = Date()

        // Parse the log message for status updates
        parseLogMessage(configId: configId, message: message)

        // ALSO write to Rust-style notification file so it appears in Live Notifications UI
        writeNotificationToFile(configId: configId, message: message, type: "info")
    }

    /// Write a notification directly to the Rust notification file format
    /// This ensures messages appear in the Live Notifications UI
    private func writeNotificationToFile(configId: UUID, message: String, type: String) {
        // Skip empty messages
        if message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return
        }

        // CRITICAL: Use the stored hash from configHashMap, not UUID.hashValue
        // Swift's UUID.hashValue is NOT stable across calls - it changes every time!
        // We must use the same hash that was sent to Rust when starting the process
        guard let configHash = configHashMap[configId] else {
            print("⚠️ No stored hash for config \(configId), cannot write notification")
            print("⚠️ This config may not have been started yet, or mapping was lost")
            return
        }

        let tempDir = FileManager.default.temporaryDirectory.path
        let notificationFile = "\(tempDir)/ftp_notifications_\(configHash).jsonl"

        print("📝 Writing notification to file: \(notificationFile)")
        print("📝 Config ID: \(configId), Hash: \(configHash) (from stored map)")
        print("📝 Message: \(message)")

        let notification: [String: Any] = [
            "config_id": configHash,
            "notification_type": type,
            "message": message,
            "timestamp": UInt64(Date().timeIntervalSince1970 * 1000), // milliseconds
            "filename": NSNull(),
            "progress": NSNull()
        ]

        do {
            if let jsonData = try? JSONSerialization.data(withJSONObject: notification, options: []),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                let line = jsonString + "\n"

                // Append to file
                if let fileHandle = FileHandle(forWritingAtPath: notificationFile) {
                    fileHandle.seekToEndOfFile()
                    if let data = line.data(using: .utf8) {
                        fileHandle.write(data)
                    }
                    fileHandle.closeFile()
                    print("✅ Appended notification to existing file")
                } else {
                    // Create file if it doesn't exist
                    try line.write(toFile: notificationFile, atomically: true, encoding: .utf8)
                    print("✅ Created new notification file and wrote message")
                }

                // Verify file was written
                if FileManager.default.fileExists(atPath: notificationFile) {
                    if let fileSize = try? FileManager.default.attributesOfItem(atPath: notificationFile)[.size] as? UInt64 {
                        print("✅ Notification file exists, size: \(fileSize) bytes")
                    }
                } else {
                    print("❌ Notification file does NOT exist after write!")
                }
            }
        } catch {
            print("❌ Error writing notification: \(error)")
        }

        // Track file completions for FPS calculation
        // Rust sends "Downloaded {filename}" in notifications and "✅ Downloaded: ..." in logs
        if type == "success" && (message.contains("Downloaded ") || message.contains("Downloaded:")) {
            // Increment file counter for this download completion
            incrementFileCounter(for: configId)

            // Track completion timestamp for accurate FPS calculation
            addFileCompletionTime(for: configId)

            let newCount = configFileCounters[configId] ?? 0
            print("📊 File downloaded (notification) - File counter for \(configId): \(newCount)")
        }
    }
    
    private func parseLogMessage(configId: UUID, message: String) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Check if this log message belongs to this config by looking for [ConfigName] prefix
        // Since we don't have direct access to config names, we'll look for any [Name] prefix
        // and assume it's for this config if it has a prefix format
        let hasPrefix = trimmed.hasPrefix("[") && trimmed.contains("]")
        
        // If this message has a prefix format, remove it for processing
        let cleanMessage: String
        if hasPrefix {
            // Remove the [ConfigName] prefix
            if let endIndex = trimmed.firstIndex(of: "]") {
                let afterBracket = trimmed.index(after: endIndex)
                cleanMessage = String(trimmed[afterBracket...]).trimmingCharacters(in: .whitespaces)
            } else {
                cleanMessage = trimmed
            }
        } else {
            // No prefix, use as-is (backward compatibility)
            cleanMessage = trimmed
        }
        
        // Parse monitor conflict warnings from Rust (new format without emoji)
        // Also handle "clear" messages to remove warnings when conflicts resolve
        if cleanMessage == "clear" {
            // Clear any existing monitor warning for this config
            if configMonitorWarning[configId] != nil {
                print("🧹 CLEARING monitor warning for config \(configId)")
                configMonitorWarning[configId] = nil
                objectWillChange.send()

                // Update menu bar icon if needed
                NotificationCenter.default.post(name: NSNotification.Name("SyncStatusChanged"), object: nil)
            }
        } else if cleanMessage.contains("Multiple FTPUploaders detected") ||
           cleanMessage.contains("Another FTPUploader detected") ||
           cleanMessage.contains("Other FTPUploaders detected") {

            // Determine severity based on content
            let level: String
            if cleanMessage.contains("CONFLICT") || cleanMessage.contains("Multiple DELETE-mode") {
                level = "critical"
                print("🚨 Monitor conflict CRITICAL detected for config \(configId)")
            } else if cleanMessage.contains("WARNING") {
                level = "warning"
                print("⚠️  Monitor conflict WARNING detected for config \(configId)")
            } else {
                level = "info"
                print("ℹ️  Monitor conflict INFO detected for config \(configId)")
            }

            configMonitorWarning[configId] = (level: level, message: cleanMessage)
            print("✅ SET configMonitorWarning[\(configId)] = (level: \(level), message: \(cleanMessage.prefix(50))...)")
            print("📊 configMonitorWarning now has \(configMonitorWarning.count) entries")
            objectWillChange.send()

            // IMPORTANT: Trigger menu bar icon update for critical conflicts
            if level == "critical" {
                print("🔴 Posting SyncStatusChanged for critical monitor conflict")
                NotificationCenter.default.post(name: NSNotification.Name("SyncStatusChanged"), object: nil)
            }
        }

        // CRITICAL: Monitor log for connection state changes
        // Detect successful connection
        if cleanMessage.contains("Connected") && !cleanMessage.contains("Not Connected") {
            configConnectionState[configId] = .connected
            configConnectionError[configId] = nil
            print("🔌 Connection state: CONNECTED for config \(configId) (via log)")
            objectWillChange.send()
        }
        // Detect login/auth failures
        else if cleanMessage.contains("Login failed") || cleanMessage.contains("LOGIN REJECTION") ||
                cleanMessage.contains("authentication failed") || cleanMessage.contains("Auth failed") {
            let errorMsg = cleanMessage.contains("Login failed") ? cleanMessage : "Authentication failed"
            configConnectionState[configId] = .error
            configConnectionError[configId] = errorMsg
            print("🔌 Connection state: ERROR for config \(configId) - \(errorMsg) (via log)")
            objectWillChange.send()
        }

        // Update current operation based on log content
        if cleanMessage.contains("Starting sync for config") {
            configCurrentOperation[configId] = "Starting sync..."
        } else if cleanMessage.contains("Found") && cleanMessage.contains("files in") {
            configCurrentOperation[configId] = "Scanning files..."
        } else if cleanMessage.contains("Downloading") {
            configCurrentOperation[configId] = "Downloading files..."
        } else if cleanMessage.contains("Downloaded") {
            configCurrentOperation[configId] = "Downloaded successfully"
            // NOTE: Counter is now incremented via direct notification in rustDownloadSpeedUpdate observer
            // No need to parse logs for counter - Rust sends "success" notification only for actual downloads
        } else if cleanMessage.contains("Error") || cleanMessage.contains("Failed") {
            configCurrentOperation[configId] = "Error occurred"
        } else if cleanMessage.contains("Sync completed") {
            configCurrentOperation[configId] = "Sync completed"
        }
        
        // Extract file progress information
        if cleanMessage.contains("Downloading") {
            // Extract filename from "Downloading filename..."
            if let filename = extractFilename(from: cleanMessage) {
                updateFileProgress(configId: configId, filename: filename, progress: 0.5) // Start at 50%
            }
        } else if cleanMessage.contains("Downloaded") {
            // Extract filename from "Downloaded filename..."
            if let filename = extractFilename(from: cleanMessage) {
                updateFileProgress(configId: configId, filename: filename, progress: 1.0) // Complete
            }
        }
        
        // Extract download speed information
        if cleanMessage.contains("Speed:") || cleanMessage.contains("speed:") {
            if let speed = extractDownloadSpeed(from: cleanMessage) {
                configDownloadSpeeds[configId] = speed
            }
        } else if cleanMessage.contains("B/s") || cleanMessage.contains("KB/s") || cleanMessage.contains("MB/s") {
            // Look for speed patterns like "1.5 MB/s" or "500 B/s"
            if let speed = extractSpeedFromText(from: cleanMessage) {
                configDownloadSpeeds[configId] = speed
            }
        }
        
        // Track download speeds for session average
        if cleanMessage.contains("Complete") || cleanMessage.contains("downloaded") {
            // Try to extract download speed from the JSON status
            if let speed = extractDownloadSpeedFromJSON(from: cleanMessage, configId: configId) {
                configSessionSpeeds[configId]?.append(speed)
                
                // Update current download speed display
                configDownloadSpeeds[configId] = String(format: "%.2f MB/s", speed)
            }
        }
    }
    
    private func extractFilename(from message: String) -> String? {
        // Extract filename from various log formats
        if message.contains("Downloading") {
            let parts = message.components(separatedBy: "Downloading ")
            if parts.count > 1 {
                return parts[1].trimmingCharacters(in: .whitespaces)
            }
        } else if message.contains("Downloaded") {
            let parts = message.components(separatedBy: "Downloaded ")
            if parts.count > 1 {
                return parts[1].trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }
    
    private func extractDownloadSpeed(from message: String) -> String? {
        // Extract speed from Rust output format: "⬇️ [Thread-1] filename.jpg downloaded at 1.25 MB/s"
        if message.contains("downloaded at") {
            let parts = message.components(separatedBy: "downloaded at")
            if parts.count > 1 {
                let speedPart = parts[1].trimmingCharacters(in: .whitespaces)
                // Extract just the speed value (e.g., "1.25 MB/s")
                if let range = speedPart.range(of: #"[\d.]+ [KMGT]?B/s"#, options: .regularExpression) {
                    return String(speedPart[range])
                }
            }
        }
        
        // Fallback: Extract speed from "Speed: 1.5 MB/s" format (if any)
        if message.contains("Speed:") {
            let parts = message.components(separatedBy: "Speed:")
            if parts.count > 1 {
                return parts[1].trimmingCharacters(in: .whitespaces)
            }
        } else if message.contains("speed:") {
            let parts = message.components(separatedBy: "speed:")
            if parts.count > 1 {
                return parts[1].trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }
    
    private func extractDownloadSpeedFromJSON(from message: String, configId: UUID) -> Double? {
        // download_speed field has been removed from Rust status updates
        // This function now returns nil since speed information is no longer available
        return nil
    }
    
    private func extractSpeedFromText(from message: String) -> String? {
        // Look for speed patterns in the text
        let words = message.components(separatedBy: .whitespaces)
        for word in words {
            if word.contains("B/s") || word.contains("KB/s") || word.contains("MB/s") || word.contains("GB/s") {
                return word
            }
        }
        return nil
    }
    
    private func estimateDownloadSpeed(from message: String, configId: UUID) -> Double? {
        // Estimate download speed based on file processing time
        // This is a fallback since Rust isn't sending detailed speed logs
        
        // Get the session start time
        guard let sessionStart = configSessionStartTime[configId] else { return nil }
        
        // Calculate elapsed time since session start
        let elapsed = Date().timeIntervalSince(sessionStart)
        if elapsed < 1.0 { return nil } // Need at least 1 second
        
        // Estimate based on typical file sizes and processing patterns
        // For JPG files, assume average size of 2-5 MB
        let estimatedFileSizeMB = 3.5 // Average JPG size in MB
        
        // Calculate estimated speed: size / time
        let estimatedSpeed = estimatedFileSizeMB / elapsed
        
        // Add some realistic variation (±30%)
        let variation = Double.random(in: 0.7...1.3)
        return estimatedSpeed * variation
    }
    
    private func updateFileProgress(configId: UUID, filename: String, progress: Double) {
        // Find the file by name and update its progress
        if let files = configFiles[configId] {
            for file in files {
                if file.name == filename {
                    configDownloadProgress[configId]?[file.id] = progress
                    break
                }
            }
        }
    }
    
    func startSync(config: FTPConfig) {
        print("▶️▶️▶️ START SYNC CALLED ▶️▶️▶️")
        print("🔍 DEBUG: startSync called for config: \(config.name)")
        print("🔍 DEBUG: Config ID: \(config.id)")
        print("🔍 DEBUG: Server: \(config.serverAddress)")
        print("🔍 DEBUG: Sync Interval: \(config.syncInterval)s")
        print("🔍 DEBUG: Call stack: \(Thread.callStackSymbols.prefix(5).joined(separator: "\n"))")
        print("🛡️  GUARD: Configuration start requested")

        // Check if this is a demo configuration
        if config.serverAddress == "demo.example.com" {
            print("🎬 Demo configuration detected - restarting demo mode")
            DemoModeManager.shared.restartDemoMode(config: config, syncManager: self)
            return
        }

        // Security check - ensure this is being called from a legitimate source
        // We'll trust that if this method is called, it's from legitimate user interaction
        // The call stack analysis was too fragile and blocked legitimate button presses
        print("✅ SECURITY CHECK: Assuming legitimate user interaction")
        
        if config.localSourcePath.isEmpty {
            print("⚠️  No local source path configured for config: \(config.name)")
            return
        }
        
        // Only cancel tasks for this specific config, don't affect others
        if configIsSyncing[config.id] == true {
            print("⚠️  Config \(config.name) is already running, stopping it first")
            stopConfigSync(configId: config.id)
        }
        
        // Clear previous live notifications to start fresh
        clearConfigLogs(config.id)
        
        // Clear notification files on disk to start fresh (clears main UI notifications)
        clearNotificationFiles(config.id)
        
        // Initialize or continue session statistics tracking
        // This logic is now handled by the NotificationCenter observer
        
        // Track connection start time
        updateConnectionTime(for: config)
        
        // Set sync start time for connection timer
        configSessionStartTime[config.id] = Date()
        
        // Initialize session speed tracking
        configSessionStartTime[config.id] = Date()
        
        // Initialize file counter for this session
        configFileCounters[config.id] = 0
        configSessionSpeeds[config.id] = []

        // Clear completion timestamps for accurate FPS tracking
        configFileCompletionTimes[config.id] = []

        // Clear processed notification timestamps to start fresh count
        configProcessedNotificationTimestamps[config.id] = Set<UInt64>()
        
        // Delete previous session file to start fresh batch
        deleteSessionFile(for: config.id)
        
        // Clear session reports to show new batch has started
        configSessionReports[config.id] = nil
        
        // CRITICAL: Reset file counter FIRST before any notifications can arrive
        configFileCounters[config.id] = 0
        print("🔄 Reset file counter to 0 for new sync session (BEFORE sync starts)")

        // CRITICAL: Clear logs from previous session to prevent old entries from showing
        configLogs[config.id] = []
        print("🧹 Cleared logs for new sync session")

        print("🔄 Starting sync for config: \(config.name) (ID: \(config.id))")
        print("🔄 Server: \(config.serverAddress)")
        print("📤 Remote destination: \(config.remoteDestination)")
        print("⏱️  Sync interval: \(config.syncInterval)s")
        print("🔍 FTP HANDLES STABILIZATION - Swift stabilization disabled")
        print("📁 Local source path: \(config.localSourcePath)")

        // NOTE: No longer adding log entries here - LiveLogsView will collect logs directly from notifications
        // This prevents logs from accumulating in memory when window is closed

        // Mark as syncing (process is running)
        configIsSyncing[config.id] = true
        print("✅ MARKED AS SYNCING: configIsSyncing[\(config.id)] = true")
        print("🔍 Current configIsSyncing state: \(configIsSyncing)")
        configSyncStatus[config.id] = "Starting..."

        // Set connection state to "connecting" (not yet connected)
        configConnectionState[config.id] = .connecting
        configConnectionError[config.id] = nil // Clear any previous error
        print("🔌 Connection state: connecting (waiting for FTP authentication)")

        // CRITICAL: Force UI update to notify all observers (including MenuBarIconView)
        // SwiftUI doesn't auto-detect dictionary value changes, only dictionary replacement
        objectWillChange.send()
        print("🔔 Sent objectWillChange notification - menu bar icon should update")

        // Notify AppDelegate to update menu bar icon
        NotificationCenter.default.post(name: NSNotification.Name("SyncStatusChanged"), object: nil)

        // REMOVED: Session file polling is no longer needed
        // Session reports now come directly from Rust via NotificationCenter
        // This eliminates duplicate updates and reduces CPU usage

        // Don't start automatic sync timers - sync only runs once when Start is pressed
        // The user must press Start again to trigger another sync operation

        // Perform the sync now (since user pressed Start)
        Task {
            await performSync(config: config)
        }

        // REMOVED: All periodic timers - they cause excessive CPU usage
        // - UI refresh timer (every 2s)
        // - Connection time update timer (every 5s)
        // UI updates are triggered by actual data changes from Rust via notifications
    }
    
    // MARK: - Manual Sync
    func manualSync(config: FTPConfig) {
        guard configIsSyncing[config.id] == true else {
            print("⚠️  Config \(config.name) is not currently running")
            return
        }
        
        print("🔄 Manual sync triggered for config: \(config.name)")
        Task {
            await performSync(config: config)
        }
    }
    
    // MARK: - State Management
    private func resetAllSyncStates() {
        print("🔄 Resetting all sync states on app initialization")
        print("🛡️  GUARD: Ensuring ALL automatic processes are DISABLED")
        
        // Stop all existing timers
        for (configId, timer) in syncTimers {
            timer.invalidate()
            print("⏹️  Stopped sync timer for config: \(configId)")
        }
        syncTimers.removeAll()
        
        // Reset all sync states
        for configId in configIsSyncing.keys {
            configIsSyncing[configId] = false
            configSyncStatus[configId] = "Idle"
            configSessionStartTime[configId] = nil
            configConnectionTimes[configId] = "Not connected"
            configDownloadSpeeds[configId] = nil
        }
        
        // Clear any existing FTP services to prevent automatic connections
        for (configId, ftpService) in ftpServices {
            print("🔌 Disconnecting FTP service for config: \(configId)")
            ftpService.disconnect()
        }
        ftpServices.removeAll()
        
        // Clear all live notifications to start with a clean slate
        clearAllConfigLogs()
        
        // Clear all notification files on disk to start with a clean slate
        clearAllNotificationFiles()
        
        print("✅ All sync states reset to idle")
        print("✅ All FTP services disconnected")
        print("✅ All live notifications cleared")
        print("✅ All notification files cleared")
        print("🛡️  GUARD: NO configurations can run automatically")
        print("🛡️  GUARD: Only manual Start button presses will start configurations")
    }
    
    // Delete session file for a specific config
    private func deleteSessionFile(for configId: UUID) {
        let sessionFile = AppFileManager.shared.getSessionFilePath(for: configId)

        do {
            try FileManager.default.removeItem(atPath: sessionFile)
            print("🗑️ Deleted session file for config: \(configId)")
        } catch {
            print("⚠️ Failed to delete session file for config \(configId): \(error)")
        }
    }

    private func startSessionFilePolling(for configId: UUID) {
        // Stop any existing timer
        sessionPollingTimers[configId]?.invalidate()

        // Poll every second to read session file and update file count
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.pollSessionFile(for: configId)
        }

        sessionPollingTimers[configId] = timer
        print("📊 Started session file polling for config: \(configId)")
    }

    private func stopSessionFilePolling(for configId: UUID) {
        sessionPollingTimers[configId]?.invalidate()
        sessionPollingTimers.removeValue(forKey: configId)
        print("📊 Stopped session file polling for config: \(configId)")
    }

    private func pollSessionFile(for configId: UUID) {
        let sessionFile = AppFileManager.shared.getSessionFilePath(for: configId)

        guard FileManager.default.fileExists(atPath: sessionFile) else {
            return
        }

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: sessionFile))
            let sessionReport = try JSONDecoder().decode(SessionReport.self, from: data)

            // Update the session report which the UI reads
            Task { @MainActor in
                self.configSessionReports[configId] = sessionReport
            }
        } catch {
            // Ignore errors - session file might not be ready yet
        }
    }

    func stopConfigSync(configId: UUID) {
        print("⏹️  STOP BUTTON: Stopping sync for config: \(configId)")
        print("⏹️  STOP BUTTON: This MUST call stopFTPProcess to create shutdown file")
        
        // Stop session statistics tracking
        // This logic is now handled by the NotificationCenter observer
        
        // Add log entry for UI display
        addConfigLog(configId, message: "⏹️ Stop button pressed - stopping sync...")
        
        // Stop timers for this specific config
        syncTimers[configId]?.invalidate()
        syncTimers.removeValue(forKey: configId)

        // REMOVED: Session file polling - no longer used
        // stopSessionFilePolling(for: configId)

        // Reset status for this config
        configIsSyncing[configId] = false
        configSyncStatus[configId] = "Idle"

        // Reset connection state
        configConnectionState[configId] = .idle
        configConnectionError[configId] = nil
        configMonitorWarning[configId] = nil  // Clear monitor warnings when stopping
        print("🔌 Connection state reset to idle for config \(configId)")
        print("🧹 Cleared monitor warning for config \(configId)")

        // Force UI update
        objectWillChange.send()

        // Notify AppDelegate to update menu bar icon
        NotificationCenter.default.post(name: NSNotification.Name("SyncStatusChanged"), object: nil)
        configCurrentOperation[configId] = "Idle"

        // CRITICAL: Force UI update to notify all observers (including MenuBarIconView)
        // SwiftUI doesn't auto-detect dictionary value changes, only dictionary replacement
        objectWillChange.send()
        print("🔔 Sent objectWillChange notification - menu bar icon should update to orange")
        
        // Clear sync start time for connection timer
        configSessionStartTime[configId] = nil
        
        // Clear download speed and file counter
        configDownloadSpeeds[configId] = nil
        configFileCounters[configId] = 0  // Reset file counter for new session
        
        // Clear session speed tracking (but keep session reports for display)
        configSessionSpeeds[configId] = nil
        configSessionStartTime[configId] = nil
        
        // Keep session reports so speed display remains visible in UI
        // configSessionReports[configId] = nil  // Commented out to preserve speed display
        
        // Clear connection time for this config
        let connectionKey = "\(configId)_start"
        UserDefaults.standard.removeObject(forKey: connectionKey)
        
        Task { @MainActor in
            self.configConnectionTimes[configId] = "Not connected"
        }
        
        // Clear live notifications/logs for this specific config
        clearConfigLogs(configId)
        
        // Clear notification files on disk for this config (clears main UI notifications)
        clearNotificationFiles(configId)
        
        // Force UI update to reflect all the cleared state
        objectWillChange.send()
        
        // CRITICAL: Stop the Rust FTP process for this specific config
        if let ftpService = ftpServices[configId] {
            if let rustService = ftpService as? SimpleRustFTPService_FFI {
                print("🛑 Stopping Rust FTP process for config: \(configId)")
                rustService.stopFTPProcess(configId: configId)
            }
            ftpServices.removeValue(forKey: configId)
        }
        
        // Only disconnect FTP if no other configs are running
        let otherConfigsRunning = configIsSyncing.values.contains(true)
        if !otherConfigsRunning {
            print("🔌 No other configs running, disconnecting FTP")
        } else {
            print("🔌 Other configs still running, keeping FTP connection")
        }
        
        print("✅ Sync stopped for config: \(configId)")
    }
    
    func stopSync() {
        // Alias for stopAllSync for backward compatibility
        stopAllSync()
    }
    
    func stopAllSync() {
        print("⏹️  Stopping all sync operations")
        
        // Terminate all processes when stopping all syncs
        terminateAllProcesses()
    }
    
    func terminateAllProcesses() {
        print("🛑 Terminating all FTP processes")
        
        // Stop all FTP services and terminate their processes
        for (configId, ftpService) in ftpServices {
            if let rustService = ftpService as? SimpleRustFTPService_FFI {
                print("🛑 Terminating process for config: \(configId)")
                rustService.terminateAllProcesses()
            }
        }
        
        // Clear all services
        ftpServices.removeAll()
        
        print("✅ All FTP processes terminated")
        
        // Stop all timers
        for (configId, timer) in syncTimers {
            timer.invalidate()
            print("⏹️  Stopped sync timer for config: \(configId)")
        }
        syncTimers.removeAll()
        
        // Stop all configs
        for configId in configIsSyncing.keys {
            if configIsSyncing[configId] == true {
                stopConfigSync(configId: configId)
            }
        }
        
        // Clear all live notifications since all syncs are stopped
        clearAllConfigLogs()
        
        // Clear all notification files on disk (clears main UI notifications)
        clearAllNotificationFiles()
        
        // Clear all remaining UI state
        configSyncStatus.removeAll()
        configCurrentOperation.removeAll()
        configConnectionTimes.removeAll()
        configDownloadSpeeds.removeAll()
        configFileCounters.removeAll()
        configSessionSpeeds.removeAll()
        configSessionStartTime.removeAll()
        
        // Reset global status
        syncStatus = "Idle"
        print("✅ All sync operations stopped")
    }
    
    private func performSync(config: FTPConfig) async {
        print("🔍 Starting FTP process...")
        await MainActor.run {
            syncStatus = "Starting FTP process..."
        }
        
        // Get the Rust FTP service and start processing
        let ftpService = getFTPService(for: config)
        
        if let rustService = ftpService as? SimpleRustFTPService_FFI {
            print("🚀 Starting FTP process for config: \(config.name)")
            
            // Start the Rust FTP process with status callbacks
            rustService.startFTPProcess(config: config) { [weak self] configId, stage, filename, progress in
                Task { @MainActor in
                    // Update UI with real-time status from Rust
                    self?.configSyncStatus[config.id] = "\(stage): \(filename)"
                    
                    // Update progress if we have a filename
                    if !filename.isEmpty {
                        print("🔄 FTP Status [\(config.name)]: \(stage) → \(filename) (\(Int(progress * 100))%)")
                    } else {
                        print("🔄 FTP Status [\(config.name)]: \(stage) (\(Int(progress * 100))%)")
                    }
                    
                    // Update connection time display
                    if stage == "Connected" {
                        self?.updateConnectionTime(for: config)
                        // Start updating connection time display
                        self?.startConnectionTimeUpdates(for: config)
                    }
                    

                }
            }
            
            // Update sync status
            await MainActor.run {
                configSyncStatus[config.id] = "FTP process started"
                syncStatus = "FTP process started for \(config.name)"
            }
        } else {
            print("❌ Expected SimpleRustFTPService_FFI but got: \(type(of: ftpService))")
            await MainActor.run {
                syncStatus = "Service type mismatch"
            }
        }
    }
    
    // MARK: - File Processing (BACKEND HANDLES DOWNLOADING AND STABILIZATION)
    
    // Backend now handles all file processing directly - no Swift processing needed
    
    // MARK: - Connection Time Tracking
    
    private func updateConnectionTime(for config: FTPConfig) {
        let connectionKey = "\(config.id)_start"
        UserDefaults.standard.set(Date(), forKey: connectionKey)
        configConnectionTimes[config.id] = "Connected"
    }
    
    private func updateConnectionTimeDisplay(for config: FTPConfig) async {
        let connectionKey = "\(config.id)_start"
        if let startTime = UserDefaults.standard.object(forKey: connectionKey) as? Date {
            let duration = Date().timeIntervalSince(startTime)
            let hours = Int(duration) / 3600
            let minutes = Int(duration) % 3600 / 60
            let seconds = Int(duration) % 60
            
            let timeString: String
            if hours > 0 {
                timeString = String(format: "%02d:%02d:%02d", hours, minutes, seconds)
            } else {
                timeString = String(format: "%02d:%02d", minutes, seconds)
            }
            
            await MainActor.run {
                configConnectionTimes[config.id] = timeString
            }
        }
    }
    
    private func startConnectionTimeUpdates(for config: FTPConfig) {
        // Start a timer to update connection time display every second
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.updateConnectionTimeDisplay(for: config)
            }
        }
        
        // Store the timer so we can invalidate it later
        syncTimers[config.id] = timer
    }
    
    // MARK: - Utility Methods
    
    func getParallelDownloadStatus(config: FTPConfig) -> String {
        let configCurrentFiles = configFiles[config.id] ?? []
        let activeDownloads = configCurrentFiles.filter { $0.downloadStatus == .downloading }.count
        let queuedDownloads = configCurrentFiles.filter { $0.downloadStatus == .monitoring }.count
        return "Downloads: \(activeDownloads) active, \(queuedDownloads) queued"
    }
    
    func getServerDetectionInfo(config: FTPConfig) -> (isRumpus: Bool, serverType: String) {
        // Check if server banner indicates Rumpus
        let isRumpus = config.serverBanner.lowercased().contains("rumpus")
        let serverType = config.serverBanner.isEmpty ? "Standard FTP Server" : config.serverBanner
        return (isRumpus: isRumpus, serverType: serverType)
    }
    
    func showStabilizationStatus(configId: UUID? = nil) {
        if let configId = configId {
            // Show status for specific config
            let configCurrentFiles = configFiles[configId] ?? []
            let pendingFiles = configCurrentFiles.filter { $0.downloadStatus == .pending }
            let stableFiles = configCurrentFiles.filter { $0.isStabilized }
            let downloadingFiles = configCurrentFiles.filter { $0.downloadStatus == .downloading }
            let completedFiles = configCurrentFiles.filter { $0.downloadStatus == .completed }
            
            print("📊 Stabilization Status for Config \(configId):")
            print("   📄 Total files: \(configCurrentFiles.count)")
            print("   ⏳ Pending: \(pendingFiles.count)")
            print("   📏 Stable: \(stableFiles.count)")
            print("   📥 Downloading: \(downloadingFiles.count)")
            print("   ✅ Completed: \(completedFiles.count)")
        } else {
            // Show status for all configs
            print("📊 Overall Stabilization Status:")
            for (configId, files) in configFiles {
                let pendingFiles = files.filter { $0.downloadStatus == .pending }
                let stableFiles = files.filter { $0.isStabilized }
                let downloadingFiles = files.filter { $0.downloadStatus == .downloading }
                let completedFiles = files.filter { $0.downloadStatus == .completed }
                
                print("   📁 Config \(configId): \(files.count) total, \(pendingFiles.count) pending, \(stableFiles.count) stable, \(downloadingFiles.count) downloading, \(completedFiles.count) completed")
            }
        }
        print("================================")
    }
    
    // MARK: - Utility Methods for UI Compatibility
    
    func clearStuckFiles(config: FTPConfig) {
        print("🧹 Clearing stuck files for config: \(config.name)")
        
        // Reset files for this configuration
        configFiles[config.id] = []
        configDownloadProgress[config.id] = [:]
        
        // Reset sync status
        configSyncStatus[config.id] = "Stuck files cleared, ready to sync"
        syncStatus = "\(config.name): Stuck files cleared, ready to sync"
        
        print("✅ Stuck files cleared for \(config.name)")
    }
    
    func validateDownloadQueue(config: FTPConfig) {
        let configCurrentFiles = configFiles[config.id] ?? []
        let downloadingFiles = configCurrentFiles.filter { $0.downloadStatus == .downloading }
        let monitoringFiles = configCurrentFiles.filter { $0.downloadStatus == .monitoring }
        
        print("📊 Download queue validation for config \(config.id):")
        print("   - Downloading: \(downloadingFiles.count)")
        print("   - Monitoring (ready): \(monitoringFiles.count)")
        print("   - Note: FTP backend handles actual downloading")
    }
    
    func manualStabilizationCheck(config: FTPConfig) {
        print("🔧 Manual stabilization check not implemented - FTP backend handles stabilization")
        configSyncStatus[config.id] = "Manual stabilization not implemented - FTP backend handles stabilization"
    }

    /// Pauses all active configurations (called before system sleep)
    /// This cleanly stops Rust processes to avoid zombie/stuck processes after wake
    func pauseAllActiveConfigurations() {
        print("⏸️⏸️⏸️ pauseAllActiveConfigurations() CALLED ⏸️⏸️⏸️")
        print("⏸️ Pausing active configurations before system sleep")
        print("🔍 FULL configIsSyncing dictionary: \(configIsSyncing)")
        print("🔍 Dictionary has \(configIsSyncing.count) entries")

        // Find all configs that are currently syncing - BEFORE we stop them
        let activeConfigIds = configIsSyncing.filter { $0.value == true }.map { $0.key }

        print("⏸️ Found \(activeConfigIds.count) active configuration(s) to pause")
        print("⏸️ Active config IDs: \(activeConfigIds)")

        if activeConfigIds.isEmpty {
            print("ℹ️ No active configurations to pause")
            // DON'T clear configsShouldResumeAfterWake here!
            // It may have been populated by a previous call (IOKit fires before NSWorkspace)
            print("ℹ️ Keeping existing resume list: \(configsShouldResumeAfterWake)")
            return
        }

        // CRITICAL: Remember which configs to restart BEFORE calling stopConfigSync
        // because stopConfigSync clears the configIsSyncing state
        configsShouldResumeAfterWake = Set(activeConfigIds)
        print("⏸️ SAVED \(configsShouldResumeAfterWake.count) configs for resume: \(configsShouldResumeAfterWake)")

        // Add prominent log entries BEFORE stopping to show sleep is happening
        for configId in activeConfigIds {
            addConfigLog(configId, message: "")
            addConfigLog(configId, message: "💤💤💤 SYSTEM GOING TO SLEEP 💤💤💤")
            addConfigLog(configId, message: "⏸️  Stopping FTP processes cleanly...")
            addConfigLog(configId, message: "⏸️  Configuration will resume automatically after wake")
            addConfigLog(configId, message: "")
        }

        // FORCE KILL all Rust processes before sleep (don't wait for graceful shutdown)
        for configId in activeConfigIds {
            print("⏸️ Force killing Rust process for config: \(configId)")

            // FORCE TERMINATE the Rust FTP process for this specific config
            // We use terminateAllProcesses() instead of stopFTPProcess() because:
            // - stopFTPProcess() creates a shutdown file and waits for graceful exit
            // - System sleep happens immediately, Rust process may not see shutdown file
            // - Rust process survives sleep as zombie and conflicts with new process after wake
            if let ftpService = ftpServices[configId] {
                if let rustService = ftpService as? SimpleRustFTPService_FFI {
                    print("🛑 FORCE TERMINATING Rust FTP process for config: \(configId)")
                    rustService.terminateAllProcesses() // Force kill, don't wait
                }
                ftpServices.removeValue(forKey: configId)
            }

            // Stop timers for this specific config
            syncTimers[configId]?.invalidate()
            syncTimers.removeValue(forKey: configId)

            // Reset status for this config - CRITICAL: Set to false to update UI
            print("⏸️ Setting configIsSyncing[\(configId)] = false")
            configIsSyncing[configId] = false
            configSyncStatus[configId] = "Paused (sleeping)"
            configCurrentOperation[configId] = "Paused for system sleep"

            // Clear sync start time
            configSessionStartTime[configId] = nil

            print("⏸️ Config \(configId) state updated: isSyncing=\(configIsSyncing[configId] ?? false), status=\(configSyncStatus[configId] ?? "nil")")
        }

        print("⏸️ DEBUG: After pause loop, configIsSyncing state:")
        for (id, syncing) in configIsSyncing {
            print("  - Config \(id): isSyncing = \(syncing)")
        }

        // Extra paranoia: Kill ANY rust_ftp processes that might be running
        // CRITICAL: Move to background thread to avoid blocking UI
        print("🛑 Running system-wide rust_ftp process cleanup...")
        Task.detached {
            let task = Process()
            task.launchPath = "/usr/bin/killall"
            task.arguments = ["-9", "rust_ftp"]
            task.standardOutput = Pipe()
            task.standardError = Pipe()
            try? task.run()
            task.waitUntilExit()
            if task.terminationStatus == 0 {
                print("✅ Killed any remaining rust_ftp processes")
            } else {
                print("ℹ️ No additional rust_ftp processes found to kill")
            }
        }

        // CRITICAL: Clean up shutdown files so processes can restart cleanly after wake
        // Move to background thread to avoid blocking UI
        print("🧹 Cleaning up shutdown files to allow clean restart after wake...")
        Task.detached {
            let tempDir = FileManager.default.temporaryDirectory.path
            do {
                let fileURLs = try FileManager.default.contentsOfDirectory(atPath: tempDir)
                let shutdownFiles = fileURLs.filter { $0.hasSuffix(".shutdown") }

                for filename in shutdownFiles {
                    let fullPath = "\(tempDir)/\(filename)"
                    try? FileManager.default.removeItem(atPath: fullPath)
                    print("🗑️ Removed shutdown file before sleep: \(filename)")
                }

                if shutdownFiles.isEmpty {
                    print("ℹ️ No shutdown files found to clean")
                } else {
                    print("✅ Cleaned \(shutdownFiles.count) shutdown file(s) before sleep")
                }
            } catch {
                print("⚠️ Error cleaning shutdown files: \(error)")
            }
        }

        // CRITICAL: Force multiple UI updates to ensure UI sees the change
        print("⏸️ Forcing UI update to show paused state...")
        objectWillChange.send()

        // Double-send on main thread to ensure UI updates
        DispatchQueue.main.async { [weak self] in
            self?.objectWillChange.send()
            print("✅ UI update sent from main thread")
        }

        print("✅ All active configurations paused cleanly - will resume on wake")
        print("✅ configsShouldResumeAfterWake = \(configsShouldResumeAfterWake)")
    }

    /// Restarts all configurations that were running (called after system wake OR network change)
    func restartActiveConfigurations() {
        print("🔄🔄🔄 restartActiveConfigurations() CALLED 🔄🔄🔄")
        print("🔄 Thread: \(Thread.current)")
        print("🔄 Is main thread: \(Thread.isMainThread)")
        print("🔄 Restarting active configurations")

        // CRITICAL: Prevent multiple simultaneous restart operations
        if isRestartInProgress {
            print("⚠️ WARNING: Restart already in progress, ignoring duplicate call")
            print("⚠️ This likely means both NSWorkspace.didWakeNotification AND failsafe fired")
            return
        }

        isRestartInProgress = true
        print("🔒 Set restart lock to prevent duplicate operations")

        // CRITICAL: Kill processes and clean up FIRST, before attempting restart
        // This must complete BEFORE we proceed to avoid conflicts
        Task { @MainActor in
            // STEP 1: Kill ALL rust_ftp processes to ensure clean slate
            await Task.detached {
                print("🛑 STEP 1: Killing ALL rust_ftp processes to ensure clean slate...")
                let killTask = Process()
                killTask.launchPath = "/usr/bin/killall"
                killTask.arguments = ["-9", "rust_ftp"]
                killTask.standardOutput = Pipe()
                killTask.standardError = Pipe()
                try? killTask.run()
                killTask.waitUntilExit()

                if killTask.terminationStatus == 0 {
                    print("✅ Killed all rust_ftp processes")
                } else {
                    print("ℹ️ No rust_ftp processes were running")
                }

                // CRITICAL: Clean up any residual shutdown files that would prevent restart
                print("🧹 STEP 1.5: Cleaning up shutdown files to prevent immediate exit...")
                let tempDir = FileManager.default.temporaryDirectory.path
                do {
                    let fileURLs = try FileManager.default.contentsOfDirectory(atPath: tempDir)
                    let shutdownFiles = fileURLs.filter { $0.hasSuffix(".shutdown") }

                    for filename in shutdownFiles {
                        let fullPath = "\(tempDir)/\(filename)"
                        try? FileManager.default.removeItem(atPath: fullPath)
                        print("🗑️ Removed shutdown file: \(filename)")
                    }

                    if shutdownFiles.isEmpty {
                        print("ℹ️ No shutdown files found to clean")
                    } else {
                        print("✅ Cleaned \(shutdownFiles.count) shutdown file(s)")
                    }
                } catch {
                    print("⚠️ Error cleaning shutdown files: \(error)")
                }

                // Give kernel time to clean up processes
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            }.value // CRITICAL: .value forces us to await completion before proceeding

            // NOW we can safely proceed to restart configs
            // Try to use configs marked for resume (from sleep/wake)
            // If that's empty, find currently running configs
            var configsToResume = Array(self.configsShouldResumeAfterWake)

            if configsToResume.isEmpty {
                print("🔄 STEP 2: No configs in resume list, checking for currently syncing configs...")
                // Find configs that were marked as syncing before we killed processes
                configsToResume = self.configIsSyncing.filter { $0.value == true }.map { $0.key }
                print("🔄 Found \(configsToResume.count) currently syncing configs")
            } else {
                print("🔄 STEP 2: Using \(configsToResume.count) configs from resume list")
            }

            print("🔄 Config IDs to resume: \(configsToResume)")

            if configsToResume.isEmpty {
                print("⚠️⚠️⚠️ NO CONFIGURATIONS TO RESTART ⚠️⚠️⚠️")
                print("⚠️ This means no configs were running when restart was called")
                print("⚠️ Releasing restart lock and returning")
                self.isRestartInProgress = false
                return
            }

            print("🔄 STEP 3: Will restart \(configsToResume.count) configuration(s) with fresh processes")

            // Load configurations from Keychain (not JSON file anymore)
            print("🔄 Loading configurations from Keychain...")
            let configsArray = ConfigurationStorage.shared.loadConfigurations()

            if configsArray.isEmpty {
                print("❌ Could not load configurations for restart (Keychain returned empty)")
                self.configsShouldResumeAfterWake.removeAll()
                self.isRestartInProgress = false
                return
            }

            print("🔄 Loaded \(configsArray.count) configurations from Keychain")

            // Add prominent log entries to show wake is happening
            for configId in configsToResume {
                self.addConfigLog(configId, message: "")
                self.addConfigLog(configId, message: "⏰⏰⏰ SYSTEM WOKE FROM SLEEP ⏰⏰⏰")
                self.addConfigLog(configId, message: "🛑 Killed all old FTP processes")
                self.addConfigLog(configId, message: "⏳ Waiting 5 seconds for network to stabilize...")
                self.addConfigLog(configId, message: "🔄 Fresh FTP process will start automatically")
                self.addConfigLog(configId, message: "")

                self.configSyncStatus[configId] = "Resuming after wake"
                self.configCurrentOperation[configId] = "Resuming after wake"

                // Keep configIsSyncing as false during resume to show "Waking from Sleep" status
                self.configIsSyncing[configId] = false
            }

            // Force UI update to show resuming state BEFORE restarting
            print("🔄 STEP 4: Forcing UI update to show 'Waking from Sleep' state...")
            self.objectWillChange.send()

            // Keep the "Waking from Sleep" state visible for the full 5 second network delay
            // Don't sleep here - let it show naturally during the restart delay

            // CRITICAL: Copy the list for restart, but DON'T clear the master list yet
            // We'll clear it AFTER the restart completes to avoid race conditions
            let configsToRestartNow = configsToResume
            print("🔄 Copied \(configsToRestartNow.count) configs for restart (keeping resume list until complete)")

            // Restart each config that was paused - but add countdown messages first
            var restartCount = 0
            for configId in configsToRestartNow {
                if let config = configsArray.first(where: { $0.id == configId }) {
                    print("▶️▶️▶️ RESTARTING IN 5 SECONDS: \(config.name) (ID: \(configId))")

                    // Add countdown notifications so user knows it's working
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                        self?.addConfigLog(configId, message: "⏳ Starting in 4 seconds...")
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                        self?.addConfigLog(configId, message: "⏳ Starting in 3 seconds...")
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                        self?.addConfigLog(configId, message: "⏳ Starting in 2 seconds...")
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { [weak self] in
                        self?.addConfigLog(configId, message: "⏳ Starting in 1 second...")
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
                        self?.addConfigLog(configId, message: "▶️ Starting FTP process NOW...")

                        // Start fresh Rust process with new network connections after 5s delay
                        self?.startSync(config: config)

                        print("✅ Restart initiated for: \(config.name)")
                        print("✅ After restart: configIsSyncing[\(configId)] = \(self?.configIsSyncing[configId] ?? false)")

                        // Clear this config from the resume list after successful restart
                        self?.configsShouldResumeAfterWake.remove(configId)
                        print("✅ Removed \(configId) from resume list after successful restart")
                    }

                    restartCount += 1
                } else {
                    print("⚠️ Could not find config \(configId) in loaded configurations")
                }
            }

            // Force another UI update after all configs restarted
            print("🔄 Forcing final UI update after restart...")
            self.objectWillChange.send()

            // Send update on main thread as well
            DispatchQueue.main.async { [weak self] in
                self?.objectWillChange.send()
                print("✅ Final UI update sent from main thread")
            }

            print("✅✅✅ Active configurations restart complete - restarted \(restartCount) config(s)")
            print("✅ UI should now show configs as Connected/Running")

            // Debug: Print final state
            print("🔍 Final configIsSyncing state after restart:")
            for (id, syncing) in self.configIsSyncing {
                print("  - Config \(id): isSyncing = \(syncing)")
            }

            // CRITICAL: Clear the restart lock after a delay to allow all async operations to complete
            // We delay by 6 seconds (5s network delay + 1s buffer) to ensure restart is fully complete
            DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) { [weak self] in
                self?.isRestartInProgress = false
                print("🔓 Cleared restart lock - restart operation complete")
            }
        } // End of Task { @MainActor in ...
    }
}
