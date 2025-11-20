import Foundation

class FTPConfig: Codable, Identifiable, ObservableObject, @unchecked Sendable {
    @Published var id = UUID()
    @Published var name: String
    @Published var serverAddress: String
    @Published var username: String
    @Published var password: String
    @Published var port: Int
    @Published var localDownloadPath: String
    @Published var syncDirectories: [String]
    @Published var syncInterval: TimeInterval
    @Published var stabilizationInterval: TimeInterval
    @Published var lastSyncDate: Date?
    @Published var connectionStatus: ConnectionStatus = .disconnected

    // Security-scoped bookmark for sandboxed apps (App Store builds)
    var directoryBookmark: Data?

    // File handling options
    @Published var respectFilePaths: Bool = true  // Maintain directory structure in local download
    @Published var downloadMode: DownloadMode = .deleteAfterDownload  // Download and Delete vs Download and Keep
    
    // Download performance options
    @Published var downloadAggressiveness: DownloadAggressiveness = .moderate
    @Published var autoTuneAggressiveness: Bool = true  // Enable/disable automatic aggressiveness tuning
    
    // Server-specific options
    @Published var serverBanner: String = ""     // Store server banner for detection
    
    // Connection and performance tracking
    @Published var connectionStartTime: Date?
    @Published var lastDownloadSpeed: Double = 0.0 // bytes per second
    @Published var lastDownloadedFile: String = ""
    @Published var lastDownloadTime: Date?
    
    // Session tracking
    @Published var sessionId: String = ""

    // Menu bar app options
    @Published var runOnLaunch: Bool = false  // Auto-start this config when app launches

    // Predefined sync interval options
    static let syncIntervalOptions: [TimeInterval] = [0.1, 0.5, 1, 5, 15, 30, 3600, 7200] // 0.1s, 0.5s, 1s, 5s, 15s, 30s, 1hr, 2hr
    static let syncIntervalLabels = ["0.1s", "0.5s", "1s", "5s", "15s", "30s", "1hr", "2hr"]
    
    // Predefined stabilization interval options
    static let stabilizationIntervalOptions: [TimeInterval] = [0, 5, 15, 30, 60] // None, 5s, 15s, 30s, 1min
    static let stabilizationIntervalLabels = ["None", "5s", "15s", "30s", "1min"]

    // Helper to get recommended stabilization interval based on sync interval
    var recommendedStabilizationInterval: TimeInterval {
        // For very fast sync intervals (< 1s), recommend no stabilization to avoid blocking
        if syncInterval < 1.0 {
            return 0
        }
        // For fast sync intervals (1-10s), recommend minimal stabilization
        else if syncInterval < 10.0 {
            return 0
        }
        // For slower sync intervals, allow some stabilization
        else {
            return 5
        }
    }
    
    init() {
        self.name = ""
        self.serverAddress = ""
        self.username = ""
        self.password = ""
        self.port = 21
        self.localDownloadPath = ""
        self.syncDirectories = []
        self.syncInterval = 1 // 1 second default (much faster than 5s)
        self.stabilizationInterval = 0 // 0 seconds default (no stabilization for fast sync)
        self.downloadMode = .deleteAfterDownload // Default to delete after download
        self.downloadAggressiveness = .moderate // Default to moderate aggressiveness
        self.autoTuneAggressiveness = true // Default to auto-tuning enabled
    }
    
    init(name: String, serverAddress: String, username: String, password: String, port: Int = 21) {
        self.name = name
        self.serverAddress = serverAddress
        self.username = username
        self.password = password
        self.port = port
        self.localDownloadPath = ""
        self.syncDirectories = []
        self.syncInterval = 1 // 1 second default (much faster than 5s)
        self.stabilizationInterval = 5 // 5 seconds default (changed from 0)
        self.downloadMode = .deleteAfterDownload // Default to delete after download
        self.downloadAggressiveness = .moderate // Default to moderate aggressiveness
        self.autoTuneAggressiveness = true // Default to auto-tuning enabled
    }
    
    enum ConnectionStatus: String, Codable, CaseIterable {
        case disconnected = "Disconnected"
        case connecting = "Connecting"
        case connected = "Connected"
        case failed = "Connection Failed"
    }
    
