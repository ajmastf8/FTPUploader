import SwiftUI

struct ContentView: View {
    @StateObject private var ftpService = SimpleRustFTPService_FFI()
    @EnvironmentObject private var storeManager: StoreKitManager
    @EnvironmentObject private var demoModeManager: DemoModeManager
    @State private var configurations: [FTPConfig] = []
    @State private var selectedConfigIndex = 0
    @State private var showingNewConfig = false
    @State private var showingDeleteConfig = false
    @State private var showingExpirationWarning = false
    @State private var newConfiguration = FTPConfig()
    @State private var showingLogCollection = false
    @State private var showPurchaseView = false
    @State private var colorScheme: ColorScheme? = nil
    @State private var helpManager = HelpManager.shared

    // CRITICAL: ObservedObject wrapper around the global singleton
    // This allows UI to reactively update when configIsSyncing changes
    // while keeping the singleton alive across ContentView recreations
    @ObservedObject private var syncManager: FileSyncManager = {
        guard let manager = globalSyncManager else {
            fatalError("globalSyncManager must be initialized before ContentView")
        }
        print("🔗 ContentView: Linking to singleton FileSyncManager for UI updates")
        return manager
    }()

    init() {
        print("🎨 ContentView.init() called - using SINGLETON FileSyncManager")
        print("🔍 globalSyncManager exists: \(globalSyncManager != nil)")
        loadConfigurations()
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // FIXED HEADER (Always at top)
            VStack(spacing: 0) {
                HStack {
                    HStack(spacing: 12) {
                        Image(nsImage: NSImage(named: "app-icon") ?? NSImage())
                            .resizable()
                            .frame(width: 32, height: 32)
                            .clipShape(RoundedRectangle(cornerRadius: 6))

                        Text("FTP Downloader")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                    }

                    Spacer()

                    Button("New Configuration") {
                        // Create a completely fresh configuration instance
                        newConfiguration = FTPConfig()
                        showingNewConfig = true
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal)

                // Trial Status Banner (App Store builds only)
                if BuildType.current.showPurchaseUI {
                    TrialStatusBanner(storeManager: storeManager)
                        .padding(.horizontal)
                        .padding(.top, 8)
                }

                // Expiration Banner (Notarized builds only)
                if BuildType.current.useTimeExpiration {
                    ExpirationBanner(
                        expirationDate: getExpirationDateString(),
                        daysRemaining: daysUntilExpiration()
                    )
                    .padding(.horizontal)
                    .padding(.top, 8)
                }
            }
            .padding(.top, 0)
            .padding(.bottom, 20)
            .background(Color(NSColor.controlBackgroundColor))
            .frame(height: BuildType.current.useTimeExpiration ? 110 : 80) // FIXED HEADER HEIGHT - taller if showing expiration

            // Menu bar hint banner (always visible)
            HStack(spacing: 12) {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(.blue)
                    .font(.system(size: 14))

                Text("FTP Downloader runs from the menu bar. Closing this window keeps your syncs running in the background.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.blue.opacity(0.1))
            .cornerRadius(8)
            .padding(.horizontal, 16)
            .padding(.top, 8)

            // MAIN CONTENT AREA (Fixed layout)
            if !configurations.isEmpty {
                VStack(spacing: 0) { // No negative spacing
                    // Add proper spacing between header and tab card
                    Spacer().frame(height: 30)
                    
                    // Unified tab and card design
                    ZStack(alignment: .topLeading) {
                        // Background card that extends behind tabs
                        UnevenRoundedRectangle(
                            topLeadingRadius: 12,
                            bottomLeadingRadius: 12,
                            bottomTrailingRadius: 12,
                            topTrailingRadius: 12
                        )
                        .fill(Color(NSColor.controlBackgroundColor))
                        .shadow(
                            color: Color.black.opacity(0.05),
                            radius: 4,
                            x: 0,
                            y: 2
                        )
                        .overlay(
                            UnevenRoundedRectangle(
                                topLeadingRadius: 12,
                                bottomLeadingRadius: 12,
                                bottomTrailingRadius: 12,
                                topTrailingRadius: 12
                            )
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )
                        
                        // Content inside the unified card
                        VStack(spacing: 0) {
                            // Tabs positioned at the top of the card
                             HStack(spacing: 0) {
                                 ForEach(0..<configurations.count, id: \.self) { index in
                                     Button(action: {
                                         selectedConfigIndex = index
                                     }) {
                                         Text(configurations[index].name)
                                             .font(.system(.body, design: .default))
                                             .fontWeight(selectedConfigIndex == index ? .semibold : .medium)
                                             .foregroundColor(
                                                 syncManager.isConfigSyncing(configurations[index].id) ? .green : 
                                                 selectedConfigIndex == index ? .primary : .secondary
                                             )
                                             .padding(.horizontal, 20)
                                             .padding(.vertical, 12)
                                             .background(
                                                 selectedConfigIndex == index ? 
                                                 Color(NSColor.windowBackgroundColor) : 
                                                 Color(NSColor.controlBackgroundColor).opacity(0.7)
                                             )
                                             .clipShape(
                                                 UnevenRoundedRectangle(
                                                     topLeadingRadius: 0,
                                                     bottomLeadingRadius: 0,
                                                     bottomTrailingRadius: 0,
                                                     topTrailingRadius: 0
                                                 )
                                             )
                                     }
                                     .buttonStyle(.plain)
                                     
                                     // Add separator between tabs (except after the last one)
                                     if index < configurations.count - 1 {
                                         Rectangle()
                                             .fill(Color.secondary.opacity(0.3))
                                             .frame(width: 1, height: 20)
                                             .padding(.horizontal, 8)
                                     }
                                 }
                                 
                                 Spacer()
                             }
                            .padding(.horizontal)
                            .padding(.top, 8)
                            
                            // Config Details
                            ConfigurationDetailView(
                                config: $configurations[selectedConfigIndex],
                                syncManager: syncManager,
                                ftpService: ftpService,
                                onConfigChanged: saveConfigurations,
                                onDeleteConfig: {
                                    showingDeleteConfig = true
                                }
                            )
                            
                            // Live Notifications Section
                            VStack(alignment: .leading, spacing: 12) {
                                Divider()
                                    .padding(.horizontal)
                                
                                NotificationFeed(
                                    configId: configurations[selectedConfigIndex].id,
                                    syncManager: syncManager
                                )
                                .id(configurations[selectedConfigIndex].id)
                            }
                            .padding(.bottom, 20)
                        }
                    }
                    .padding(.horizontal)
                    .frame(height: 460)
                    .padding(.bottom, 20)
                }
                .padding() // Padding around entire content area
            } else {
                // Empty state when no configurations
                VStack(spacing: 20) {
                    Image(systemName: "gear")
                        .font(.system(size: 64))
                        .foregroundColor(.secondary)
                    
                    Text("No Configurations")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    
                    Text("Create your first FTP configuration to get started")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Button("Create Configuration") {
                        showingNewConfig = true
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            }
            
            Spacer().frame(height: 20) // Match top spacing for vertical centering
        }
        .frame(minWidth: 800, minHeight: 650)
        .frame(maxWidth: 900, maxHeight: 700)
        .background(Color(NSColor.windowBackgroundColor))
        .sheet(isPresented: $showingNewConfig) {
            FTPConfigurationView(
                configuration: $newConfiguration,
                isNewConfiguration: true,
                onSave: { newConfig in
                    print("🔍 Saving new configuration:")
                    print("   name: '\(newConfig.name)'")
                    print("   serverAddress: '\(newConfig.serverAddress)'")
                    print("   localDownloadPath: '\(newConfig.localDownloadPath)'")
                    print("   syncDirectories: \(newConfig.syncDirectories)")
                    
                    configurations.append(newConfig)
                    selectedConfigIndex = configurations.count - 1
                    saveConfigurations()
                    
                    // Clear notifications for the new configuration to start fresh
                    syncManager.clearConfigLogs(newConfig.id)
                    print("🧹 Cleared notifications for new configuration: \(newConfig.name)")
                },
                syncManager: syncManager
            )
            .frame(minWidth: 800, minHeight: 700)
            .frame(maxWidth: 900, maxHeight: 800)
        }
        .alert("Delete Configuration", isPresented: $showingDeleteConfig) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteCurrentConfiguration()
            }
        } message: {
            Text("Are you sure you want to delete the configuration '\(configurations.isEmpty ? "" : configurations[selectedConfigIndex].name)'? This action cannot be undone.")
        }
        .sheet(isPresented: $showingLogCollection) {
            LogCollectionView()
        }
        .sheet(isPresented: $helpManager.isHelpWindowOpen) {
            HelpWindow()
                .frame(minWidth: 900, minHeight: 700)
                .frame(maxWidth: 1200, maxHeight: 900)
        }
        .sheet(isPresented: $showPurchaseView) {
            PurchaseView(storeManager: storeManager, triggeredByExpiration: false)
        }
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                // FTP Downloader menu
                Menu("FTP Downloader") {
                    Button("About FTP Downloader") {
                        NSApp.orderFrontStandardAboutPanel(nil)
                    }

                    Divider()

                    if BuildType.current.showPurchaseUI {
                        if storeManager.isPurchased {
                            Button("License: Full Version") { }
                                .disabled(true)
                        } else if storeManager.isTrialExpired {
                            Button("Trial Expired - Purchase...") {
                                showPurchaseView = true
                            }
                        } else {
                            let daysRemaining = storeManager.trialDaysRemaining
                            if daysRemaining > 0 {
                                Button("Trial: \(daysRemaining) day\(daysRemaining == 1 ? "" : "s") left") { }
                                    .disabled(true)

                                Button("Purchase Full Version...") {
                                    showPurchaseView = true
                                }
                            }
                        }

                        Divider()
                    }

                    Button("Start Demo Mode") {
                        NotificationCenter.default.post(name: .startDemoMode, object: nil)
                    }
                }

                // View menu
                Menu("View") {
                    Menu("Theme Options") {
                        Button("System") {
                            colorScheme = nil
                            NSApp.appearance = nil
                        }

                        Button("Light") {
                            colorScheme = .light
                            NSApp.appearance = NSAppearance(named: .aqua)
                        }

                        Button("Dark") {
                            colorScheme = .dark
                            NSApp.appearance = NSAppearance(named: .darkAqua)
                        }
                    }
                }

                // Help menu
                Menu("Help") {
                    Button("FTP Downloader Help") {
                        helpManager.openHelp()
                    }

                    Button("Contact Support") {
                        showingLogCollection = true
                    }
                }
            }
        }
        .preferredColorScheme(colorScheme)
        .onAppear {
            loadConfigurations()

            // Check expiration on launch for builds that will expire
            if BuildType.current.useTimeExpiration {
                if isAppExpired() {
                    // App has expired - show non-dismissable alert and quit
                    let alert = NSAlert()
                    alert.messageText = "App Expired"
                    alert.informativeText = "This app expired on \(getExpirationDateString()). Please contact support for a new version."
                    alert.alertStyle = .critical
                    alert.addButton(withTitle: "Quit")
                    alert.runModal()
                    // Force quit using exit(0) to ensure app closes even if terminate() is blocked
                    exit(0)
                } else if daysUntilExpiration() <= 3 {
                    // Show warning if expiring soon (3 days or less)
                    showingExpirationWarning = true
                }
            }


            // Listen for demo mode notifications
            NotificationCenter.default.addObserver(
                forName: .startDemoMode,
                object: nil,
                queue: .main
            ) { [self] _ in
                startDemoMode()
            }

            NotificationCenter.default.addObserver(
                forName: .cleanupDemoMode,
                object: nil,
                queue: .main
            ) { [self] _ in
                cleanupDemoMode()
            }
        }
        .onDisappear {
            // Cleanup demo mode when view disappears (app quit)
            if demoModeManager.isDemoMode {
                cleanupDemoMode()
            }
        }
        .alert("App Expiration Notice", isPresented: $showingExpirationWarning) {
            Button("OK", role: .cancel) { }
            Button("Quit App") {
                NSApplication.shared.terminate(nil)
            }
        } message: {
            let days = daysUntilExpiration()
            if days == 0 {
                Text("This app will expire today (\(getExpirationDateString())). Please contact support for a new version immediately.")
            } else if days == 1 {
                Text("This app will expire tomorrow (\(getExpirationDateString())). Please contact support for a new version.")
            } else {
                Text("This app will expire in \(days) days (\(getExpirationDateString())). Please contact support for a new version.")
            }
        }
    }
    
