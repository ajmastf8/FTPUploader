import Foundation
import OSLog

enum LogCollectionType: String, CaseIterable {
    case currentSession = "currentSession"
    case last2Minutes = "last2Minutes"
    case last10Minutes = "last10Minutes"
    case last30Minutes = "last30Minutes"
    case last2Errors = "last2Errors"
    case last5Errors = "last5Errors"
    case last10Errors = "last10Errors"

    var displayName: String {
        switch self {
        case .currentSession: return "Current Session (since app launch)"
        case .last2Minutes: return "Last 2 minutes"
        case .last10Minutes: return "Last 10 minutes"
        case .last30Minutes: return "Last 30 minutes"
        case .last2Errors: return "Last 2 error messages"
        case .last5Errors: return "Last 5 error messages"
        case .last10Errors: return "Last 10 error messages"
        }
    }
}

class LogCollectionService: ObservableObject {
    static let shared = LogCollectionService()
    var appLaunchTime: Date = Date() // Set by app on launch
    private init() {}

    func collectLogs(type: LogCollectionType, includeSystemInfo: Bool) -> String {
        // Use array of strings and join at end for better performance
        var sections: [String] = []

        // Professional header
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .full
        dateFormatter.timeStyle = .medium

        let header = """

        \(String(repeating: "═", count: 80))
                            🚀 FTP DOWNLOADER DIAGNOSTIC LOG
        \(String(repeating: "═", count: 80))

        📋 DIAGNOSTIC REPORT DETAILS
        \(String(repeating: "─", count: 50))
        🕐 Generated:        \(dateFormatter.string(from: Date()))
        📊 Collection Type:  \(type.displayName)
        📱 App Version:      \(getAppVersion())
        🔨 Build Number:     \(getBuildVersion())
        ⏰ Expires:          \(getExpirationDateForLog())
        🎯 Purpose:          Technical support and issue diagnosis

        """
        sections.append(header)

        // System information (optional)
        if includeSystemInfo {
            sections.append(getSystemInfo())
            sections.append("\n")
        }

        // Collect and format logs
        let logs = getLogsBasedOnType(type)
        let logSection = """
        \(String(repeating: "═", count: 80))
                              📝 APPLICATION LOG ANALYSIS
        \(String(repeating: "═", count: 80))
        \(logs)
        """
        sections.append(logSection)

        return sections.joined()
    }

    private func getLogsBasedOnType(_ type: LogCollectionType) -> String {
        switch type {
        case .currentSession:
            return getSessionLogs()
        case .last2Minutes:
            return getTimeBasedLogs(minutes: 2)
        case .last10Minutes:
            return getTimeBasedLogs(minutes: 10)
        case .last30Minutes:
            return getTimeBasedLogs(minutes: 30)
        case .last2Errors:
            return getErrorBasedLogs(count: 2)
        case .last5Errors:
            return getErrorBasedLogs(count: 5)
        case .last10Errors:
            return getErrorBasedLogs(count: 10)
        }
    }

    private func getSessionLogs() -> String {
        // Get OSLogs from current session
        let osLogs = getSystemLogs(since: appLaunchTime, errorOnly: false)

        // Get console output from current instance
        let consoleOutput = OutputCapture.shared.getAllOutput()

        // Get statistics
        let stats = OutputCapture.shared.getStatistics()

        return """
        \(osLogs)

        \(String(repeating: "═", count: 80))
                          📟 CONSOLE OUTPUT (Current Session Only)
        \(String(repeating: "═", count: 80))

        This section contains all print() statements and console output from THIS
        app instance, exactly as you would see when running from Terminal.

        📊 Console Output Statistics:
           Total Lines:   \(stats.totalLines)
           Error Lines:   \(stats.errorLines)
           Warning Lines: \(stats.warningLines)
           Size:          \(ByteCountFormatter.string(fromByteCount: Int64(stats.sizeBytes), countStyle: .file))
           Session Start: \(DateFormatter.localizedString(from: appLaunchTime, dateStyle: .short, timeStyle: .medium))

        \(String(repeating: "─", count: 80))

        \(consoleOutput)

        \(String(repeating: "─", count: 80))
        End of console output from current session.

        """
    }