    enum DownloadMode: String, Codable, CaseIterable {
        case deleteAfterDownload = "delete"
        case keepAfterDownload = "keep"
    }
    
    enum DownloadAggressiveness: Int, Codable, CaseIterable {
        case conservative = 3
        case moderate = 10
        case aggressive = 20
        case extreme = 50
        case maximum = 100
        case ultra = 150
        case extreme_max = 200
        
        var displayName: String {
            switch self {
            case .conservative: return "Conservative (3 connections)"
            case .moderate: return "Moderate (10 connections)"
            case .aggressive: return "Aggressive (20 connections)"
            case .extreme: return "Extreme (50 connections)"
            case .maximum: return "Maximum (100 connections)"
            case .ultra: return "Ultra (150 connections)"
            case .extreme_max: return "Extreme Max (200 connections)"
            }
        }
        
        var shortName: String {
            switch self {
            case .conservative: return "Conservative"
            case .moderate: return "Moderate"
            case .aggressive: return "Aggressive"
            case .extreme: return "Extreme"
            case .maximum: return "Maximum"
            case .ultra: return "Ultra"
            case .extreme_max: return "Extreme Max"
            }
        }
        
        var connectionCount: Int {
            return self.rawValue
        }
        
        var connectionDelay: TimeInterval {
            switch self {
            case .conservative: return 3.0    // Conservative: 3 second delay
            case .moderate: return 1.5       // Moderate: 1.5 second delay
            case .aggressive: return 0.5     // Aggressive: 0.5 second delay
            case .extreme: return 0.2        // Extreme: 0.2 second delay
            case .maximum: return 0.1        // Maximum: 0.1 second delay
            case .ultra: return 0.05         // Ultra: 0.05 second delay
            case .extreme_max: return 0.025  // Extreme Max: 0.025 second delay
            }
        }
        
        var timeoutSeconds: Int {
            switch self {
            case .conservative: return 60    // Conservative: 60 second timeout
            case .moderate: return 45        // Moderate: 45 second timeout
            case .aggressive: return 30      // Aggressive: 30 second timeout
            case .extreme: return 20         // Extreme: 20 second timeout
            case .maximum: return 15         // Maximum: 15 second timeout
            case .ultra: return 10           // Ultra: 10 second timeout
            case .extreme_max: return 8      // Extreme Max: 8 second timeout
            }
        }
        
        var description: String {
            switch self {
            case .conservative: return "Slower but more reliable. Best for unstable servers or when you want to be gentle on the FTP server."
            case .moderate: return "Balanced speed and reliability. Good for most servers and typical use cases."
            case .aggressive: return "Maximum speed but may stress unstable servers. Use only with reliable, high-capacity FTP servers."
            case .extreme: return "Very high speed with minimal delays. Use only with very reliable, high-capacity FTP servers that can handle heavy load."
            case .maximum: return "Maximum possible speed with minimal overhead. Use only with enterprise-grade FTP servers that are designed for extreme concurrent loads."
            case .ultra: return "Ultra-high speed with minimal delays. Use only with enterprise-grade FTP servers that are designed for ultra-high concurrent loads."
            case .extreme_max: return "Extreme maximum speed with minimal overhead. Use only with enterprise-grade FTP servers that are designed for extreme maximum concurrent loads."
            }
        }
    }
    