    private func loadConfigurations() {
        print("🛡️  GUARD: loadConfigurations called - this method ONLY loads data")
        print("🛡️  GUARD: This method will NEVER start FTP connections or processes")

        // Load from Keychain (with automatic JSON migration if needed)
        let configs = ConfigurationStorage.shared.loadConfigurations()
        configurations = configs

        if !configs.isEmpty {
            print("✅ Loaded \(configs.count) configurations from Keychain")
            print("🛡️  GUARD: Configurations loaded but remain INACTIVE")
            print("🛡️  GUARD: User must press Start button to activate any configuration")
        } else {
            print("📁 No existing configurations found")
            print("🛡️  GUARD: No configurations to load - app is in clean state")
        }

        print("✅ loadConfigurations complete - NO FTP processes started")
    }
    
    private func deleteCurrentConfiguration() {
        guard !configurations.isEmpty else { return }

        // Stop sync for this configuration first
        let configToDelete = configurations[selectedConfigIndex]
        syncManager.stopConfigSync(configId: configToDelete.id)

        // Delete from Keychain
        _ = ConfigurationStorage.shared.deleteConfiguration(configToDelete.id)

        // Remove the configuration from array
        configurations.remove(at: selectedConfigIndex)

        // Adjust selected index if needed
        if configurations.isEmpty {
            selectedConfigIndex = 0
        } else if selectedConfigIndex >= configurations.count {
            selectedConfigIndex = configurations.count - 1
        }

        print("🗑️  Deleted configuration: \(configToDelete.name)")
    }

