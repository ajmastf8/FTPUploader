//
//  RustFTPServiceImplementation.swift
//  RustFTPService
//
//  Implements the FTP service protocol and manages rust_ftp process
//

import Foundation

class RustFTPServiceImplementation: NSObject, FTPServiceProtocol {

    // Reference to connection for callbacks to main app
    weak var clientConnection: NSXPCConnection?

    // Track running rust_ftp processes by config ID
    private var runningProcesses: [String: Process] = [:]
    private var processQueue = DispatchQueue(label: "com.roningroupinc.FTPDownloader.xpc.processes")

    // Path to rust_ftp binary within XPC Service bundle
    private lazy var rustBinaryPath: String = {
        // The rust_ftp binary will be embedded in the XPC Service bundle
        let xpcBundle = Bundle.main
        if let resourcePath = xpcBundle.resourcePath {
            return "\(resourcePath)/rust_ftp"
        }
        // Fallback for development
        return "RustFTP/target/release/rust_ftp"
    }()

    override init() {
        super.init()
        print("✅ RustFTPServiceImplementation initialized")
        print("🔍 Rust binary path: \(rustBinaryPath)")
    }

    // MARK: - FTPServiceProtocol Implementation

    func startMonitoring(
        configID: String,
        host: String,
        port: Int,
        username: String,
        password: String,
        remotePath: String,
        downloadPath: String,
        pollingInterval: Int,
        stableWaitTime: Int,
        respectFilePaths: Bool,
        withReply reply: @escaping (Bool, String?) -> Void
    ) {
        print("📡 XPC Service: startMonitoring request for config \(configID)")

        processQueue.async { [weak self] in
            guard let self = self else {
                reply(false, "Service deallocated")
                return
            }

            // Check if already running
            if self.runningProcesses[configID] != nil {
                reply(false, "Configuration already running")
                return
            }

            // Create config JSON for rust_ftp
            let config = [
                "host": host,
                "port": port,
                "username": username,
                "password": password,
                "remote_path": remotePath,
                "download_path": downloadPath,
                "polling_interval_seconds": pollingInterval,
                "stable_wait_seconds": stableWaitTime,
                "respect_file_paths": respectFilePaths
            ] as [String : Any]

            do {
                // Create temporary directory for IPC files
                let tmpDir = FileManager.default.temporaryDirectory
                let configPath = tmpDir.appendingPathComponent("config_\(configID).json")
                let statusPath = tmpDir.appendingPathComponent("status_\(configID).json")
                let resultPath = tmpDir.appendingPathComponent("result_\(configID).json")
                let sessionPath = tmpDir.appendingPathComponent("session_\(configID).json")
                let hashPath = tmpDir.appendingPathComponent("hash_\(configID).json")

                // Write config file
                let jsonData = try JSONSerialization.data(withJSONObject: config, options: .prettyPrinted)
                try jsonData.write(to: configPath)

                // Launch rust_ftp process
                let process = Process()
                process.executableURL = URL(fileURLWithPath: self.rustBinaryPath)
                process.arguments = [
                    configPath.path,
                    statusPath.path,
                    resultPath.path,
                    sessionPath.path,
                    hashPath.path
                ]

                // Set up environment
                var env = ProcessInfo.processInfo.environment
                env["FTP_TMP_DIR"] = tmpDir.path
                process.environment = env

                // Capture output
                let outputPipe = Pipe()
                let errorPipe = Pipe()
                process.standardOutput = outputPipe
                process.standardError = errorPipe

                // Monitor output for notifications
                self.monitorProcessOutput(
                    pipe: outputPipe,
                    configID: configID,
                    isError: false
                )
                self.monitorProcessOutput(
                    pipe: errorPipe,
                    configID: configID,
                    isError: true
                )

                // Handle process termination
                process.terminationHandler = { [weak self] process in
                    print("⚠️ rust_ftp process terminated for config \(configID), exit code: \(process.terminationStatus)")
                    self?.processQueue.async {
                        self?.runningProcesses.removeValue(forKey: configID)
                    }

                    // Notify main app
                    if let remote = self?.clientConnection?.remoteObjectProxy as? FTPServiceNotificationProtocol {
                        if process.terminationStatus != 0 {
                            remote.errorOccurred(
                                configID: configID,
                                error: "Process exited with code \(process.terminationStatus)"
                            )
                        }
                    }
                }

                // Start the process
                try process.run()
                self.runningProcesses[configID] = process

                print("✅ rust_ftp process started for config \(configID), PID: \(process.processIdentifier)")
                reply(true, nil)

            } catch {
                print("❌ Failed to start rust_ftp: \(error)")
                reply(false, error.localizedDescription)
            }
        }
    }