    private func getTimeBasedLogs(minutes: Int) -> String {
        let cutoffDate = Date().addingTimeInterval(-Double(minutes * 60))
        return getSystemLogs(since: cutoffDate, errorOnly: false)
    }

    private func getErrorBasedLogs(count: Int) -> String {
        return getSystemLogs(since: Date().addingTimeInterval(-24 * 60 * 60), errorOnly: true, limit: count)
    }

    private func getSystemLogs(since: Date, errorOnly: Bool, limit: Int? = nil) -> String {
        do {
            let store = try OSLogStore(scope: .currentProcessIdentifier)
            let position = store.position(date: since)

            var logEntries: [String] = []
            var errorCount = 0
            var warningCount = 0
            var infoCount = 0

            let entries = try store.getEntries(at: position)
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "MMM dd HH:mm:ss.SSS"

            for entry in entries {
                guard let logEntry = entry as? OSLogEntryLog else { continue }

                // Filter by error level if requested
                if errorOnly && logEntry.level != .error && logEntry.level != .fault {
                    continue
                }

                // Filter for FTP Downloader app logs
                if logEntry.subsystem.contains("FTPDownloader") ||
                   logEntry.category.contains("FTPDownloader") ||
                   logEntry.composedMessage.contains("FTP") ||
                   logEntry.composedMessage.contains("Rust") ||
                   logEntry.composedMessage.contains("Config") ||
                   logEntry.composedMessage.contains("Download") ||
                   logEntry.composedMessage.contains("Sync") ||
                   logEntry.composedMessage.contains("🚀") || // Our emoji markers
                   logEntry.composedMessage.contains("🔧") ||
                   logEntry.composedMessage.contains("📄") ||
                   logEntry.composedMessage.contains("✅") ||
                   logEntry.composedMessage.contains("❌") ||
                   logEntry.composedMessage.contains("⚠️") ||
                   logEntry.composedMessage.contains("🛑") {

                    let timestamp = dateFormatter.string(from: logEntry.date)
                    let level = levelString(for: logEntry.level)
                    let category = logEntry.category.isEmpty ? "General" : logEntry.category

                    // Count log levels for summary
                    switch logEntry.level {
                    case .error, .fault:
                        errorCount += 1
                    case .notice:
                        warningCount += 1
                    default:
                        infoCount += 1
                    }

                    // Format with proper spacing
                    let timestampPadded = timestamp.padding(toLength: 17, withPad: " ", startingAt: 0)
                    let levelPadded = "[\(level)]".padding(toLength: 8, withPad: " ", startingAt: 0)
                    let categoryPadded = "[\(category)]".padding(toLength: 15, withPad: " ", startingAt: 0)
                    let logLine = "\(timestampPadded) \(levelPadded) \(categoryPadded) \(logEntry.composedMessage)"
                    logEntries.append(logLine)
                }

                // Apply limit if specified
                if let limit = limit, logEntries.count >= limit {
                    break
                }
            }

            if logEntries.isEmpty {
                return """
                No relevant FTP Downloader log entries found for the specified criteria.

                This may be normal if:
                • The app was recently started and hasn't generated logs yet
                • No significant activity occurred during the selected time period
                • The issue occurred outside the selected timeframe

                Troubleshooting suggestions:
                1. Try selecting a longer time window (e.g., "Last 30 minutes")
                2. Ensure the app was actively running during the selected period
                3. If experiencing a specific issue, try to reproduce it and collect logs immediately after
                4. For startup issues, try "Last 2 errors" or "Last 5 errors" instead

                """
            }

            // Add summary header with better formatting
            let interpretation: String
            if errorCount > 0 {
                interpretation = "🔍 IMPORTANT: \(errorCount) error(s) detected - these likely indicate the source of your issue.\n\n"
            } else if warningCount > 0 {
                interpretation = "🔍 NOTE: \(warningCount) warning(s) found - these may provide clues about your issue.\n\n"
            } else {
                interpretation = "🔍 NOTE: No errors detected in logs - issue may be related to configuration or network.\n\n"
            }

            // Build detailed log entries efficiently
            let sortedEntries = logEntries.reversed()
            let detailedEntries = sortedEntries.enumerated().map { index, entry in
                "[\(index + 1)] \(entry)"
            }.joined(separator: "\n\n")

            return """

            📊 LOG ANALYSIS SUMMARY
            \(String(repeating: "═", count: 50))
            📈 Total Log Entries: \(logEntries.count)
            ❌ Errors/Critical:   \(errorCount)
            ⚠️  Warnings/Notices:  \(warningCount)
            ℹ️  Info/Debug:        \(infoCount)
            🕐 Time Period:       \(DateFormatter.localizedString(from: since, dateStyle: .none, timeStyle: .medium)) - \(DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium))
            \(String(repeating: "═", count: 50))

            \(interpretation)📋 DETAILED LOG ENTRIES (Most Recent First)
            \(String(repeating: "─", count: 80))

            \(detailedEntries)

            \(String(repeating: "─", count: 80))
            End of log entries.

            """
        } catch {
            return "Error reading system logs: \(error.localizedDescription)\n\nThis may occur if:\n1. The app hasn't generated any logs yet\n2. The selected time window is too narrow\n3. System log access is restricted\n\nPlease try selecting a longer time window or describe the issue manually.\n"
        }
    }

