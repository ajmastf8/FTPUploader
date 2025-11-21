import Foundation
import SwiftUI
import AppKit

@MainActor
class DemoModeManager: ObservableObject {
    static let shared = DemoModeManager()

    @Published var isDemoMode = false
    @Published var demoConfig: FTPConfig?

    private var demoDirectoryURL: URL?
    private var demoImagesCreated: [URL] = []
    private var statsTimer: Timer?
    private var liveNotificationTimer: Timer?
    private var currentFileIndex = 0
    private var totalBytesTransferred: UInt64 = 0

    private init() {}

    /// Start demo mode - creates config, directory, and images
    func startDemoMode(syncManager: FileSyncManager, onConfigCreated: @escaping (FTPConfig) -> Void) {
        guard !isDemoMode else {
            print("⚠️ Demo mode already active")
            return
        }

        print("🎬 Starting demo mode...")
        isDemoMode = true

        // Create demo configuration
        let config = createDemoConfiguration()
        demoConfig = config

        // Clear any existing demo images first
        clearExistingDemoImages()

        // Create demo directory
        if let demoDir = createDemoDirectory() {
            demoDirectoryURL = demoDir
            print("✅ Created demo directory: \(demoDir.path)")
        }

        // Create demo images in the app bundle resources area (simulating FTP server)
        createDemoImages()

        // Notify the UI to add the config
        onConfigCreated(config)

        // Start the demo transfer
        startDemoTransfer(config: config, syncManager: syncManager)
    }

    /// Restart demo mode for an existing demo config (when Start button is clicked)
    func restartDemoMode(config: FTPConfig, syncManager: FileSyncManager) {
        print("🎬 Restarting demo mode for existing config...")

        // Clear any existing demo images first
        clearExistingDemoImages()

        // Recreate demo directory
        if let demoDir = createDemoDirectory() {
            demoDirectoryURL = demoDir
            print("✅ Recreated demo directory: \(demoDir.path)")
        }

        // Create fresh demo images
        createDemoImages()

        // Start the demo transfer
        startDemoTransfer(config: config, syncManager: syncManager)
    }

    /// Start the demo transfer process (used by both startDemoMode and restartDemoMode)
    private func startDemoTransfer(config: FTPConfig, syncManager: FileSyncManager) {
        // Simulate connecting to FTP server
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self = self else { return }
            self.writeInfoNotification(config: config, message: "🔌 Connecting to demo.example.com:21...")
        }

