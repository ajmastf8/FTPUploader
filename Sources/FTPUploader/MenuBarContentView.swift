import SwiftUI

/// Compact menu bar interface for FTP Uploader
/// Shows status of active configurations and provides quick controls
struct MenuBarContentView: View {
    @ObservedObject var syncManager: FileSyncManager
    @ObservedObject var storeManager: StoreKitManager
    @StateObject private var launchAtLoginManager = LaunchAtLoginManager.shared
    @State private var configurations: [FTPConfig] = []
    @State private var showPurchaseView = false
    @State private var hasLoadedConfigurations = false // Track if we've loaded at least once
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                // Use custom menu bar icon to match the actual menu bar
                if let icon = NSImage(named: "app-icon-menubar-orange") {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 16, height: 16)
                } else {
                    // Fallback to SF Symbol if custom icon not found
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title3)
                        .foregroundColor(.orange)
                }
                Text("FTP Uploader")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Configurations list
            if configurations.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No Configurations")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Button("Show Main Window") {
                        showMainWindow()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity)
                .padding()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(configurations) { config in
                            MenuBarConfigRow(
                                config: config,
                                syncManager: syncManager
                            )
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: calculateHeight())
                .id(warningStateKey) // Force re-render when warnings change
            }

            Divider()

            // Settings section with license status (App Store builds)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Toggle("Launch at Login", isOn: Binding(
                        get: { launchAtLoginManager.isEnabled },
                        set: { _ in
                            launchAtLoginManager.toggle()
                        }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .font(.system(size: 11))

                    Spacer()

                    // License status (App Store builds only)
                    if BuildType.current.showPurchaseUI {
                        if storeManager.isPurchased {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(.green)
                                Text("Licensed")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.green)
                            }
                        } else if storeManager.isTrialExpired {
                            Button("Trial Expired - Purchase") {
                                showPurchaseView = true
                            }
                            .buttonStyle(.borderless)
                            .controlSize(.small)
                            .font(.system(size: 10))
                            .foregroundColor(.orange)
                        } else {
                            let daysRemaining = storeManager.trialDaysRemaining
                            if daysRemaining > 0 {
                                Button("\(daysRemaining)d trial - Purchase") {
                                    showPurchaseView = true
                                }
                                .buttonStyle(.borderless)
                                .controlSize(.small)
                                .font(.system(size: 10))
                            }
                        }
                    }
                }

                if launchAtLoginManager.status == .requiresApproval {
                    Text("⚠️ Requires approval in System Settings")
                        .font(.system(size: 9))
                        .foregroundColor(.orange)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            .sheet(isPresented: $showPurchaseView) {
                PurchaseView(storeManager: storeManager, triggeredByExpiration: false)
            }

            Divider()

            // Footer actions
            HStack {
                Button("Show Main Window") {
                    showMainWindow()
                }
                .buttonStyle(.borderless)

                Spacer()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(width: 280)
        .onAppear {
            // Only load configurations once per app session to minimize keychain prompts
            // The cache in ConfigurationStorage will handle rapid repeated calls
            if !hasLoadedConfigurations {
                loadConfigurations()
                hasLoadedConfigurations = true

                // If still no configurations after load, open main window
                if configurations.isEmpty {
                    showMainWindow()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ConfigurationsChanged"))) { _ in
            // Reload configurations when explicitly notified of changes (save/delete)
            // This will hit the cache if called within the cache validity window
            loadConfigurations()
        }
    }

    /// Generate a unique key based on warning state to trigger view updates
    private var warningStateKey: String {
        // Create a key that changes whenever warnings are added/removed
        configurations.map { config in
            "\(config.id.uuidString):\(syncManager.configMonitorWarning[config.id] != nil ? "1" : "0")"
        }.joined(separator: ",")
    }

    /// Calculate dynamic height for config list based on number of configs and warnings
    private func calculateHeight() -> CGFloat {
        // Each MenuBarConfigRow is approximately 50px tall (padding + 2 rows of content)
        let rowHeight: CGFloat = 50

        // Warning banners add approximately 50px of additional height
        let warningHeight: CGFloat = 50

        // Count how many configs have warnings
        let warningCount = configurations.filter { config in
            syncManager.configMonitorWarning[config.id] != nil
        }.count

        // Calculate total height: base height + warning height
        let baseHeight = CGFloat(configurations.count) * rowHeight
        let totalWarningHeight = CGFloat(warningCount) * warningHeight
        let calculatedHeight = baseHeight + totalWarningHeight

        // Minimum height of 50px for at least one config, max 300px to prevent huge popover
        return min(max(calculatedHeight, 50), 300)
    }

    private func loadConfigurations() {
        // Load configurations from Keychain (with automatic JSON migration if needed)
        let loadedConfigs = ConfigurationStorage.shared.loadConfigurations()

        // Only update if different to avoid unnecessary redraws
        if loadedConfigs.map({ $0.id }) != configurations.map({ $0.id }) {
            configurations = loadedConfigs
            print("📱 Menu bar: Loaded \(loadedConfigs.count) configurations from Keychain")
        } else if loadedConfigs.isEmpty && !configurations.isEmpty {
            // Configurations were deleted - clear the list
            configurations = []
            print("📱 Menu bar: Cleared configurations (none found)")
        }
    }

    private func showMainWindow() {
        print("🪟 Show Main Window clicked")

        // First, try to activate and bring existing window to front
        NSApplication.shared.activate(ignoringOtherApps: true)

        // Look for existing main window
        var foundWindow = false
        for window in NSApplication.shared.windows {
            if window.title == "FTP Uploader" || window.identifier?.rawValue == "main" {
                print("🪟 Found existing main window, bringing to front")
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
                foundWindow = true
                break
            }
        }

        // If no window found, open a new one using SwiftUI's openWindow
        if !foundWindow {
            print("🪟 No existing window found, opening new main window")
            openWindow(id: "main")
        }
    }
}

/// Row displaying a single configuration's status in the menu bar
struct MenuBarConfigRow: View {
    let config: FTPConfig
    @ObservedObject var syncManager: FileSyncManager
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Monitor Conflict Warning Banner (if present)
            if let warning = syncManager.configMonitorWarning[config.id], let (level, message) = warning {
                MenuBarMonitorWarningBanner(level: level, message: message)
                    .padding(.bottom, 4)
            }

            // Top row: Status, clickable name, and controls
            HStack(spacing: 8) {
                // Status indicator
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)

                // Config name - clickable to open in main window
                Button(action: {
                    showMainWindow()
                }) {
                    HStack(spacing: 4) {
                        Text(config.name)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.blue)
                            .underline()
                            .lineLimit(1)

                        // Badge icon for warning/error states
                        if let state = syncManager.configConnectionState[config.id] {
                            if state == .error {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(.red)
                            } else if state == .warning {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(.orange)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
                .help(statusHelpText)

                Spacer()

                // Start/Stop button
                Button(action: {
                    toggleSync()
                }) {
                    Image(systemName: syncManager.isConfigSyncing(config.id) ? "stop.circle.fill" : "play.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(syncManager.isConfigSyncing(config.id) ? .red : .green)
                }
                .buttonStyle(.plain)
                .help(syncManager.isConfigSyncing(config.id) ? "Stop syncing" : "Start syncing")
            }

            // Bottom row: Session stats and local path
            HStack(spacing: 8) {
                // Files downloaded counter - cumulative for entire session
                if let fileCount = syncManager.configFileCounters[config.id], fileCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 9))
                            .foregroundColor(.blue)
                        Text("\(fileCount) file\(fileCount == 1 ? "" : "s")")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                }

                // Local path - clickable to open in Finder
                if !config.localSourcePath.isEmpty {
                    Button(action: {
                        openInFinder(path: config.localSourcePath)
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "folder.fill")
                                .font(.system(size: 9))
                                .foregroundColor(.orange)
                            Text(formatPath(config.localSourcePath))
                                .font(.system(size: 9))
                                .foregroundColor(.blue)
                                .underline()
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Open \(config.localSourcePath) in Finder")
                }
            }
            .padding(.leading, 16) // Align with config name above
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.001)) // Invisible but clickable
        .contentShape(Rectangle())
    }

    private var statusColor: Color {
        // Use unified status function - single source of truth
        let status = syncManager.getConnectionStatus(for: config.id)

        switch status {
        case .error, .warning:
            return .red  // Both error and warning use red
        case .connected:
            return .green
        case .connecting:
            return .orange
        case .idle:
            return .secondary
        }
    }

    private var statusHelpText: String {
        if let state = syncManager.configConnectionState[config.id] {
            switch state {
            case .error:
                if let errorMsg = syncManager.configConnectionError[config.id] {
                    return "Error: \(errorMsg)"
                }
                return "Error - click to view details"
            case .warning:
                if let errorMsg = syncManager.configConnectionError[config.id] {
                    return "Warning: \(errorMsg)"
                }
                return "Warning - click to view details"
            case .connected:
                return "Connected and syncing - click to view details"
            case .connecting:
                return "Connecting to FTP server..."
            case .idle:
                return "Idle - click to view details"
            }
        }
        return "Open \(config.name) in main window"
    }

    private func toggleSync() {
        if syncManager.isConfigSyncing(config.id) {
            syncManager.stopConfigSync(configId: config.id)
        } else {
            syncManager.startSync(config: config)
        }
    }

    private func showMainWindow() {
        print("🪟 Show Main Window clicked from config row")

        // First, try to activate and bring existing window to front
        NSApplication.shared.activate(ignoringOtherApps: true)

        // Look for existing main window
        var foundWindow = false
        for window in NSApplication.shared.windows {
            if window.title == "FTP Uploader" || window.identifier?.rawValue == "main" {
                print("🪟 Found existing main window, bringing to front")
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
                foundWindow = true
                break
            }
        }

        // If no window found, open a new one using SwiftUI's openWindow
        if !foundWindow {
            print("🪟 No existing window found, opening new main window")
            openWindow(id: "main")
        }
    }

    /// Opens the local path in Finder
    private func openInFinder(path: String) {
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.open(url)
    }

    /// Formats the path to show only the last few components (more readable in menu)
    private func formatPath(_ path: String) -> String {
        let url = URL(fileURLWithPath: path)
        let components = url.pathComponents

        // Show last 2 components if possible (e.g., "Downloads/FTP")
        if components.count >= 2 {
            let lastTwo = components.suffix(2).joined(separator: "/")
            return "…/\(lastTwo)"
        }

        return url.lastPathComponent
    }
}

// MARK: - Menu Bar Monitor Warning Banner
struct MenuBarMonitorWarningBanner: View {
    let level: String
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: bannerIcon)
                .font(.system(size: 12))
                .foregroundColor(bannerColor)

            Text(message)
                .font(.system(size: 10))
                .foregroundColor(.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(bannerBackgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(bannerColor, lineWidth: 1.5)
        )
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