    private func saveConfigurations() {
        print("💾 Saving configurations - clearing old notifications for changed configs")

        // Filter out demo configurations - they should not persist across sessions
        let nonDemoConfigs = configurations.filter { $0.name != "Demo Configuration" }
        print("💾 Saving \(nonDemoConfigs.count) configurations (excluded \(configurations.count - nonDemoConfigs.count) demo configs)")

        // Save each configuration to Keychain
        var successCount = 0
        for config in nonDemoConfigs {
            if ConfigurationStorage.shared.saveConfiguration(config) {
                successCount += 1
            }
        }

        print("✅ Saved \(successCount)/\(nonDemoConfigs.count) configurations to Keychain")

        // Clear notifications for all configs since they may have changed
        syncManager.clearAllConfigLogs()
        print("🧹 Cleared all notifications after configuration save")
    }
    
    private func getConfigFileURL() -> URL {
        // Force initialization of AppFileManager
        AppFileManager.initialize()

        let url = AppFileManager.shared.configurationsFileURL
        print("📁 AppFileManager config URL: \(url.path)")
        AppFileManager.shared.printFileStructure()
        return url
    }

    // MARK: - Expiration Helpers

    /// Checks if the app has expired based on BuildTimestamp
    private func isAppExpired() -> Bool {
        // Only check expiration for notarized builds
        guard BuildType.current.useTimeExpiration else {
            return false
        }

        guard let expirationDate = getExpirationDate() else {
            return false
        }

        return Date() > expirationDate
    }