        // Simulate FTP login
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
            guard let self = self else { return }
            self.writeInfoNotification(config: config, message: "🔐 Logging in as demo_user...")
        }

        // Simulate test connection success
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self else { return }

            // Add success notification
            syncManager.addConfigLog(config.id, message: "✅ Test connection successful!")
            syncManager.addConfigLog(config.id, message: "✅ Server: demo.example.com")
            syncManager.addConfigLog(config.id, message: "✅ Demo configuration created successfully")
            self.writeInfoNotification(config: config, message: "✅ Connected to FTP server successfully")

            // Simulate "connected" state without actually starting FTP
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                // Mark as syncing without actually calling startSync
                syncManager.configIsSyncing[config.id] = true
                syncManager.configSyncStatus[config.id] = "Connected (Demo Mode)"
                syncManager.configSessionStartTime[config.id] = Date()
                syncManager.configConnectionTimes[config.id] = "Connected"

                // Add initial demo log
                syncManager.addConfigLog(config.id, message: "🎬 Demo mode active - simulating FTP downloads")
                syncManager.addConfigLog(config.id, message: "📁 Demo images will appear in Success tab")

                // Simulate scanning directory
                self.writeInfoNotification(config: config, message: "📁 Scanning directory /demo/images...")

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    self.writeInfoNotification(config: config, message: "📊 Found 10 files in /demo/images")

                    // Begin moving demo images
                    self.startDemoImageTransfer(config: config, syncManager: syncManager)

                    // Start fake stats and live notifications
                    self.startFakeStats(config: config, syncManager: syncManager)
                    self.startLiveNotifications(config: config, syncManager: syncManager)
                }
            }
        }
    }

    /// Generate fake download stats periodically
    private func startFakeStats(config: FTPConfig, syncManager: FileSyncManager) {
        print("📊 Starting fake stats generation")

        // Update stats every 0.5 seconds
        statsTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self else { return }

            DispatchQueue.main.async {
                guard self.isDemoMode else { return }

                // Generate fake download speed (between 8-25 MB/s)
                let speedMBps = Double.random(in: 8.0...25.0)
                let formattedSpeed = String(format: "%.1f MB/s", speedMBps)

                // Update sync manager stats
                syncManager.configSyncStatus[config.id] = "Downloading @ \(formattedSpeed)"
                syncManager.configDownloadSpeeds[config.id] = formattedSpeed

                // Calculate fake total downloaded (just track internally)
                self.totalBytesTransferred += UInt64(speedMBps * 1024 * 1024 * 0.5) // bytes in 0.5 seconds

                // Update file count (increases as files are transferred)
                let fileCount = self.currentFileIndex
                if fileCount > 0 {
                    syncManager.configFileCounters[config.id] = fileCount
                }
            }
        }
    }

    /// Generate live notification events periodically
    private func startLiveNotifications(config: FTPConfig, syncManager: FileSyncManager) {
        print("🔔 Starting live notifications")

        let liveEvents = [
            "📡 Maintaining FTP connection...",
            "🔍 Scanning for new files...",
            "⏱️  Checking file stabilization...",
            "📊 Monitoring directory changes...",
            "🔄 Refreshing file list...",
            "🌐 Connection stable - latency 12ms",
            "💾 Verifying downloaded files...",
            "📁 Analyzing file metadata...",
            "🔐 Secure connection active",
            "⚡ Transfer queue optimized",
            "🎯 File detection active",
            "🔔 Monitoring /demo/images directory",
            "📈 Performance: Excellent",
            "🌟 System resources: 8% CPU, 124 MB RAM",
            "🔄 Auto-sync enabled"
        ]

        var eventIndex = 0

        // Send live events every 3-5 seconds
        liveNotificationTimer = Timer.scheduledTimer(withTimeInterval: Double.random(in: 3.0...5.0), repeats: true) { [weak self] timer in
            guard let self = self else { return }

            DispatchQueue.main.async {
                guard self.isDemoMode else {
                    timer.invalidate()
                    return
                }

                let event = liveEvents[eventIndex % liveEvents.count]
                self.writeInfoNotification(config: config, message: event)

                eventIndex += 1

                // Randomize next interval
                timer.invalidate()
                self.liveNotificationTimer = Timer.scheduledTimer(withTimeInterval: Double.random(in: 3.0...5.0), repeats: false) { [weak self] newTimer in
                    guard let self = self else { return }
                    // Use DispatchQueue to avoid actor isolation warning
                    DispatchQueue.main.async {
                        self.startLiveNotifications(config: config, syncManager: syncManager)
                    }
                }
            }
        }
    }

    /// Create a demo configuration with pre-filled values
    private func createDemoConfiguration() -> FTPConfig {
        let config = FTPConfig()

        // Demo FTP server details
        config.name = "Demo Configuration"
        config.serverAddress = "demo.example.com"
        config.username = "demo_user"
        config.password = "demo_password_12345"
        config.port = 21
        config.remoteDestination = "/demo/uploads"
        config.syncInterval = 1.0
        config.stabilizationInterval = 0

        // Local source path with timestamp (using Application Support for sandbox compatibility)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let dateString = dateFormatter.string(from: Date())

        // Use Application Support directory which is sandbox-safe
        let appSupportPath = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let ftpUploaderDir = appSupportPath.appendingPathComponent("FTPUploader")
        let demoPath = ftpUploaderDir.appendingPathComponent("Demo_\(dateString)")
        config.localSourcePath = demoPath.path

        return config
    }

    /// Clear any existing demo images from previous runs
    private func clearExistingDemoImages() {
        guard let config = demoConfig else { return }

        let demoURL = URL(fileURLWithPath: config.localSourcePath)

        // Delete the entire demo directory if it exists
        if FileManager.default.fileExists(atPath: demoURL.path) {
            do {
                try FileManager.default.removeItem(at: demoURL)
                print("🧹 Cleared existing demo directory: \(demoURL.path)")
            } catch {
                print("⚠️ Failed to clear existing demo directory: \(error)")
            }
        }

        // Clear the temp images directory from previous runs
        for imageURL in demoImagesCreated {
            do {
                if FileManager.default.fileExists(atPath: imageURL.path) {
                    try FileManager.default.removeItem(at: imageURL)
                }
            } catch {
                print("⚠️ Failed to delete old demo image: \(error)")
            }
        }

        // Clean up the temp directory
        if let firstImage = demoImagesCreated.first {
            let tempDir = firstImage.deletingLastPathComponent()
            do {
                if FileManager.default.fileExists(atPath: tempDir.path) {
                    try FileManager.default.removeItem(at: tempDir)
                    print("🧹 Deleted old temp demo images directory")
                }
            } catch {
                print("⚠️ Failed to delete old temp directory: \(error)")
            }
        }

        // Clear the array
        demoImagesCreated.removeAll()
    }

    /// Create the local download directory for demo
    private func createDemoDirectory() -> URL? {
        guard let config = demoConfig else { return nil }

        let demoURL = URL(fileURLWithPath: config.localSourcePath)

        do {
            try FileManager.default.createDirectory(at: demoURL, withIntermediateDirectories: true, attributes: nil)
            return demoURL
        } catch {
            print("❌ Failed to create demo directory: \(error)")
            return nil
        }
    }

    /// Create 10 demo images programmatically
    private func createDemoImages() {
        guard demoConfig != nil else { return }

        // Create images in a temporary directory (simulating FTP server)
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("FTPDemo_\(UUID().uuidString)")

        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: nil)

            for i in 1...10 {
                let image = createDemoImage(number: i)
                let imageURL = tempDir.appendingPathComponent("Demo_image_\(String(format: "%02d", i)).png")

                if let tiffData = image.tiffRepresentation,
                   let bitmapImage = NSBitmapImageRep(data: tiffData),
                   let pngData = bitmapImage.representation(using: .png, properties: [:]) {
                    try pngData.write(to: imageURL)
                    demoImagesCreated.append(imageURL)
                    print("✅ Created demo image: \(imageURL.lastPathComponent)")
                }
            }
        } catch {
            print("❌ Failed to create demo images: \(error)")
        }
    }

    /// Create a single demo image with colored background and "Demo" text
    private func createDemoImage(number: Int) -> NSImage {
        let size = NSSize(width: 800, height: 600)
        let image = NSImage(size: size)

        image.lockFocus()

        // Background color (cycle through different colors)
        let colors: [NSColor] = [
            .systemBlue, .systemGreen, .systemOrange, .systemPurple,
            .systemRed, .systemTeal, .systemPink, .systemYellow,
            .systemIndigo, .systemBrown
        ]
        let bgColor = colors[(number - 1) % colors.count]
        bgColor.setFill()
        NSRect(origin: .zero, size: size).fill()

        // Draw "Demo" text
        let text = "Demo"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 120),
            .foregroundColor: NSColor.white
        ]

        let textSize = text.size(withAttributes: attributes)
        let textRect = NSRect(
            x: (size.width - textSize.width) / 2,
            y: (size.height - textSize.height) / 2,
            width: textSize.width,
            height: textSize.height
        )

        text.draw(in: textRect, withAttributes: attributes)

        // Draw image number
        let numberText = "\(number)"
        let numberAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 60),
            .foregroundColor: NSColor.white.withAlphaComponent(0.7)
        ]

        let numberSize = numberText.size(withAttributes: numberAttributes)
        let numberRect = NSRect(
            x: (size.width - numberSize.width) / 2,
            y: (size.height - textSize.height) / 2 - numberSize.height - 20,
            width: numberSize.width,
            height: numberSize.height
        )

        numberText.draw(in: numberRect, withAttributes: numberAttributes)

        image.unlockFocus()

        return image
    }

    /// Start transferring demo images one by one (10 images over 20 seconds = 1 image per 2 seconds)
    private func startDemoImageTransfer(config: FTPConfig, syncManager: FileSyncManager) {
        guard !demoImagesCreated.isEmpty else {
            print("⚠️ No demo images to transfer")
            return
        }

        print("🎬 Starting demo image transfer: 10 images over 20 seconds")

        for (index, imageURL) in demoImagesCreated.enumerated() {
            let delay = Double(index) * 2.0 // 2 seconds between each image

            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self = self, self.isDemoMode else { return }

                // Send "downloading" notification
                self.writeInfoNotification(config: config, message: "⬇️ Downloading: \(imageURL.lastPathComponent)")

                // Simulate download progress
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    guard self.isDemoMode else { return }
                    self.writeProgressNotification(
                        config: config,
                        filename: imageURL.lastPathComponent,
                        progress: 0.5
                    )
                }

                // Copy image to local download directory
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    guard self.isDemoMode else { return }

                    if let demoDir = self.demoDirectoryURL {
                        let destinationURL = demoDir.appendingPathComponent(imageURL.lastPathComponent)

                        do {
                            try FileManager.default.copyItem(at: imageURL, to: destinationURL)

                            // Increment file counter
                            self.currentFileIndex = index + 1

                            // Add success notification directly to the notification file
                            let fileSize = try FileManager.default.attributesOfItem(atPath: imageURL.path)[.size] as? UInt64 ?? 0
                            let fileSizeMB = Double(fileSize) / 1024.0 / 1024.0

                            // Write success notification to file (for Success tab) and post to NotificationCenter
                            self.writeSuccessNotification(
                                config: config,
                                message: "Downloaded: \(imageURL.lastPathComponent) (\(String(format: "%.2f", fileSizeMB)) MB)",
                                filename: imageURL.lastPathComponent
                            )

                            // Also write to info feed
                            self.writeInfoNotification(
                                config: config,
                                message: "✅ Completed: \(imageURL.lastPathComponent) - \(String(format: "%.2f", fileSizeMB)) MB"
                            )

                            print("✅ Demo image transferred: \(imageURL.lastPathComponent)")
                        } catch {
                            print("❌ Failed to transfer demo image: \(error)")
                        }
                    }
                }
            }
        }

        // After all images are transferred, add completion message
        DispatchQueue.main.asyncAfter(deadline: .now() + 21.0) { [weak self] in
            guard let self = self else { return }

            self.writeSuccessNotification(config: config, message: "")
            self.writeSuccessNotification(config: config, message: "Demo completed successfully!")
            syncManager.addConfigLog(config.id, message: "📁 Demo images placed in: \(config.localSourcePath)")
            syncManager.addConfigLog(config.id, message: "")
            syncManager.addConfigLog(config.id, message: "ℹ️ Demo mode will cleanup when you quit the app")
        }
    }

    /// Write a success notification directly to the notification file
    private func writeSuccessNotification(config: FTPConfig, message: String, filename: String? = nil) {
        // Calculate config hash (same way Rust does it)
        let configHash = UInt32(config.id.hashValue & 0xFFFFFFFF)
        let tempDir = FileManager.default.temporaryDirectory.path
        let notificationFile = "\(tempDir)/ftp_notifications_\(configHash).jsonl"

        let notification: [String: Any] = [
            "config_id": configHash,
            "notification_type": "success",  // This makes it appear in Success tab
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
                } else {
                    // Create file if it doesn't exist
                    try line.write(toFile: notificationFile, atomically: true, encoding: .utf8)
                }
            }
        } catch {
            print("❌ Error writing success notification: \(error)")
        }

        // ALSO post to NotificationCenter for immediate UI update
        // If this is a file download notification, use rustDownloadSpeedUpdate
        if let filename = filename {
            NotificationCenter.default.post(
                name: .rustUploadSpeedUpdate,
                object: nil,
                userInfo: [
                    "configId": config.id,
                    "filename": filename
                ]
            )
        } else {
            // General success message - use rustStateUpdate
            NotificationCenter.default.post(
                name: .rustStateUpdate,
                object: nil,
                userInfo: [
                    "configId": config.id,
                    "message": message
                ]
            )
        }
    }

    /// Write an info notification directly to the notification file (for Live Logs)
    private func writeInfoNotification(config: FTPConfig, message: String) {
        // Calculate config hash (same way Rust does it)
        let configHash = UInt32(config.id.hashValue & 0xFFFFFFFF)
        let tempDir = FileManager.default.temporaryDirectory.path
        let notificationFile = "\(tempDir)/ftp_notifications_\(configHash).jsonl"

        let notification: [String: Any] = [
            "config_id": configHash,
            "notification_type": "info",  // This makes it appear in Live Logs tab
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
                } else {
                    // Create file if it doesn't exist
                    try line.write(toFile: notificationFile, atomically: true, encoding: .utf8)
                }
            }
        } catch {
            print("❌ Error writing info notification: \(error)")
        }

        // ALSO post to NotificationCenter for immediate UI update
        NotificationCenter.default.post(
            name: .rustStateUpdate,
            object: nil,
            userInfo: [
                "configId": config.id,
                "message": message
            ]
        )
    }

    /// Write a progress notification directly to the notification file
    private func writeProgressNotification(config: FTPConfig, filename: String, progress: Double) {
        // Calculate config hash (same way Rust does it)
        let configHash = UInt32(config.id.hashValue & 0xFFFFFFFF)
        let tempDir = FileManager.default.temporaryDirectory.path
        let notificationFile = "\(tempDir)/ftp_notifications_\(configHash).jsonl"

        let notification: [String: Any] = [
            "config_id": configHash,
            "notification_type": "download_progress",
            "message": "",
            "timestamp": UInt64(Date().timeIntervalSince1970 * 1000), // milliseconds
            "filename": filename,
            "progress": progress
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
                } else {
                    // Create file if it doesn't exist
                    try line.write(toFile: notificationFile, atomically: true, encoding: .utf8)
                }
            }
        } catch {
            print("❌ Error writing progress notification: \(error)")
        }
    }

    /// Cleanup demo mode - remove config, directory, and files
    func cleanupDemoMode(configurations: inout [FTPConfig], syncManager: FileSyncManager) {
        guard isDemoMode, let config = demoConfig else {
            return
        }

        print("🧹 Cleaning up demo mode...")

        // Invalidate timers to stop fake stats and live notifications
        statsTimer?.invalidate()
        statsTimer = nil
        liveNotificationTimer?.invalidate()
        liveNotificationTimer = nil
        print("✅ Stopped fake stats and live notification timers")

        // Reset tracking variables
        currentFileIndex = 0
        totalBytesTransferred = 0

        // Stop the demo config if running
        syncManager.stopConfigSync(configId: config.id)

        // Remove demo config from configurations list
        if let index = configurations.firstIndex(where: { $0.id == config.id }) {
            configurations.remove(at: index)
            print("✅ Removed demo configuration")
        }

        // Delete demo directory and all its contents
        if let demoDir = demoDirectoryURL {
            do {
                try FileManager.default.removeItem(at: demoDir)
                print("✅ Deleted demo directory: \(demoDir.path)")
            } catch {
                print("❌ Failed to delete demo directory: \(error)")
            }
        }

        // Delete temporary demo images
        for imageURL in demoImagesCreated {
            do {
                if FileManager.default.fileExists(atPath: imageURL.path) {
                    try FileManager.default.removeItem(at: imageURL)
                }
            } catch {
                print("❌ Failed to delete demo image: \(error)")
            }
        }

        // Clean up the temp directory
        if let firstImage = demoImagesCreated.first {
            let tempDir = firstImage.deletingLastPathComponent()
            do {
                try FileManager.default.removeItem(at: tempDir)
                print("✅ Deleted temp demo images directory")
            } catch {
                print("❌ Failed to delete temp directory: \(error)")
            }
        }

        // Reset state
        isDemoMode = false
        demoConfig = nil
        demoDirectoryURL = nil
        demoImagesCreated.removeAll()

        print("✅ Demo mode cleanup complete")
    }
}
