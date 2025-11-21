import SwiftUI
import UniformTypeIdentifiers

struct FTPConfigurationView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var configuration: FTPConfig
    let isNewConfiguration: Bool
    let onSave: (FTPConfig) -> Void
    let syncManager: FileSyncManager // Add access to sync manager for performance data
    
    // Form state - directly bound to configuration
    
    // UI state
    @State private var showingDirectoryPicker = false
    @State private var showingFTPServerBrowser = false
    @State private var showingImportPicker = false
    @State private var showingImportAlert = false
    @State private var newDirectory = ""
    @State private var isTestingConnection = false
    @State private var connectionResult: String?
    
    // Add state variables to track form values and sync with configuration
    @State private var name: String = ""
    @State private var serverAddress: String = ""
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var port: Int = 21
    @State private var localSourcePath: String = ""
    @State private var remoteDestination: String = "/"
    @State private var respectFilePaths: Bool = true
    @State private var syncInterval: TimeInterval = 5
    @State private var stabilizationInterval: TimeInterval = 5
    @State private var uploadAggressiveness: FTPConfig.UploadAggressiveness = .moderate
    @State private var autoTuneAggressiveness: Bool = true
    @State private var runOnLaunch: Bool = false
    @State private var refreshTrigger = false
    
    init(configuration: Binding<FTPConfig>, isNewConfiguration: Bool, onSave: @escaping (FTPConfig) -> Void, syncManager: FileSyncManager) {
        self._configuration = configuration
        self.isNewConfiguration = isNewConfiguration
        self.onSave = onSave
        self.syncManager = syncManager
    }

    // Computed property to detect if this is a demo configuration
    private var isDemoConfig: Bool {
        configuration.name == "Demo Configuration"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 12) {
                HStack {
                    HStack(spacing: 12) {
                        Image(nsImage: NSImage(named: "app-icon") ?? NSImage())
                            .resizable()
                            .frame(width: 32, height: 32)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        
                        Text(isNewConfiguration ? "New FTP Configuration" : "Edit FTP Configuration")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                    }
                    
                    Spacer()

                    HStack(spacing: 8) {
                        if isNewConfiguration {
                            Button("Import") {
                                showingImportPicker = true
                            }
                            .buttonStyle(.bordered)
                        }

                        // Close button
                        Button(action: {
                            dismiss()
                        }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .frame(width: 24, height: 24)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(Circle())
                        .help("Close configuration window")
                    }
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .frame(height: 80)
            
            Divider()

            // Demo Mode Banner
            if isDemoConfig {
                HStack(spacing: 12) {
                    Image(systemName: "info.circle.fill")
                        .font(.title2)
                        .foregroundColor(.orange)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Demo Mode")
                            .font(.headline)
                            .fontWeight(.semibold)
                        Text("This is a demo configuration and cannot be edited. It demonstrates the app's features with simulated data.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                }
                .padding()
                .background(Color.orange.opacity(0.15))
                .overlay(
                    Rectangle()
                        .frame(height: 1)
                        .foregroundColor(Color.orange.opacity(0.3)),
                    alignment: .bottom
                )
            }

            // Main Content
            ScrollView {
                VStack(spacing: 0) {
                    // Add padding above the form content
                    Spacer().frame(height: 30)
                    
                    HStack(alignment: .top, spacing: 0) {
                        // Left Column
                        VStack(alignment: .leading, spacing: 24) {
                            // Configuration Section
                            VStack(alignment: .leading, spacing: 16) {
                                SectionHeader(title: "Configuration")
                                CustomTextField(title: "Configuration Name", text: $name, placeholder: "My FTP Server")
                            }
                            .disabled(isDemoConfig)
                            
                            // FTP Server Section
                            VStack(alignment: .leading, spacing: 16) {
                                SectionHeader(title: "FTP Server")
                                CustomTextField(title: "Server Address", text: $serverAddress, placeholder: "ftp.example.com")
                                CustomTextField(title: "Username", text: $username, placeholder: "username")
                                CustomSecureField(title: "Password", text: $password, placeholder: "password")
                                CustomTextField(title: "Port", text: Binding(
                                    get: { String(port) },
                                    set: { port = Int($0) ?? 21 }
                                ), placeholder: "21")

                                Button(action: {
                                    print("Test button clicked!")
                                    testConnection()
                                }) {
                                    HStack {
                                        Image(systemName: "globe")
                                        Text("Test Connection")
                                    }
                                }
                                .buttonStyle(.bordered)
                                .disabled(serverAddress.isEmpty || username.isEmpty || password.isEmpty || port <= 0 || isDemoConfig)

                                // Show connection result
                                if let result = connectionResult {
                                    Text(result)
                                        .font(.caption)
                                        .foregroundColor(result.contains("✅") ? .green : result.contains("❌") ? .red : .orange)
                                        .padding(.top, 4)
                                }
                            }
                            .disabled(isDemoConfig)
                            
                            // Sync Settings Section
                            VStack(alignment: .leading, spacing: 16) {
                                SectionHeader(title: "Sync Settings")
                                HStack(spacing: 20) {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("Sync:")
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                        Picker("", selection: $syncInterval) {
                                            ForEach(Array(FTPConfig.syncIntervalOptions.enumerated()), id: \.offset) { index, interval in
                                                Text(FTPConfig.syncIntervalLabels[index]).tag(interval)
                                            }
                                        }
                                        .frame(width: 80)
                                    }

                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("Stabilize:")
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                        Picker("", selection: $stabilizationInterval) {
                                            ForEach(Array(FTPConfig.stabilizationIntervalOptions.enumerated()), id: \.offset) { index, interval in
                                                Text(FTPConfig.stabilizationIntervalLabels[index]).tag(interval)
                                            }
                                        }
                                        .frame(width: 80)
                                    }

                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("Aggressiveness:")
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                        Picker("", selection: $uploadAggressiveness) {
                                            ForEach(FTPConfig.UploadAggressiveness.allCases, id: \.self) { aggressiveness in
                                                Text("\(aggressiveness.shortName) (\(aggressiveness.connectionCount))").tag(aggressiveness)
                                            }
                                        }
                                        .frame(width: 140)
                                    }
                                }

                                VStack(alignment: .leading, spacing: 8) {
                                    Toggle("Auto-tune aggressiveness", isOn: $autoTuneAggressiveness)
                                        .toggleStyle(.switch)
                                        .onChange(of: autoTuneAggressiveness) {
                                            print("🔍 Auto-tune aggressiveness changed to: \(autoTuneAggressiveness)")
                                        }

                                    Text("Automatically adjust connection count based on server performance")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .disabled(isDemoConfig)
                        }
                        .frame(width: 350)
                        .padding(.horizontal, 30)
                        
                        // Right Column
                        VStack(alignment: .leading, spacing: 24) {
                            // Local Source Section
                            VStack(alignment: .leading, spacing: 16) {
                                SectionHeader(title: "Local Source")
                                HStack {
                                    CustomTextField(title: "Source Path", text: $localSourcePath, placeholder: "/Users/username/Documents/ToUpload")
                                    Button("Browse") {
                                        print("Browse button clicked! Opening native file picker")
                                        openDirectoryPicker()
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(isDemoConfig)
                                }
                                Text("📁 Files in this directory will be uploaded to the FTP server")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .disabled(isDemoConfig)

                            // Remote Destination Section
                            VStack(alignment: .leading, spacing: 16) {
                                SectionHeader(title: "Remote Destination")
                                HStack {
                                    CustomTextField(title: "FTP Path", text: $remoteDestination, placeholder: "/uploads")
                                    Button("Browse FTP") {
                                        showingFTPServerBrowser = true
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(serverAddress.isEmpty || username.isEmpty || password.isEmpty || port <= 0 || isDemoConfig)
                                }
                                Text("📤 Files will be uploaded to this directory on the FTP server")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .disabled(isDemoConfig)
                            
                            // File Handling Section
                            VStack(alignment: .leading, spacing: 16) {
                                SectionHeader(title: "File Handling")

                                VStack(alignment: .leading, spacing: 12) {
                                    Toggle("Respect file paths (maintain directory structure)", isOn: $respectFilePaths)
                                        .toggleStyle(.switch)
                                        .onChange(of: respectFilePaths) {
                                            print("🔍 File paths respect changed to: \(respectFilePaths)")
                                        }

                                    if respectFilePaths {
                                        Text("📁 Uploads will maintain the same directory structure on the FTP server")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    } else {
                                        Text("📁 All files will be uploaded to the root remote directory")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }

                                Divider()
                                    .padding(.vertical, 4)

                                HStack(alignment: .center, spacing: 12) {
                                    Toggle("Run on Launch", isOn: $runOnLaunch)
                                        .toggleStyle(.switch)
                                        .onChange(of: runOnLaunch) {
                                            print("🔍 Run on Launch changed to: \(runOnLaunch)")
                                        }

                                    Text("Automatically start syncing this configuration when the app launches")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }

                                VStack(alignment: .leading, spacing: 12) {
                                    Text("After successful upload:")
                                        .font(.subheadline)
                                        .fontWeight(.medium)

                                    Text("📦 Files will be moved to FTPU-Sent directory")
                                        .font(.caption)
                                        .foregroundColor(.blue)
                                }
                            }
                            .disabled(isDemoConfig)
                            
                            // Save Button at bottom of right column
                            VStack(spacing: 16) {
                                Divider()

                                HStack(spacing: 16) {
                                    Button("Cancel") {
                                        dismiss()
                                    }
                                    .buttonStyle(.bordered)
                                    .keyboardShortcut(.escape)

                                    Spacer()

                                    Button(isNewConfiguration ? "Create Configuration" : "Save Changes") {
                                        saveConfiguration()
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(!isValidConfiguration || isDemoConfig)
                                    .keyboardShortcut(.return)
                                }
                            }
                        }
                        .padding(.trailing, 30)
                    }
                    .frame(width: 800)
                    .padding(.bottom, 30)
                }
            }
        }
        .frame(minWidth: 800, minHeight: 700)
        .frame(maxWidth: 900, maxHeight: 800)
        .onAppear {
            print("🔍 FTPConfigurationView appeared")
            print("   isNewConfiguration: \(isNewConfiguration)")
            print("   configuration.name: '\(configuration.name)'")
            print("   configuration.serverAddress: '\(configuration.serverAddress)'")
            print("   configuration.localSourcePath: '\(configuration.localSourcePath)'")
            print("   configuration.port: \(configuration.port)")

            // Sync local state with configuration object
            name = configuration.name
            serverAddress = configuration.serverAddress
            username = configuration.username
            password = configuration.password
            port = configuration.port
            localSourcePath = configuration.localSourcePath
            remoteDestination = configuration.remoteDestination.isEmpty ? "/" : configuration.remoteDestination
            respectFilePaths = configuration.respectFilePaths
            syncInterval = configuration.syncInterval
            stabilizationInterval = configuration.stabilizationInterval
            uploadAggressiveness = configuration.uploadAggressiveness
            autoTuneAggressiveness = configuration.autoTuneAggressiveness
            runOnLaunch = configuration.runOnLaunch

            print("   respectFilePaths: \(respectFilePaths)")
            print("   uploadAggressiveness: \(uploadAggressiveness)")
            print("   autoTuneAggressiveness: \(autoTuneAggressiveness)")
            print("   runOnLaunch: \(runOnLaunch)")
            print("   remoteDestination: \(remoteDestination)")
        }
        .onChange(of: configuration.serverAddress) {
            print("🔍 serverAddress changed to: '\(configuration.serverAddress)'")
        }
        .onChange(of: configuration.localSourcePath) {
            print("🔍 localSourcePath changed to: '\(configuration.localSourcePath)'")
        }
        .onChange(of: configuration.port) {
            print("🔍 port changed to: \(configuration.port)")
        }
        .onChange(of: respectFilePaths) {
            print("🔍 respectFilePaths changed to: \(respectFilePaths)")
        }
        .onChange(of: remoteDestination) {
            print("🔍 remoteDestination changed to: \(remoteDestination)")
        }
        .sheet(isPresented: $showingFTPServerBrowser) {
            FTPServerBrowserView(
                serverAddress: serverAddress,
                username: username,
                password: password,
                port: String(port),
                selectedDirectory: $remoteDestination
            )
        }
        .onChange(of: showingFTPServerBrowser) {
            if !showingFTPServerBrowser {
                // FTP browser was dismissed, force UI refresh
                print("FTP Browser dismissed, refreshing UI...")
                refreshTrigger.toggle()
            }
        }
        .fileImporter(
            isPresented: $showingImportPicker,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    importConfiguration(from: url)
                }
            case .failure(let error):
                print("Import failed: \(error)")
            }
        }
        .alert("Set Local Source Directory", isPresented: $showingImportAlert) {
            Button("OK") { }
        } message: {
            Text("Configuration imported successfully! Please set the local source directory using the Browse button before saving.")
        }
    }
}

// MARK: - Helper Functions
extension FTPConfigurationView {
    private var isValidConfiguration: Bool {
        // Core required fields - use local state variables
        let hasCoreFields = !name.isEmpty &&
                           !serverAddress.isEmpty &&
                           !username.isEmpty &&
                           !password.isEmpty &&
                           port > 0

        // For new configurations, allow empty localSourcePath
        if isNewConfiguration {
            return hasCoreFields
        } else {
            // For editing, require local source path
            return hasCoreFields && !localSourcePath.isEmpty
        }
    }

    private func saveConfiguration() {
        // Sync local state variables back to configuration object
        configuration.name = name
        configuration.serverAddress = serverAddress
        configuration.username = username
        configuration.password = password
        configuration.port = port
        configuration.localSourcePath = localSourcePath
        configuration.remoteDestination = remoteDestination
        configuration.respectFilePaths = respectFilePaths
        configuration.syncInterval = syncInterval
        configuration.stabilizationInterval = stabilizationInterval
        configuration.uploadAggressiveness = uploadAggressiveness
        configuration.autoTuneAggressiveness = autoTuneAggressiveness
        configuration.runOnLaunch = runOnLaunch

        // Debug: Print configuration values before saving
        print("🔍 Configuration values before saving:")
        print("   name: '\(configuration.name)'")
        print("   serverAddress: '\(configuration.serverAddress)'")
        print("   username: '\(configuration.username)'")
        print("   password: '\(configuration.password.isEmpty ? "empty" : "filled")'")
        print("   port: \(configuration.port)")
        print("   localSourcePath: '\(configuration.localSourcePath)'")
        print("   remoteDestination: \(configuration.remoteDestination)")
        print("   syncInterval: \(configuration.syncInterval)")
        print("   stabilizationInterval: \(configuration.stabilizationInterval)")
        print("   respectFilePaths: \(configuration.respectFilePaths)")
        print("   uploadAggressiveness: \(configuration.uploadAggressiveness)")
        print("   autoTuneAggressiveness: \(configuration.autoTuneAggressiveness)")
        print("   runOnLaunch: \(configuration.runOnLaunch)")

        // The configuration object is already updated by the form bindings
        // The fix for @Published/Codable issues is now implemented in ContentView.saveConfigurations()

        onSave(configuration)
        dismiss()
    }
    
    private func importConfiguration(from url: URL) {
        do {
            let data = try Data(contentsOf: url)
            let importedConfig = try JSONDecoder().decode(FTPConfig.self, from: data)

            print("🔍 Importing configuration:")
            print("   Imported localSourcePath: '\(importedConfig.localSourcePath)'")

            // Update the configuration object directly
            configuration.name = importedConfig.name
            configuration.serverAddress = importedConfig.serverAddress
            configuration.username = importedConfig.username
            configuration.password = importedConfig.password
            configuration.port = importedConfig.port
            // Always clear local source path on import - user must set their own
            configuration.localSourcePath = ""
            configuration.directoryBookmark = nil
            configuration.remoteDestination = importedConfig.remoteDestination.isEmpty ? "/" : importedConfig.remoteDestination
            configuration.syncInterval = importedConfig.syncInterval
            configuration.stabilizationInterval = importedConfig.stabilizationInterval
            configuration.respectFilePaths = importedConfig.respectFilePaths
            configuration.uploadAggressiveness = importedConfig.uploadAggressiveness
            configuration.autoTuneAggressiveness = importedConfig.autoTuneAggressiveness

            // Also update local state variables to keep UI in sync
            name = importedConfig.name
            serverAddress = importedConfig.serverAddress
            username = importedConfig.username
            password = importedConfig.password
            port = importedConfig.port
            // Clear local source path - user must set their own
            localSourcePath = ""
            remoteDestination = importedConfig.remoteDestination
            respectFilePaths = importedConfig.respectFilePaths
            syncInterval = importedConfig.syncInterval
            stabilizationInterval = importedConfig.stabilizationInterval
            uploadAggressiveness = importedConfig.uploadAggressiveness
            autoTuneAggressiveness = importedConfig.autoTuneAggressiveness

            print("   ✅ Configuration imported successfully")
            print("   📁 Local source path cleared - user must set their own")

            // Show alert reminding user to set local source directory
            showingImportAlert = true

        } catch {
            print("❌ Failed to import configuration: \(error)")
        }
    }
    
    private func testConnection() {
        print("testConnection() called!")

        // Prevent double-clicking
        guard !isTestingConnection else {
            print("⚠️ Test connection already in progress, ignoring duplicate click")
            return
        }

        print("🔍 Test connection validation:")
        print("   serverAddress: '\(serverAddress)' (empty: \(serverAddress.isEmpty))")
        print("   username: '\(username)' (empty: \(username.isEmpty))")
        print("   password: '\(password.isEmpty ? "empty" : "filled")' (empty: \(password.isEmpty))")
        print("   port: \(port) (valid: \(port > 0))")

        isTestingConnection = true
        connectionResult = nil

        // Validate inputs
        guard !serverAddress.isEmpty, !username.isEmpty, !password.isEmpty, port > 0 else {
            print("❌ Validation failed: serverAddress=\(serverAddress), username=\(username), password=\(password.isEmpty ? "empty" : "filled"), port=\(port)")
            connectionResult = "❌ Please fill in all required fields"
            isTestingConnection = false
            return
        }

        // Check if this is a demo configuration
        if serverAddress == "demo.example.com" {
            print("🎬 Demo configuration detected - simulating test connection")
            Task {
                // Simulate a brief connection test delay
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

                await MainActor.run {
                    isTestingConnection = false
                    connectionResult = "✅ Demo connection successful! (Simulated)"
                }
            }
            return
        }

        print("✅ Validation passed, testing connection...")

        // Test connection using curl
        Task {
            do {
                let result = try await executeCurlCommand([
                    "-v",
                    "-u", "\(username):\(password)",
                    "ftp://\(serverAddress):\(port)/",
                    "--connect-timeout", "10",
                    "--max-time", "15",
                    "--ftp-pasv",
                    "--retry", "0",
                    "--retry-delay", "0",
                    "--list-only"
                ])

                await MainActor.run {
                    isTestingConnection = false
                    if result.exitCode == 0 {
                        connectionResult = "✅ Connection successful!"
                    } else {
                        connectionResult = "❌ Connection failed (exit code: \(result.exitCode))"
                    }
                }
            } catch {
                await MainActor.run {
                    isTestingConnection = false
                    connectionResult = "❌ Connection error: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func formatInterval(_ seconds: TimeInterval) -> String {
        if seconds == 0 {
            return "None"
        } else if seconds < 60 {
            return "\(Int(seconds))s"
        } else if seconds < 3600 {
            let minutes = Int(seconds / 60)
            return "\(minutes)m"
        } else {
            let hours = Int(seconds / 3600)
            return "\(hours)h"
        }
    }

    private func openDirectoryPicker() {
        let panel = NSOpenPanel()
        panel.prompt = "Choose Source Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true  // This enables the create folder button in the file picker
        panel.message = "Select the folder containing files to upload"

        print("🔍 Directory picker opened")
        print("   Current localSourcePath: '\(localSourcePath)'")

        if panel.runModal() == .OK, let selectedURL = panel.url {
            let newPath = selectedURL.path
            print("   Selected path: '\(newPath)'")

            // Create security-scoped bookmark for sandboxed App Store builds
            do {
                let bookmarkData = try selectedURL.bookmarkData(
                    options: .withSecurityScope,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )

                // Save bookmark to configuration
                configuration.directoryBookmark = bookmarkData
                print("   ✅ Created and saved security-scoped bookmark (\(bookmarkData.count) bytes)")

                // Update path
                localSourcePath = newPath
                configuration.localSourcePath = newPath
                print("   Updated localSourcePath: '\(localSourcePath)'")

            } catch {
                print("   ❌ Failed to create security-scoped bookmark: \(error)")
                // Still update the path even if bookmark fails (for dev builds)
                localSourcePath = newPath
                configuration.localSourcePath = newPath
            }
        } else {
            print("   Directory picker cancelled")
        }
    }
    
    private func executeCurlCommand(_ arguments: [String]) async throws -> (exitCode: Int32, output: String) {
        print("🔍 DEBUG: Starting curl command with args: \(arguments)")
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        process.arguments = arguments
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        print("🔍 DEBUG: About to start curl process")
        
        do {
            print("🔍 DEBUG: Running curl process...")
            try process.run()
            print("🔍 DEBUG: Curl process started, waiting for completion...")
            
            // Simple timeout using DispatchQueue
            let timeoutWorkItem = DispatchWorkItem {
                if process.isRunning {
                    print("⚠️ Curl command timed out, terminating process")
                    process.terminate()
                }
            }
            
            // Schedule timeout for 15 seconds
            DispatchQueue.global().asyncAfter(deadline: .now() + 15.0, execute: timeoutWorkItem)
            
            // Wait for process to complete
            process.waitUntilExit()
            
            // Cancel timeout since process completed
            timeoutWorkItem.cancel()
            
            print("🔍 DEBUG: Curl process completed, status: \(process.terminationStatus)")
            
            // Close the write ends of the pipes to ensure readDataToEndOfFile doesn't hang
            outputPipe.fileHandleForWriting.closeFile()
            errorPipe.fileHandleForWriting.closeFile()
            
            // Read pipe data
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            
            let output = String(data: outputData, encoding: .utf8) ?? ""
            let error = String(data: errorData, encoding: .utf8) ?? ""
            
            // Log the actual curl output
            print("🔍 DEBUG: Curl stdout output: '\(output)'")
            print("🔍 DEBUG: Curl stderr output: '\(error)'")
            print("🔍 DEBUG: Curl exit code: \(process.terminationStatus)")
            
            print("🔍 DEBUG: Curl command completed successfully")
            return (process.terminationStatus, output + error)
            
        } catch {
            print("🔍 DEBUG: Error during curl execution: \(error)")
            throw error
        }
    }
}

// MARK: - Helper Views
struct SectionHeader: View {
    let title: String
    
    var body: some View {
        Text(title)
            .font(.headline)
            .fontWeight(.semibold)
            .foregroundColor(.primary)
    }
}

struct CustomTextField: View {
    let title: String
    @Binding var text: String
    let placeholder: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
            
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
        }
    }
}

struct CustomSecureField: View {
    let title: String
    @Binding var text: String
    let placeholder: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
            
            SecureField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
        }
    }
}

struct RadioButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                Text(title)
                    .foregroundColor(.primary)
                Spacer()
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - FTP Server Browser View
struct FTPServerBrowserView: View {
    @Environment(\.dismiss) private var dismiss
    let serverAddress: String
    let username: String
    let password: String
    let port: String
    @Binding var selectedDirectory: String

    @State private var isConnecting = false
    @State private var connectionError: String?
    @State private var serverDirectories: [String] = []
    @State private var selectedPath: String = "/"
    @State private var showCreateDirectory = false
    @State private var newDirectoryName: String = ""
    @State private var isCreatingDirectory = false
    @State private var createDirectoryError: String?

    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 8) {
                Text("FTP Server Browser")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Select destination directory on \(serverAddress)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if isConnecting {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("Connecting to FTP server...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            } else if let error = connectionError {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.orange)
                    
                    Text("Connection Failed")
                        .font(.headline)
                    
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    
                    Button("Retry") {
                        connectToServer()
                    }
                    .buttonStyle(.bordered)
                }
            } else if serverDirectories.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "folder")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    
                    Text("No directories found")
                        .font(.headline)
                    
                    Text("The FTP server appears to be empty or you don't have access to list directories")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            } else {
                // Directory list
                VStack(alignment: .leading, spacing: 12) {
                    Text("Available Directories")
                        .font(.headline)

                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(serverDirectories, id: \.self) { directory in
                                HStack {
                                    Button(action: {
                                        selectedPath = directory
                                    }) {
                                        Image(systemName: selectedPath == directory ? "largecircle.fill.circle" : "circle")
                                            .foregroundColor(selectedPath == directory ? .accentColor : .secondary)
                                    }
                                    .buttonStyle(.plain)

                                    Text(directory)
                                        .font(.system(.body, design: .monospaced))

                                    Spacer()
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(selectedPath == directory ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.05))
                                .cornerRadius(4)
                            }
                        }
                    }
                    .frame(maxHeight: 300)
                }
            }
            
            Spacer()
            
            // Create directory section
            if showCreateDirectory {
                VStack(spacing: 12) {
                    HStack {
                        TextField("New directory name", text: $newDirectoryName)
                            .textFieldStyle(.roundedBorder)

                        Button(isCreatingDirectory ? "Creating..." : "Create") {
                            createDirectory()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(newDirectoryName.isEmpty || isCreatingDirectory)

                        Button("Cancel") {
                            showCreateDirectory = false
                            newDirectoryName = ""
                            createDirectoryError = nil
                        }
                        .buttonStyle(.bordered)
                    }

                    if let error = createDirectoryError {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
                .padding()
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)
            }

            // Footer buttons
            HStack(spacing: 16) {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)

                Button("New Directory") {
                    showCreateDirectory.toggle()
                    createDirectoryError = nil
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Select Directory") {
                    selectedDirectory = selectedPath
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedPath.isEmpty)
            }
        }
        .padding(30)
        .frame(width: 600, height: 500)
        .onAppear {
            selectedPath = selectedDirectory.isEmpty ? "/" : selectedDirectory
            connectToServer()
        }
    }
    
    private func connectToServer() {
        isConnecting = true
        connectionError = nil
        
        Task {
            do {
                // Use --list-only for simple directory names
                let result = try await executeCurlCommand([
                    "-u", "\(username):\(password)",
                    "ftp://\(serverAddress):\(port)/",
                    "--connect-timeout", "10",
                    "--max-time", "30",
                    "--ftp-pasv",
                    "--list-only",
                    "--silent"
                ])
                
                await MainActor.run {
                    isConnecting = false

                    if result.exitCode == 0 {
                        // Parse the directory listing using regex to extract only directories
                        let directories = extractDirectories(from: result.output)
                        let items = directories.map { "/\($0)" }

                        // Always include root and add found directories
                        var allDirectories = ["/"]
                        allDirectories.append(contentsOf: items)

                        serverDirectories = allDirectories

                        // Pre-select the currently selected directory if it exists
                        if allDirectories.contains(selectedPath) {
                            // Keep current selection
                        } else {
                            selectedPath = "/"
                        }

                        print("FTP Browser: Found \(serverDirectories.count) items")
                        print("FTP Browser: Raw output: \(result.output)")
                        print("FTP Browser: Selected path: \(selectedPath)")
                    } else {
                        connectionError = "Failed to connect to FTP server (exit code: \(result.exitCode)). Please check your credentials and try again."
                        print("FTP Browser: Connection failed with exit code \(result.exitCode)")
                        print("FTP Browser: Error output: \(result.output)")
                    }
                }
            } catch {
                await MainActor.run {
                    isConnecting = false
                    connectionError = "Connection error: \(error.localizedDescription)"
                }
            }
        }
    }

    private func createDirectory() {
        isCreatingDirectory = true
        createDirectoryError = nil

        // Build the full path for the new directory
        let newDirPath = if selectedPath == "/" {
            "/\(newDirectoryName)"
        } else {
            "\(selectedPath)/\(newDirectoryName)"
        }

        Task {
            do {
                // Use curl to create the directory via FTP MKD command
                let result = try await executeCurlCommand([
                    "-u", "\(username):\(password)",
                    "ftp://\(serverAddress):\(port)/",
                    "-Q", "MKD \(newDirPath)",
                    "--connect-timeout", "10",
                    "--max-time", "30",
                    "--ftp-pasv"
                ])

                await MainActor.run {
                    isCreatingDirectory = false

                    if result.exitCode == 0 {
                        // Success - add to list locally and select it immediately
                        showCreateDirectory = false
                        print("FTP Browser: Created directory \(newDirPath)")

                        // Add the new directory to the list if not already there
                        if !serverDirectories.contains(newDirPath) {
                            serverDirectories.append(newDirPath)
                            serverDirectories.sort()
                        }

                        // Select the newly created directory
                        selectedPath = newDirPath
                        newDirectoryName = ""
                    } else {
                        createDirectoryError = "Failed to create directory. It may already exist or you don't have permission."
                        print("FTP Browser: Failed to create directory \(newDirPath), exit code: \(result.exitCode)")
                    }
                }
            } catch {
                await MainActor.run {
                    isCreatingDirectory = false
                    createDirectoryError = "Error: \(error.localizedDescription)"
                }
            }
        }
    }

    // Extract directories using regex patterns for Unix and Windows FTP servers
    private func extractDirectories(from listing: String) -> [String] {
        let lines = listing.components(separatedBy: .newlines)
        var directories: [String] = []
        
        // Unix-style: "drwxr-xr-x 2 user group 4096 Jan 1 12:00 dirname"
        let unixRegex = try! NSRegularExpression(pattern: #"^d.*\s(\S+)$"#)
        // Windows-style: "01-01-20 12:00AM <DIR> dirname"
        let windowsRegex = try! NSRegularExpression(pattern: #"<DIR>\s+(\S+)$"#)
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Skip empty lines and special entries
            if trimmed.isEmpty || trimmed == "." || trimmed == ".." { continue }
            
            // Skip FTP server messages and commands (more comprehensive filtering)
            if trimmed.hasPrefix("<") || trimmed.hasPrefix(">") || trimmed.hasPrefix("*") || 
               trimmed.hasPrefix("}") || trimmed.hasPrefix("{") || trimmed.hasPrefix("Host") ||
               trimmed.hasPrefix("IPv6") || trimmed.hasPrefix("IPv4") || trimmed.hasPrefix("Trying") ||
               trimmed.hasPrefix("Connected") || trimmed.hasPrefix("Entry path") || 
               trimmed.hasPrefix("Request has") || trimmed.hasPrefix("EPSV") || 
               trimmed.hasPrefix("Connect data") || trimmed.hasPrefix("ftp_perform") ||
               trimmed.hasPrefix("TYPE") || trimmed.hasPrefix("NLST") || trimmed.hasPrefix("Accepted") ||
               trimmed.hasPrefix("Maxdownload") || trimmed.hasPrefix("Remembering") ||
               trimmed.hasPrefix("matches total") || trimmed.hasPrefix("Connection") ||
               trimmed.hasPrefix("left intact") { continue }
            
            // Skip lines that contain FTP protocol keywords
            let lowercased = trimmed.lowercased()
            if lowercased.contains("welcome") || lowercased.contains("pure-ftpd") || 
               lowercased.contains("user number") || lowercased.contains("local time") ||
               lowercased.contains("server port") || lowercased.contains("private system") ||
               lowercased.contains("ipv6") || lowercased.contains("disconnected") ||
               lowercased.contains("user") || lowercased.contains("password") ||
               lowercased.contains("ok") || lowercased.contains("current location") ||
               lowercased.contains("entry path") || lowercased.contains("extended passive") ||
               lowercased.contains("connecting") || lowercased.contains("connected") ||
               lowercased.contains("type") || lowercased.contains("accepted") ||
               lowercased.contains("matches total") || lowercased.contains("connection") ||
               lowercased.contains("left intact") || lowercased.contains("data connection") ||
               lowercased.contains("passive") || lowercased.contains("ascii") { continue }
            
            let range = NSRange(location: 0, length: trimmed.utf16.count)
            
            // Try Unix-style pattern
            if let match = unixRegex.firstMatch(in: trimmed, options: [], range: range),
               let dirRange = Range(match.range(at: 1), in: trimmed) {
                let dirName = String(trimmed[dirRange])
                if !dirName.isEmpty {
                    directories.append(dirName)
                }
            }
            // Try Windows-style pattern
            else if let match = windowsRegex.firstMatch(in: trimmed, options: [], range: range),
                      let dirRange = Range(match.range(at: 1), in: trimmed) {
                let dirName = String(trimmed[dirRange])
                if !dirName.isEmpty {
                    directories.append(dirName)
                }
            }
            // For simple listings without format indicators, assume it's a directory if no file extension
            else {
                // Check if the name contains a dot followed by characters (indicating a file extension)
                // This catches any file with any extension (*.*)
                let hasFileExtension = trimmed.contains(".") && 
                                     !trimmed.hasSuffix(".") && 
                                     trimmed.lastIndex(of: ".") != trimmed.startIndex
                
                // Only add if it doesn't have a file extension and doesn't start with a dot (hidden files)
                if !hasFileExtension && !trimmed.hasPrefix(".") {
                    directories.append(trimmed)
                }
            }
        }
        
        return directories
    }
    
    private func executeCurlCommand(_ arguments: [String]) async throws -> (exitCode: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        process.arguments = arguments
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        try process.run()
        process.waitUntilExit()
        
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        
        let output = String(data: outputData, encoding: .utf8) ?? ""
        let error = String(data: errorData, encoding: .utf8) ?? ""
        
        return (process.terminationStatus, output + error)
    }
}