    /// Gets the expiration date from Info.plist BuildTimestamp + configured expiration days
    private func getExpirationDate() -> Date? {
        guard let buildTimestampString = Bundle.main.infoDictionary?["BuildTimestamp"] as? String else {
            print("⚠️ No BuildTimestamp found in Info.plist")
            return nil
        }

        let isoFormatter = ISO8601DateFormatter()
        guard let buildDate = isoFormatter.date(from: buildTimestampString) else {
            print("⚠️ Could not parse BuildTimestamp: \(buildTimestampString)")
            return nil
        }

        guard let expirationDays = BuildType.current.expirationDays else {
            return nil
        }

        return Calendar.current.date(byAdding: .day, value: expirationDays, to: buildDate)
    }

    /// Returns formatted expiration date string
    private func getExpirationDateString() -> String {
        guard let expirationDate = getExpirationDate() else {
            return "Unknown"
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter.string(from: expirationDate)
    }

    /// Returns the number of days until expiration
    private func daysUntilExpiration() -> Int {
        guard let expirationDate = getExpirationDate() else {
            return Int.max
        }

        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: Date(), to: expirationDate).day ?? 0
        return days
    }

    // MARK: - Demo Mode

    private func startDemoMode() {
        print("🎬 Starting demo mode from ContentView")

        demoModeManager.startDemoMode(syncManager: syncManager) { [self] config in
            // Add the demo config to configurations
            configurations.append(config)
            selectedConfigIndex = configurations.count - 1

            print("✅ Demo configuration added to list")
        }
    }