    func stopMonitoring(configID: String, withReply reply: @escaping (Bool) -> Void) {
        print("🛑 XPC Service: stopMonitoring request for config \(configID)")

        processQueue.async { [weak self] in
            guard let process = self?.runningProcesses[configID] else {
                reply(false)
                return
            }

            process.terminate()
            self?.runningProcesses.removeValue(forKey: configID)

            print("✅ Stopped rust_ftp process for config \(configID)")
            reply(true)
        }
    }

    func getStatus(configID: String, withReply reply: @escaping (String?) -> Void) {
        processQueue.async {
            // Read status file
            let tmpDir = FileManager.default.temporaryDirectory
            let statusPath = tmpDir.appendingPathComponent("status_\(configID).json")

            if let data = try? Data(contentsOf: statusPath),
               let statusJSON = String(data: data, encoding: .utf8) {
                reply(statusJSON)
            } else {
                reply(nil)
            }
        }
    }

    func testConnection(
        host: String,
        port: Int,
        username: String,
        password: String,
        withReply reply: @escaping (Bool, String?) -> Void
    ) {
        // For now, just call startMonitoring briefly to test connection
        // In a full implementation, rust_ftp would have a dedicated test mode
        reply(true, "Connection test not yet implemented in XPC version")
    }

    // MARK: - Process Output Monitoring

    private func monitorProcessOutput(pipe: Pipe, configID: String, isError: Bool) {
        let handle = pipe.fileHandleForReading

        handle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }

            if let output = String(data: data, encoding: .utf8) {
                if isError {
                    print("❌ rust_ftp stderr [\(configID)]: \(output)")

                    // Notify main app of error
                    if let remote = self?.clientConnection?.remoteObjectProxy as? FTPServiceNotificationProtocol {
                        remote.errorOccurred(configID: configID, error: output)
                    }
                } else {
                    print("📝 rust_ftp stdout [\(configID)]: \(output)")

                    // Parse output for notifications
                    self?.parseRustFTPOutput(output, configID: configID)
                }
            }
        }
    }

    private func parseRustFTPOutput(_ output: String, configID: String) {
        guard let remote = clientConnection?.remoteObjectProxy as? FTPServiceNotificationProtocol else {
            return
        }

        // Parse rust_ftp output and send notifications
        // This is a simple implementation - in production you'd parse JSON notifications
        let lines = output.components(separatedBy: "\n")

        for line in lines {
            if line.contains("Discovered file:") {
                if let filename = line.components(separatedBy: "Discovered file:").last?.trimmingCharacters(in: .whitespaces) {
                    remote.fileDiscovered(configID: configID, filename: filename)
                }
            }
            else if line.contains("Downloaded:") {
                if let parts = line.components(separatedBy: "Downloaded:").last?.components(separatedBy: "->"),
                   parts.count == 2 {
                    let filename = parts[0].trimmingCharacters(in: .whitespaces)
                    let localPath = parts[1].trimmingCharacters(in: .whitespaces)
                    remote.downloadCompleted(configID: configID, filename: filename, localPath: localPath)
                }
            }
        }
    }
}