    // MARK: - Codable Implementation for @Published properties
    enum CodingKeys: String, CodingKey {
        case id, name, serverAddress, username, password, port, localDownloadPath, syncDirectories
        case syncInterval, stabilizationInterval, lastSyncDate, connectionStatus
        case respectFilePaths, downloadMode, downloadAggressiveness, autoTuneAggressiveness, serverBanner, connectionStartTime
        case lastDownloadSpeed, lastDownloadedFile, lastDownloadTime, sessionId
        case directoryBookmark, runOnLaunch
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        serverAddress = try container.decode(String.self, forKey: .serverAddress)
        username = try container.decode(String.self, forKey: .username)
        password = try container.decode(String.self, forKey: .password)
        port = try container.decode(Int.self, forKey: .port)
        localDownloadPath = try container.decode(String.self, forKey: .localDownloadPath)
        syncDirectories = try container.decode([String].self, forKey: .syncDirectories)
        syncInterval = try container.decode(TimeInterval.self, forKey: .syncInterval)
        stabilizationInterval = try container.decode(TimeInterval.self, forKey: .stabilizationInterval)
        lastSyncDate = try container.decodeIfPresent(Date.self, forKey: .lastSyncDate)
        connectionStatus = try container.decode(ConnectionStatus.self, forKey: .connectionStatus)
        respectFilePaths = try container.decode(Bool.self, forKey: .respectFilePaths)
        downloadMode = try container.decode(DownloadMode.self, forKey: .downloadMode)
        downloadAggressiveness = try container.decodeIfPresent(DownloadAggressiveness.self, forKey: .downloadAggressiveness) ?? .moderate
        autoTuneAggressiveness = try container.decodeIfPresent(Bool.self, forKey: .autoTuneAggressiveness) ?? true
        serverBanner = try container.decode(String.self, forKey: .serverBanner)
        connectionStartTime = try container.decodeIfPresent(Date.self, forKey: .connectionStartTime)
        lastDownloadSpeed = try container.decode(Double.self, forKey: .lastDownloadSpeed)
        lastDownloadedFile = try container.decode(String.self, forKey: .lastDownloadedFile)
        lastDownloadTime = try container.decodeIfPresent(Date.self, forKey: .lastDownloadTime)
        sessionId = try container.decodeIfPresent(String.self, forKey: .sessionId) ?? ""
        directoryBookmark = try container.decodeIfPresent(Data.self, forKey: .directoryBookmark)
        runOnLaunch = try container.decodeIfPresent(Bool.self, forKey: .runOnLaunch) ?? false
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(serverAddress, forKey: .serverAddress)
        try container.encode(username, forKey: .username)
        try container.encode(password, forKey: .password)
        try container.encode(port, forKey: .port)
        try container.encode(localDownloadPath, forKey: .localDownloadPath)
        try container.encode(syncDirectories, forKey: .syncDirectories)
        try container.encode(syncInterval, forKey: .syncInterval)
        try container.encode(stabilizationInterval, forKey: .stabilizationInterval)
        try container.encodeIfPresent(lastSyncDate, forKey: .lastSyncDate)
        try container.encode(connectionStatus, forKey: .connectionStatus)
        try container.encode(respectFilePaths, forKey: .respectFilePaths)
        try container.encode(downloadMode, forKey: .downloadMode)
        try container.encode(downloadAggressiveness, forKey: .downloadAggressiveness)
        try container.encode(autoTuneAggressiveness, forKey: .autoTuneAggressiveness)
        try container.encode(serverBanner, forKey: .serverBanner)
        try container.encodeIfPresent(connectionStartTime, forKey: .connectionStartTime)
        try container.encode(lastDownloadSpeed, forKey: .lastDownloadSpeed)
        try container.encode(lastDownloadedFile, forKey: .lastDownloadedFile)
        try container.encodeIfPresent(lastDownloadTime, forKey: .lastDownloadTime)
        try container.encode(sessionId, forKey: .sessionId)
        try container.encodeIfPresent(directoryBookmark, forKey: .directoryBookmark)
        try container.encode(runOnLaunch, forKey: .runOnLaunch)
    }
    
    // MARK: - Helper Methods for Saving
    
    /// Creates a clean copy of the configuration data for saving
    /// This bypasses any potential issues with @Published and Codable integration
    func createSaveableCopy() -> FTPConfig {
        let copy = FTPConfig()
        copy.id = self.id
        copy.name = self.name
        copy.serverAddress = self.serverAddress
        copy.username = self.username
        copy.password = self.password
        copy.port = self.port
        copy.localDownloadPath = self.localDownloadPath
        copy.syncDirectories = self.syncDirectories
        copy.syncInterval = self.syncInterval
        copy.stabilizationInterval = self.stabilizationInterval
        copy.lastSyncDate = self.lastSyncDate
        copy.connectionStatus = self.connectionStatus
        copy.respectFilePaths = self.respectFilePaths
        copy.downloadMode = self.downloadMode
        copy.downloadAggressiveness = self.downloadAggressiveness
        copy.autoTuneAggressiveness = self.autoTuneAggressiveness
        copy.serverBanner = self.serverBanner
        copy.connectionStartTime = self.connectionStartTime
        copy.lastDownloadSpeed = self.lastDownloadSpeed
        copy.lastDownloadedFile = self.lastDownloadedFile
        copy.lastDownloadTime = self.lastDownloadTime
        copy.sessionId = self.sessionId
        copy.directoryBookmark = self.directoryBookmark
        copy.runOnLaunch = self.runOnLaunch
        return copy
    }

