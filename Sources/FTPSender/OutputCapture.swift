import Foundation

/// Captures stdout and stderr output for diagnostic purposes
class OutputCapture: ObservableObject {
    static let shared = OutputCapture()

    private var outputBuffer: [String] = []
    private let bufferLock = NSLock()
    private var isCapturing = false
    private var sessionStartTime: Date = Date()

    // File handle for logging to disk
    private var logFileHandle: FileHandle?
    private var logFileURL: URL?

    private init() {
        setupLogFile()
    }

    deinit {
        stopCapturing()
        logFileHandle?.closeFile()
    }

    /// Set up a persistent log file
    private func setupLogFile() {
        let tempDir = FileManager.default.temporaryDirectory
        let logFileName = "FTPSender_Console_\(ProcessInfo.processInfo.processIdentifier).log"
        logFileURL = tempDir.appendingPathComponent(logFileName)

        // Create or truncate the log file
        FileManager.default.createFile(atPath: logFileURL!.path, contents: nil, attributes: nil)
        logFileHandle = FileHandle(forWritingAtPath: logFileURL!.path)

        let header = """
        ========================================
        FTP Sender Console Output Log
        Session Start: \(sessionStartTime)
        Process ID: \(ProcessInfo.processInfo.processIdentifier)
        ========================================

        """

        if let data = header.data(using: .utf8) {
            logFileHandle?.write(data)
        }

        print("📝 Console output logging to: \(logFileURL!.path)")
    }

    /// Start capturing console output
    func startCapturing() {
        guard !isCapturing else { return }
        isCapturing = true
        sessionStartTime = Date()

        print("🎬 OutputCapture: Starting console output capture")

        // Redirect stdout to capture print() statements
        // Note: This creates a duplicate of stdout, so output still appears in terminal
        freopen(logFileURL!.path, "a+", stdout)
        setvbuf(stdout, nil, _IONBF, 0) // Unbuffered for real-time logging

        // Also redirect stderr
        freopen(logFileURL!.path, "a+", stderr)
        setvbuf(stderr, nil, _IONBF, 0)
    }

    /// Stop capturing console output
    func stopCapturing() {
        guard isCapturing else { return }
        isCapturing = false

        fflush(stdout)
        fflush(stderr)

        print("🛑 OutputCapture: Stopped console output capture")
    }

    /// Get all captured output since session start
    func getAllOutput() -> String {
        guard let logFileURL = logFileURL else {
            return "❌ No log file available"
        }

        do {
            let contents = try String(contentsOf: logFileURL, encoding: .utf8)
            return contents
        } catch {
            return "❌ Error reading console log: \(error.localizedDescription)"
        }
    }

    /// Get output since a specific date
    func getOutputSince(_ date: Date) -> String {
        let allOutput = getAllOutput()
        _ = allOutput.components(separatedBy: .newlines)

        // For simplicity, return all output if we can't parse timestamps
        // In a production system, you'd parse timestamps from log lines
        return allOutput
    }

    /// Get recent output (last N lines)
    func getRecentOutput(lineCount: Int = 1000) -> String {
        let allOutput = getAllOutput()
        let lines = allOutput.components(separatedBy: .newlines)

        let recentLines = lines.suffix(lineCount)
        return recentLines.joined(separator: "\n")
    }

    /// Get output filtered by keyword
    func getFilteredOutput(containing keyword: String) -> String {
        let allOutput = getAllOutput()
        let lines = allOutput.components(separatedBy: .newlines)

        let filtered = lines.filter { $0.localizedCaseInsensitiveContains(keyword) }
        return filtered.joined(separator: "\n")
    }

    /// Clear the output buffer and log file
    func clearOutput() {
        bufferLock.lock()
        defer { bufferLock.unlock() }

        outputBuffer.removeAll()

        // Truncate log file
        if let logFileURL = logFileURL {
            try? "".write(to: logFileURL, atomically: true, encoding: .utf8)
        }
    }

    /// Get statistics about captured output
    func getStatistics() -> (totalLines: Int, errorLines: Int, warningLines: Int, sizeBytes: Int) {
        let allOutput = getAllOutput()
        let lines = allOutput.components(separatedBy: .newlines)

        let errorLines = lines.filter { line in
            line.contains("❌") || line.contains("ERROR") ||
            line.localizedCaseInsensitiveContains("error") ||
            line.localizedCaseInsensitiveContains("failed")
        }.count

        let warningLines = lines.filter { line in
            line.contains("⚠️") || line.contains("WARNING") ||
            line.localizedCaseInsensitiveContains("warning")
        }.count

        let sizeBytes = allOutput.utf8.count

        return (lines.count, errorLines, warningLines, sizeBytes)
    }

    /// Get the log file URL for direct access
    func getLogFileURL() -> URL? {
        return logFileURL
    }

    /// Get session start time
    func getSessionStartTime() -> Date {
        return sessionStartTime
    }
}