    private func cleanupDemoMode() {
        print("🧹 Cleaning up demo mode from ContentView")

        demoModeManager.cleanupDemoMode(configurations: &configurations, syncManager: syncManager)

        // Update selected index if needed
        if selectedConfigIndex >= configurations.count && !configurations.isEmpty {
            selectedConfigIndex = configurations.count - 1
        } else if configurations.isEmpty {
            selectedConfigIndex = 0
        }
    }

}

struct ConfigurationDetailView: View {
    @Binding var config: FTPConfig
    let syncManager: FileSyncManager
    let ftpService: FTPService
    let onConfigChanged: () -> Void
    let onDeleteConfig: () -> Void

    @State private var showingEditConfig = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Monitor Conflict Warning Banner (if present) - at very top of config detail
            if let warning = syncManager.configMonitorWarning[config.id], let (level, message) = warning {
                MonitorWarningBanner(level: level, message: message)
                    .padding(.bottom, 8)
            }

            VStack(alignment: .leading, spacing: 8) {
                // Top row: FTP Server Address + Start Button
                HStack(alignment: .top) {
                    // Left side: FTP Server Address
                    VStack(alignment: .leading, spacing: 8) {
                    Text("FTP Server Address: \(config.serverAddress):\(config.port)")
                        .font(.system(.body, design: .monospaced))
                    
                    HStack {
                        Text("FTP Paths:")
                            .font(.headline)
                        
                        Text(config.syncDirectories.joined(separator: " | "))
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Download Mode:")
                            .font(.headline)
                        
                        HStack(spacing: 4) {
                            Image(systemName: config.downloadMode == .deleteAfterDownload ? "trash" : "archivebox")
                                .foregroundColor(config.downloadMode == .deleteAfterDownload ? .red : .blue)
                            
                            Text(config.downloadMode == .deleteAfterDownload ? "Delete After Download" : "Keep After Download")
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    HStack {
                        Image(systemName: "folder")
                            .foregroundColor(.accentColor)
                        
                        Text("Local Download Directory:")
                            .font(.headline)
                        
                        Button(action: {
                            let url = URL(fileURLWithPath: config.localDownloadPath)
                            NSWorkspace.shared.open(url)
                        }) {
                            Text(config.localDownloadPath)
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(.blue)
                                .underline()
                        }
                        .buttonStyle(.plain)
                        .help("Click to open in Finder")
                    }
                    
                    // Connection Strategy (Phase 4: Real-time performance tracking)
                    HStack {
                        Image(systemName: "network")
                            .foregroundColor(.blue)
                        
                        Text("Connection Strategy:")
                            .font(.headline)
                        
                        HStack(spacing: 4) {
                            Text("\(config.downloadAggressiveness.connectionCount) connections")
                                .font(.system(.caption, design: .monospaced))
                                .fontWeight(.medium)
                                .foregroundColor(.green)
                            Text("(\(config.downloadAggressiveness.shortName))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // Session Statistics (Real-time performance tracking)
                    HStack {
                        Image(systemName: "chart.bar.fill")
                            .foregroundColor(.blue)
                        Text("Session:")
                            .font(.headline)
                        HStack(spacing: 4) {
                            // Use session report total files if available, otherwise fall back to counter
                            let sessionReport = syncManager.configSessionReports[config.id]
                            let fileCount = sessionReport?.totalFiles ?? (syncManager.configFileCounters[config.id] ?? 0)
                            // Use unified status function - single source of truth
                            let connectionState = syncManager.getConnectionStatus(for: config.id)
                            let isConnected = connectionState == .connected
                            let sessionTime = syncManager.configSessionStartTime[config.id]

                            if sessionTime != nil, isConnected {
                                // Connection timer
                                if let startTime = sessionTime {
                                    let duration = Date().timeIntervalSince(startTime)
                                    let minutes = Int(duration) / 60
                                    let seconds = Int(duration) % 60
                                    Text("\(minutes)m \(seconds)s")
                                        .font(.system(.caption, design: .monospaced))
                                        .fontWeight(.medium)
                                        .foregroundColor(.blue)
                                    Text("•")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                // Always show session stats when connected
                                Text("\(fileCount) files")
                                    .font(.system(.caption, design: .monospaced))
                                    .fontWeight(.medium)
                                    .foregroundColor(fileCount > 0 ? .green : .orange)

                                // Show active files/min (only time spent downloading)
                                let activeFilesPerMin = syncManager.getActiveFilesPerMinute(for: config.id)
                                if activeFilesPerMin > 0 {
                                    Text("•")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text("\(String(format: "%.1f", activeFilesPerMin)) files/min")
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(.green)
                                }

                                // Show average speed
                                let avgSpeed = syncManager.getSessionAverageSpeed(for: config.id)
                                if avgSpeed > 0 {
                                    Text("•")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    if avgSpeed >= 1.0 {
                                        Text("\(String(format: "%.2f", avgSpeed)) MB/s")
                                            .font(.system(.caption, design: .monospaced))
                                            .foregroundColor(.green)
                                    } else {
                                        Text("\(String(format: "%.0f", avgSpeed * 1024)) KB/s")
                                            .font(.system(.caption, design: .monospaced))
                                            .foregroundColor(.green)
                                    }
                                }
                            } else {
                                // Show idle state when not connected
                                Text("Not active")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                
                Spacer()
                
                // Right side: Start/Stop button and connection status
                VStack(alignment: .trailing, spacing: 4) {
                    Button(action: {
                        print("========================================")
                        print("🔘 START/STOP BUTTON CLICKED for config: \(config.name)")
                        print("🔘 Current sync state: \(syncManager.isConfigSyncing(config.id))")
                        print("========================================")
                        if syncManager.isConfigSyncing(config.id) {
                            print("🛑 Stopping sync for: \(config.name)")
                            syncManager.stopConfigSync(configId: config.id)
                        } else {
                            print("▶️ Starting sync for: \(config.name)")
                            print("▶️ About to call syncManager.startSync()")
                            syncManager.startSync(config: config)
                            print("▶️ syncManager.startSync() call completed")
                        }
                    }) {
                        HStack {
                            Image(systemName: syncManager.isConfigSyncing(config.id) ? "stop.fill" : "play.fill")
                            Text(syncManager.isConfigSyncing(config.id) ? "Stop" : "Start")
                        }
                        .frame(minWidth: 100)
                        .foregroundColor(syncManager.isConfigSyncing(config.id) ? .red : .white)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(false) // Always enable the button

                    // Connection status under button - uses unified status function
                    HStack {
                        let status = syncManager.getConfigSyncStatus(config.id)
                        let isPaused = status.contains("sleeping")
                        let isResuming = status.contains("Resuming")

                        // Use unified status function - single source of truth
                        let connectionState = syncManager.getConnectionStatus(for: config.id)
                        let errorMessage = syncManager.configConnectionError[config.id]

                        Image(systemName:
                            isResuming ? "arrow.clockwise.circle" :
                            isPaused ? "moon.circle" :
                            connectionState == .error || connectionState == .warning ? "exclamationmark.triangle" :
                            connectionState == .connecting ? "antenna.radiowaves.left.and.right" :
                            connectionState == .connected ? "checkmark.circle" : "xmark.circle"
                        )
                        .foregroundColor(
                            isResuming ? .orange :
                            isPaused ? .yellow :
                            connectionState == .error || connectionState == .warning ? .red :
                            connectionState == .connecting ? .orange :
                            connectionState == .connected ? .green : .secondary
                        )

                        Text(
                            isResuming ? "Waking from Sleep" :
                            isPaused ? "Paused for Sleep" :
                            connectionState == .error || connectionState == .warning ? (errorMessage ?? "Connection Error") :
                            connectionState == .connecting ? "Connecting..." :
                            connectionState == .connected ? "Connected" : "Not Connected"
                        )
                        .font(.caption)
                        .foregroundColor(
                            isResuming ? .orange :
                            isPaused ? .yellow :
                            connectionState == .error || connectionState == .warning ? .red :
                            connectionState == .connecting ? .orange :
                            connectionState == .connected ? .green : .secondary
                        )
                    }
                }
            }

            // Control Buttons
            HStack(spacing: 16) {
                // Edit button stays visible
                Button("Edit") {
                    showingEditConfig = true
                }
                .buttonStyle(.bordered)
                .disabled(syncManager.isConfigSyncing(config.id))
                
                // Connection timer and file speed info
                Spacer()
                
                // Menu button for additional actions
                Menu {
                    Button("Export Configuration") {
                        exportConfiguration(config)
                    }

                    Divider()

                    Button("Clear Downloaded Files") {
                        clearDownloadedFiles(config)
                    }

                    Divider()

                    Button("Delete Configuration", role: .destructive) {
                        onDeleteConfig()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title2)
                }
                .buttonStyle(.plain)
            }
            }
        }
        .padding()
        .sheet(isPresented: $showingEditConfig) {
            FTPConfigurationView(
                configuration: $config,
                isNewConfiguration: false,
                onSave: { _ in
                    onConfigChanged()
                },
                syncManager: syncManager
            )
            .frame(minWidth: 800, minHeight: 700)
            .frame(maxWidth: 900, maxHeight: 800)
        }
        // Removed automatic connection and file scanning - now waits for Start button
    }
    
    // MARK: - Helper Methods
    private func exportConfiguration(_ config: FTPConfig) {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.json]
        savePanel.nameFieldStringValue = "\(config.name)_config.json"
        savePanel.title = "Export Configuration"
        savePanel.message = "Choose where to save the configuration file"

        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                do {
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = .prettyPrinted
                    // Use createSaveableCopy to avoid @Published/Codable issues
                    // Clear local download path - the importer will need to set their own
                    // and grant security-scoped bookmark permissions
                    var exportConfig = config.createSaveableCopy()
                    exportConfig.localDownloadPath = ""
                    exportConfig.directoryBookmark = nil
                    let data = try encoder.encode(exportConfig)
                    try data.write(to: url)
                    print("✅ Configuration exported to: \(url.path)")
                    print("   📁 Local download path cleared for security")
                } catch {
                    print("❌ Failed to export configuration: \(error)")
                }
            }
        }
    }
    
    private func clearDownloadedFiles(_ config: FTPConfig) {
        // Create an alert to confirm the action
        let alert = NSAlert()
        alert.messageText = "Clear Downloaded Files"
        alert.informativeText = "This will clear the list of downloaded files for '\(config.name)', causing all files to be re-downloaded on the next sync. This action cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Clear Files")
        alert.addButton(withTitle: "Cancel")
        
        if alert.runModal() == .alertFirstButtonReturn {
            // User confirmed - clear the downloaded files JSON
            Task {
                await clearDownloadedFilesJSON(for: config.id)
            }
        }
    }
    
    private func clearDownloadedFilesJSON(for configId: UUID) async {
        // Use the Rust FFI to clear the database entries for this config
        let success = RustFTPBridge.clearConfigData(for: configId)

        if success {
            print("✅ Cleared downloaded files from database for config: \(configId)")

            // Add notification via the sync manager
            await MainActor.run {
                syncManager.addConfigLog(configId, message: "✅ Downloaded files list cleared - all files will be re-downloaded on next sync")
            }
        } else {
            print("❌ Failed to clear downloaded files from database for config: \(configId)")

            // Add error notification
            await MainActor.run {
                syncManager.addConfigLog(configId, message: "❌ Failed to clear downloaded files list from database")
            }
        }
    }
    
    private func formatConnectionTime(_ date: Date) -> String {
        let now = Date()
        let timeInterval = now.timeIntervalSince(date)
        
        if timeInterval < 60 {
            return "\(Int(timeInterval))s"
        } else if timeInterval < 3600 {
            let minutes = Int(timeInterval / 60)
            let seconds = Int(timeInterval.truncatingRemainder(dividingBy: 60))
            return "\(minutes)m \(seconds)s"
        } else {
            let hours = Int(timeInterval / 3600)
            let minutes = Int((timeInterval.truncatingRemainder(dividingBy: 3600)) / 60)
            return "\(hours)h \(minutes)m"
        }
    }
    
               // Download speed method temporarily removed
           // private func getDownloadSpeed(for configId: UUID) -> String? {
           //     // Get download speed from sync manager
           //     let downloadSpeed = syncManager.getConfigDownloadSpeed(configId)
           //     if !downloadSpeed.isEmpty && downloadSpeed != "0 KB/s" {
           //         return downloadSpeed
           //     }
           //     
           //     // If no speed available, show current operation
           //     let currentOperation = syncManager.getConfigCurrentOperation(configId)
           //     if currentOperation != "Idle" {
           //         return currentOperation
           //     }
           //     
           //     return nil
           // }
    
    private func extractFilename(from message: String) -> String? {
        // Extract filename from messages like "Downloading: example.zip"
        let patterns = [
            #"Downloading:\s*(.+)"#,
            #"Processing:\s*(.+)"#,
            #"File:\s*(.+)"#
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: message, range: NSRange(message.startIndex..., in: message)),
               let range = Range(match.range(at: 1), in: message) {
                return String(message[range]).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }
    
    // Removed automatic connection methods - now waits for Start button
}

struct FileRowView: View {
    let file: FTPFile
    let progress: Double
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(file.name)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
                
                Text("\(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file)) • \(file.path)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 1) {
                Text(file.downloadStatus.rawValue)
                    .font(.caption)
                    .foregroundColor(statusColor)
                
                if file.downloadStatus == .downloading {
                    ProgressView(value: progress)
                        .frame(width: 60)
                } else if file.downloadStatus == .monitoring {
                    Text("Ready")
                        .font(.caption2)
                        .foregroundColor(.green)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }
    
    private var statusColor: Color {
        switch file.downloadStatus {
        case .pending:
            return .orange
        case .monitoring:
            return .blue
        case .downloading:
            return .green
        case .completed:
            return .green
        case .failed:
            return .orange  // Change from red to orange since it's retrying
        case .deleted:
            return .secondary
        }
    }
}

// MARK: - Monitor Warning Banner
struct MonitorWarningBanner: View {
    let level: String
    let message: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: bannerIcon)
                .font(.system(size: 16))
                .foregroundColor(bannerColor)

            Text(message)
                .font(.system(size: 13))
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(bannerBackgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(bannerColor, lineWidth: 2)
        )
        .shadow(color: bannerColor.opacity(0.3), radius: 4, x: 0, y: 2)
    }

    private var bannerIcon: String {
        switch level {
        case "critical":
            return "exclamationmark.octagon.fill"
        case "warning":
            return "exclamationmark.triangle.fill"
        case "info":
            return "info.circle.fill"
        default:
            return "exclamationmark.circle.fill"
        }
    }

    private var bannerColor: Color {
        switch level {
        case "critical":
            return .red
        case "warning":
            return .orange
        case "info":
            return .blue
        default:
            return .yellow
        }
    }

    private var bannerBackgroundColor: Color {
        switch level {
        case "critical":
            return Color.red.opacity(0.15)
        case "warning":
            return Color.orange.opacity(0.15)
        case "info":
            return Color.blue.opacity(0.15)
        default:
            return Color.yellow.opacity(0.15)
        }
    }
}

// MARK: - Expiration Banner
struct ExpirationBanner: View {
    let expirationDate: String
    let daysRemaining: Int

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: bannerIcon)
                .font(.system(size: 14))
                .foregroundColor(bannerColor)

            Text(bannerText)
                .font(.caption)
                .foregroundColor(.primary)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(bannerBackgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(bannerColor.opacity(0.3), lineWidth: 1)
        )
    }

    private var bannerText: String {
        if daysRemaining == 0 {
            return "This app expires today (\(expirationDate))"
        } else if daysRemaining == 1 {
            return "This app expires tomorrow (\(expirationDate))"
        } else if daysRemaining <= 3 {
            return "This app expires in \(daysRemaining) days (\(expirationDate))"
        } else {
            return "This app expires on \(expirationDate) (\(daysRemaining) days remaining)"
        }
    }

    private var bannerIcon: String {
        if daysRemaining <= 3 {
            return "exclamationmark.triangle.fill"
        } else {
            return "calendar.badge.clock"
        }
    }

    private var bannerColor: Color {
        if daysRemaining == 0 {
            return .red
        } else if daysRemaining <= 3 {
            return .orange
        } else {
            return .blue
        }
    }

    private var bannerBackgroundColor: Color {
        if daysRemaining == 0 {
            return Color.red.opacity(0.1)
        } else if daysRemaining <= 3 {
            return Color.orange.opacity(0.1)
        } else {
            return Color.blue.opacity(0.1)
        }
    }
}

#Preview {
    ContentView()
}