    // MARK: - Security-Scoped Bookmark Helpers

    /// Start accessing the security-scoped resource (for sandboxed apps)
    /// Returns true if access was granted, false otherwise
    @discardableResult
    func startAccessingDirectory() -> Bool {
        guard let bookmark = directoryBookmark else {
            // No bookmark saved, try to access anyway (works in dev builds)
            return true
        }

        var isStale = false
        do {
            let url = try URL(resolvingBookmarkData: bookmark,
                             options: .withSecurityScope,
                             relativeTo: nil,
                             bookmarkDataIsStale: &isStale)

            if isStale {
                print("⚠️ Security-scoped bookmark is stale for: \(localDownloadPath)")
                // TODO: Could prompt user to reselect directory
            }

            if url.startAccessingSecurityScopedResource() {
                print("✅ Started accessing security-scoped directory: \(localDownloadPath)")
                return true
            } else {
                print("❌ Failed to access security-scoped directory: \(localDownloadPath)")
                return false
            }
        } catch {
            print("❌ Error resolving bookmark for \(localDownloadPath): \(error)")
            return false
        }
    }

    /// Stop accessing the security-scoped resource
    func stopAccessingDirectory() {
        guard let bookmark = directoryBookmark else { return }

        do {
            var isStale = false
            let url = try URL(resolvingBookmarkData: bookmark,
                             options: .withSecurityScope,
                             relativeTo: nil,
                             bookmarkDataIsStale: &isStale)
            url.stopAccessingSecurityScopedResource()
            print("✅ Stopped accessing security-scoped directory: \(localDownloadPath)")
        } catch {
            print("⚠️ Error stopping access to directory: \(error)")
        }
    }

}

struct FTPDirectoryItem {
    let name: String
    let path: String
    let isDirectory: Bool
}

struct FTPFile: Codable, Identifiable {
    var id = UUID()
    let name: String
    let path: String
    var size: Int64
    let lastModified: Date
    var isStabilized: Bool = false
    var stabilizationChecks: Int = 0
    var downloadStatus: DownloadStatus = .pending
    var lastStabilizationCheck: Date?
    var originalSize: Int64
    var retryCount: Int = 0
    var maxRetries: Int = 3
    
    // New properties for time-based stabilization
    var firstStableSize: Int64? = nil
    var firstStableTime: Date? = nil
    
    // Download tracking properties
    var downloadStartTime: Date? = nil
    
    init(name: String, path: String, size: Int64, lastModified: Date) {
        self.name = name
        self.path = path
        self.size = size
        self.lastModified = lastModified
        self.originalSize = size
    }
    
    enum DownloadStatus: String, Codable, CaseIterable {
        case pending = "Stabilizing"
        case monitoring = "Monitoring"
        case downloading = "Downloading"
        case completed = "Completed"
        case failed = "Retrying"
        case deleted = "Deleted from Server"
    }
}

enum FTPError: Error, LocalizedError {
    case connectionFailed
    case authenticationFailed
    case directoryNotFound
    case fileNotFound
    case downloadFailed
    case deleteFailed
    case fileNotStable
    case invalidConfiguration
    case localPathNotAccessible
    
    var errorDescription: String? {
        switch self {
        case .connectionFailed:
            return "Failed to connect to FTP server"
        case .authenticationFailed:
            return "Authentication failed"
        case .directoryNotFound:
            return "Directory not found"
        case .fileNotFound:
            return "File not found"
        case .downloadFailed:
            return "Download failed"
        case .deleteFailed:
            return "Failed to delete file from server"
        case .fileNotStable:
            return "File size is not stable yet"
        case .invalidConfiguration:
            return "Invalid configuration"
        case .localPathNotAccessible:
            return "Local download path is not accessible"
        }
    }
}
