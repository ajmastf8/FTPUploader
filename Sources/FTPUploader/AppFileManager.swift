import Foundation

/// Manages all app file operations in the standard macOS Application Support directory
class AppFileManager {
    static let shared = AppFileManager()
    
    private let appName = "FTPUploader"
    private var appSupportDirectory: URL?
    
    private init() {
        print("🔧 AppFileManager init() called")
        setupAppSupportDirectory()
    }
    
    /// Initialize the file manager and create directories immediately
    static func initialize() {
        print("🚀 Initializing AppFileManager...")
        _ = shared
        print("✅ AppFileManager initialized")
    }
    
    /// Sets up the Application Support directory for the app
    private func setupAppSupportDirectory() {
        print("🔧 Setting up Application Support directory...")
        
        guard let appSupportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            print("❌ Failed to get application support directory")
            return
        }
        
        print("📁 Application Support base: \(appSupportDir.path)")
        let configDir = appSupportDir.appendingPathComponent(appName)
        print("📁 Target config directory: \(configDir.path)")
        
        do {
            try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true, attributes: nil)
            appSupportDirectory = configDir
            print("✅ App support directory created successfully: \(configDir.path)")
        } catch {
            print("❌ Failed to create app support directory: \(error)")
            return
        }
        
        createBaseDirectory()
    }
    
    private func createBaseDirectory() {
        guard let baseDir = appSupportDirectory else { 
            print("❌ appSupportDirectory is nil in createBaseDirectory")
            return 
        }
        
        do {
            try FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true, attributes: nil)
            print("✅ Base directory ensured: \(baseDir.path)")
        } catch {
            print("❌ Failed to create base directory: \(error)")
        }
    }
    
    /// Gets the base app support directory
    var baseDirectory: URL {
        // Use the initialized appSupportDirectory if available, otherwise compute it
        if let appSupportDir = appSupportDirectory {
            // print("📁 AppFileManager using initialized directory: \(appSupportDir.path)")
            return appSupportDir
        } else {
            // Fallback: compute the path directly
            let appSupportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let configDir = appSupportDir.appendingPathComponent(appName)
            print("📁 AppFileManager computing directory: \(configDir.path)")
            return configDir
        }
    }
    
    /// Gets the configurations file URL
    var configurationsFileURL: URL {
        return baseDirectory.appendingPathComponent("configurations.json")
    }
    
    /// Gets the directory for temporary files (status, result, session files)
    var tempFilesDirectory: URL {
        return baseDirectory.appendingPathComponent("temp")
    }
    
    /// Creates a temporary file path for a specific config
    func getTempFilePath(for configId: UUID, extension: String) -> String {
        // Ensure temp directory exists
        try? FileManager.default.createDirectory(at: tempFilesDirectory, withIntermediateDirectories: true, attributes: nil)
        
        let filename = "\(configId.uuidString).\(`extension`)"
        let fullPath = tempFilesDirectory.appendingPathComponent(filename).path
        // print("🔍 AppFileManager: Created temp file path for \(`extension`): \(fullPath)")
        return fullPath
    }
    
    /// Gets the status file path for a config
    func getStatusFilePath(for configId: UUID) -> String {
        return getTempFilePath(for: configId, extension: "status")
    }
    
    /// Gets the result file path for a config
    func getResultFilePath(for configId: UUID) -> String {
        return getTempFilePath(for: configId, extension: "result")
    }
    
    /// Gets the session file path for a config
    func getSessionFilePath(for configId: UUID) -> String {
        return getTempFilePath(for: configId, extension: "session")
    }
    
    /// Gets the hash file path for a config
    func getHashFilePath(for configId: UUID) -> String {
        // Store hash files in temp directory to ensure they're in the sandboxed container
        // alongside other runtime files (status.json, result.json, etc.)
        return getTempFilePath(for: configId, extension: "hash")
    }
    
    /// Gets all session files for cleanup purposes
    func getAllSessionFiles() -> [String] {
        do {
            let tempFiles = try FileManager.default.contentsOfDirectory(at: tempFilesDirectory, includingPropertiesForKeys: nil)
            return tempFiles
                .filter { $0.lastPathComponent.hasSuffix(".session") }
                .map { $0.path }
        } catch {
            print("⚠️ Failed to get session files: \(error)")
            return []
        }
    }
    
    /// Cleans up temporary files for a specific config
    func cleanupTempFiles(for configId: UUID) {
        let statusFile = getStatusFilePath(for: configId)
        let resultFile = getResultFilePath(for: configId)
        let sessionFile = getSessionFilePath(for: configId)
        
        try? FileManager.default.removeItem(atPath: statusFile)
        try? FileManager.default.removeItem(atPath: resultFile)
        try? FileManager.default.removeItem(atPath: sessionFile)
        
        print("🧹 Cleaned up temporary files for config: \(configId)")
    }
    
    /// Gets the path for export operations (user's Downloads folder)
    var exportDirectory: URL {
        return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
    }
    
    /// Prints the current file structure for debugging
    func printFileStructure() {
        print("📁 App File Structure:")
        print("   Base Directory: \(baseDirectory.path)")
        print("   Configurations: \(configurationsFileURL.path)")
        print("   Temp Directory: \(tempFilesDirectory.path)")
        print("   Export Directory: \(exportDirectory.path)")
    }
}