    private func levelString(for level: OSLogEntryLog.Level) -> String {
        switch level {
        case .undefined: return "UNDEF"
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .notice: return "NOTICE"
        case .error: return "ERROR"
        case .fault: return "FAULT"
        @unknown default: return "UNKNOWN"
        }
    }

    private func getSystemInfo() -> String {
        let processInfo = ProcessInfo.processInfo
        let rustBinaryPath = Bundle.main.path(forResource: "rust_ftp", ofType: nil) ?? "Not found"

        return """
        💻 SYSTEM ENVIRONMENT
        \(String(repeating: "─", count: 50))
        macOS Version:   \(processInfo.operatingSystemVersionString)
        Hardware Model:  \(getHardwareInfo())
        Physical Memory: \(ByteCountFormatter.string(fromByteCount: Int64(processInfo.physicalMemory), countStyle: .memory))
        CPU Cores:       \(processInfo.processorCount)
        System Uptime:   \(formatUptime(processInfo.systemUptime))
        Process ID:      \(processInfo.processIdentifier)
        Hostname:        \(processInfo.hostName)

        🚀 FTP DOWNLOADER APPLICATION INFO
        \(String(repeating: "─", count: 50))
        App Bundle ID:   \(Bundle.main.bundleIdentifier ?? "Unknown")
        Build Date:      \(getBuildDate())
        Install Location: \(Bundle.main.bundlePath)
        Rust Engine:     \(rustBinaryPath)

        """
    }

    private func getHardwareInfo() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        return String(cString: model)
    }

    private func formatUptime(_ uptime: TimeInterval) -> String {
        let days = Int(uptime) / (24 * 3600)
        let hours = (Int(uptime) % (24 * 3600)) / 3600
        let minutes = (Int(uptime) % 3600) / 60

        if days > 0 {
            return "\(days)d \(hours)h \(minutes)m"
        } else {
            return "\(hours)h \(minutes)m"
        }
    }

    private func getAppVersion() -> String {
        return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    private func getBuildVersion() -> String {
        return Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    private func getBuildDate() -> String {
        // Try to get build date from bundle
        if let buildDate = Bundle.main.infoDictionary?["CFBuildDate"] as? String {
            return buildDate
        }

        // Fallback to current date if no build date found
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: Date())
    }

    func createEmailURL(subject: String, body: String) -> URL? {
        let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let encodedBody = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""

        let mailtoString = "mailto:support@roningroupinc.com?subject=\(encodedSubject)&body=\(encodedBody)"
        return URL(string: mailtoString)
    }

    func saveLogToFile(_ content: String) -> URL? {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())

        let fileName = "FTPDownloader_Log_\(timestamp).txt"
        let desktopURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first

        guard let desktopURL = desktopURL else { return nil }

        let fileURL = desktopURL.appendingPathComponent(fileName)

        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            print("Error saving log file: \(error)")
            return nil
        }
    }

    // Save log to specific URL (for file picker)
    func saveLogToFile(_ content: String, atURL url: URL) -> Bool {
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            return true
        } catch {
            print("Error saving log file: \(error)")
            return false
        }
    }

    // Generate filename for file picker
    func generateLogFileName() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())
        return "FTPDownloader_Log_\(timestamp).txt"
    }

    // Helper function to get current configuration info
    func getCurrentConfigurationInfo() -> String {
        var configInfo = "\n"
        configInfo += String(repeating: "═", count: 80) + "\n"
        configInfo += "                      ⚙️ CONFIGURATION ANALYSIS\n"
        configInfo += String(repeating: "═", count: 80) + "\n\n"
        configInfo += "📋 CURRENT FTP CONFIGURATIONS\n"
        configInfo += String(repeating: "─", count: 50) + "\n"

        // Load configurations from Keychain (not JSON file anymore)
        let configs = ConfigurationStorage.shared.loadConfigurations()

        configInfo += "📊 Total Configurations Found: \(configs.count)\n\n"

        if configs.isEmpty {
            configInfo += "ℹ️ No FTP configurations have been created yet.\n"
            configInfo += "💡 This may be why you're experiencing issues - please create an FTP configuration first.\n\n"
        } else {
            for (index, config) in configs.enumerated() {
                configInfo += "🔧 Configuration #\(index + 1): \"\(config.name)\"\n"
                configInfo += "   📡 Server:        \(config.serverAddress):\(config.port)\n"
                configInfo += "   📁 Local Path:    \(config.localDownloadPath)\n"
                configInfo += "   📂 Remote Dirs:   \(config.syncDirectories.joined(separator: ", "))\n"
                configInfo += "   ⚡ Performance:   \(config.downloadAggressiveness.displayName)\n"
                configInfo += "   🗂️ Mode:          \(config.downloadMode == .deleteAfterDownload ? "Delete After Download" : "Keep After Download")\n"
                configInfo += "   ⏱️ Sync Interval: \(config.syncInterval)s\n"
                configInfo += "   🔄 Stabilization: \(config.stabilizationInterval)s\n"
                configInfo += "\n"
            }
        }

        configInfo += getRuntimeStatusInfo()
        configInfo += getActiveProcessInfo()
        configInfo += getRecentFileActivity()

        configInfo += "\n"
        return configInfo
    }

    // Get runtime status information from active processes
    private func getRuntimeStatusInfo() -> String {
        // Check for active FTP processes and their status files
        let fileManager = FileManager.default
        let tempDir = AppFileManager.shared.tempFilesDirectory

        var activeProcesses = 0
        var statusFilesFound = 0
        var resultFilesFound = 0
        var statusDetails: [String] = []
        var resultDetails: [String] = []

        do {
            let tempFiles = try fileManager.contentsOfDirectory(atPath: tempDir.path)
            let statusFiles = tempFiles.filter { $0.contains("status") }
            let resultFiles = tempFiles.filter { $0.contains("result") }
            let sessionFiles = tempFiles.filter { $0.contains("session") }

            statusFilesFound = statusFiles.count
            resultFilesFound = resultFiles.count

            // Process status files efficiently
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss"

            for statusFile in statusFiles.prefix(5) {
                let fullPath = tempDir.appendingPathComponent(statusFile).path
                if let statusData = try? Data(contentsOf: URL(fileURLWithPath: fullPath)),
                   let status = try? JSONSerialization.jsonObject(with: statusData) as? [String: Any] {

                    let configId = statusFile.replacingOccurrences(of: "status_", with: "").replacingOccurrences(of: ".json", with: "")
                    let stage = status["stage"] as? String ?? "Unknown"
                    let filename = status["filename"] as? String ?? "No file"
                    let progress = status["progress"] as? Double ?? 0.0
                    let timestamp = status["timestamp"] as? UInt64 ?? 0

                    let date = Date(timeIntervalSince1970: Double(timestamp))
                    let timeStr = formatter.string(from: date)

                    statusDetails.append("""
                       📁 Config: \(configId.prefix(8))...
                          🔄 Stage: \(stage)
                          📄 File: \(filename)
                          📊 Progress: \(Int(progress * 100))%
                          ⏰ Last Update: \(timeStr)
                    """)

                    activeProcesses += 1
                }
            }

            // Process result files efficiently
            for resultFile in resultFiles.prefix(3) {
                let fullPath = tempDir.appendingPathComponent(resultFile).path
                if let resultData = try? Data(contentsOf: URL(fileURLWithPath: fullPath)),
                   let result = try? JSONSerialization.jsonObject(with: resultData) as? [String: Any] {

                    let success = result["success"] as? Bool ?? false
                    let message = result["message"] as? String ?? "No message"
                    let configId = resultFile.replacingOccurrences(of: "result_", with: "").replacingOccurrences(of: ".json", with: "")

                    resultDetails.append("""
                       📁 Config: \(configId.prefix(8))... - \(success ? "✅ SUCCESS" : "❌ FAILED")
                          💬 Message: \(message)
                    """)
                }
            }

            let statusSection = statusDetails.isEmpty ?
                "ℹ️ No active status files found - no FTP operations currently running.\n" :
                "🔍 ACTIVE STATUS FILES ANALYSIS:\n\(statusDetails.joined(separator: "\n\n"))\n"

            let resultSection = resultDetails.isEmpty ? "" :
                "📋 RECENT RESULT FILES:\n\(resultDetails.joined(separator: "\n\n"))\n"

            return """

            🔄 RUNTIME STATUS & ACTIVE OPERATIONS
            \(String(repeating: "─", count: 50))
            📊 Runtime Files Overview:
               📄 Status Files:  \(statusFiles.count)
               📋 Result Files:  \(resultFiles.count)
               📈 Session Files: \(sessionFiles.count)

            \(statusSection)
            \(resultSection)
            📈 Summary: \(activeProcesses) active processes, \(statusFilesFound) status files, \(resultFilesFound) result files

            """

        } catch {
            return """

            🔄 RUNTIME STATUS & ACTIVE OPERATIONS
            \(String(repeating: "─", count: 50))
            ⚠️ Error reading runtime status files: \(error.localizedDescription)

            """
        }
    }

    // Check for active system processes
    private func getActiveProcessInfo() -> String {
        var processInfo = "🔧 SYSTEM PROCESS INFORMATION\n"
        processInfo += String(repeating: "─", count: 50) + "\n"

        // Check for rust_ftp processes
        let task = Process()
        task.launchPath = "/bin/ps"
        task.arguments = ["aux"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            let lines = output.components(separatedBy: .newlines)
            let ftpProcesses = lines.filter { $0.contains("rust_ftp") || $0.contains("FTPDownloader") }

            if ftpProcesses.isEmpty {
                processInfo += "ℹ️ No active FTP Downloader processes found.\n"
                processInfo += "💡 This might explain why FTP operations aren't working.\n\n"
            } else {
                processInfo += "🔍 Active FTP-related processes found: \(ftpProcesses.count)\n\n"
                for (index, process) in ftpProcesses.prefix(5).enumerated() {
                    // Parse process info (simplified)
                    let components = process.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                    if components.count >= 11 {
                        let pid = components[1]
                        let cpu = components[2]
                        let mem = components[3]
                        let command = components[10...].joined(separator: " ")

                        processInfo += "   [\(index + 1)] PID: \(pid) | CPU: \(cpu)% | MEM: \(mem)%\n"
                        processInfo += "       Command: \(command.prefix(80))...\n\n"
                    }
                }
            }

            // Check system load
            let loadTask = Process()
            loadTask.launchPath = "/usr/bin/uptime"
            let loadPipe = Pipe()
            loadTask.standardOutput = loadPipe

            try loadTask.run()
            let loadData = loadPipe.fileHandleForReading.readDataToEndOfFile()
            let loadOutput = String(data: loadData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            processInfo += "⚙️ System Load: \(loadOutput)\n\n"

        } catch {
            processInfo += "⚠️ Error checking system processes: \(error.localizedDescription)\n\n"
        }

        return processInfo
    }

    // Get recent file activity information
    private func getRecentFileActivity() -> String {
        var activityInfo = "📂 RECENT FILE ACTIVITY & NETWORK STATUS\n"
        activityInfo += String(repeating: "─", count: 50) + "\n"

        // Check download directories for recent activity
        if let configs = getStoredConfigurations() {
            var totalActiveConfigs = 0
            var recentDownloads = 0

            for config in configs.prefix(3) { // Limit to avoid performance issues
                let downloadPath = config["localDownloadPath"] as? String ?? ""
                if !downloadPath.isEmpty && FileManager.default.fileExists(atPath: downloadPath) {
                    do {
                        let contents = try FileManager.default.contentsOfDirectory(atPath: downloadPath)
                        let recentFiles = contents.filter { filename in
                            if let attrs = try? FileManager.default.attributesOfItem(atPath: URL(fileURLWithPath: downloadPath).appendingPathComponent(filename).path),
                               let creationDate = attrs[.creationDate] as? Date {
                                return Date().timeIntervalSince(creationDate) < 3600 // Last hour
                            }
                            return false
                        }

                        if !recentFiles.isEmpty {
                            let configName = config["name"] as? String ?? "Unknown"
                            activityInfo += "📁 \(configName): \(recentFiles.count) files downloaded in last hour\n"
                            recentDownloads += recentFiles.count

                            // Show some recent files
                            for file in recentFiles.prefix(3) {
                                activityInfo += "   📄 \(file)\n"
                            }
                            if recentFiles.count > 3 {
                                activityInfo += "   📄 ... and \(recentFiles.count - 3) more\n"
                            }
                            activityInfo += "\n"
                        }
                        totalActiveConfigs += 1
                    } catch {
                        activityInfo += "⚠️ Error reading download directory '\(downloadPath)': \(error.localizedDescription)\n"
                    }
                }
            }

            if recentDownloads == 0 {
                activityInfo += "ℹ️ No recent file downloads detected in the last hour.\n"
                activityInfo += "💡 This might indicate:\n"
                activityInfo += "   • FTP processes are not running\n"
                activityInfo += "   • No new files on FTP servers\n"
                activityInfo += "   • Connection issues preventing downloads\n\n"
            } else {
                activityInfo += "📊 Summary: \(recentDownloads) files downloaded across \(totalActiveConfigs) configurations\n\n"
            }
        }

        // Basic network connectivity check
        activityInfo += "🌐 NETWORK CONNECTIVITY STATUS:\n"

        // Check if we can resolve DNS (basic connectivity test)
        let task = Process()
        task.launchPath = "/usr/bin/nslookup"
        task.arguments = ["google.com"]
        task.standardOutput = Pipe()
        task.standardError = Pipe()

        do {
            try task.run()
            task.waitUntilExit()
            if task.terminationStatus == 0 {
                activityInfo += "✅ Basic internet connectivity: OK\n"
            } else {
                activityInfo += "❌ Basic internet connectivity: FAILED\n"
                activityInfo += "💡 Network issues may be preventing FTP connections\n"
            }
        } catch {
            activityInfo += "⚠️ Could not test network connectivity\n"
        }

        activityInfo += "\n"
        return activityInfo
    }

    // Helper to get stored configurations
    private func getStoredConfigurations() -> [[String: Any]]? {
        let configFileURL = AppFileManager.shared.configurationsFileURL
        guard FileManager.default.fileExists(atPath: configFileURL.path) else { return nil }

        do {
            let data = try Data(contentsOf: configFileURL)
            if let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                return jsonArray
            }
        } catch {
            print("Error reading configurations for diagnostics: \(error)")
        }
        return nil
    }

    private func getExpirationDateForLog() -> String {
        if BuildType.current.useTimeExpiration {
            if let buildTimestampString = Bundle.main.infoDictionary?["BuildTimestamp"] as? String,
               let buildDate = ISO8601DateFormatter().date(from: buildTimestampString),
               let expirationDate = Calendar.current.date(byAdding: .day, value: 30, to: buildDate) {
                let formatter = DateFormatter()
                formatter.dateStyle = .long
                formatter.timeStyle = .none
                return formatter.string(from: expirationDate)
            }
        }
        return "No expiration"
    }
}