import SwiftUI
import os.log
import Cocoa
import SystemConfiguration
import IOKit.pwr_mgt

// Global reference to sync manager for cleanup
// CRITICAL: FileSyncManager MUST be a singleton to survive ContentView recreations
// If ContentView is recreated (which SwiftUI can do), we need the same FileSyncManager instance
// Otherwise configIsSyncing dictionary gets reset and sleep/wake tracking fails
var globalSyncManager: FileSyncManager?

// Global reference to store manager for menu bar access
var globalStoreManager: StoreKitManager?

// App delegate to handle termination and background activity
class AppDelegate: NSObject, NSApplicationDelegate {
    var backgroundActivity: NSObjectProtocol?
    var lastActiveTime: Date = Date()
    var healthCheckTimer: Timer?
    var networkReachability: SCNetworkReachability?
    var lastNetworkStatus: SCNetworkReachabilityFlags?

    // IOKit power management
    var powerNotificationPort: IONotificationPortRef?
    var powerNotifier: io_object_t = 0

    // Menu bar items
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("🚀 App finished launching - setting up background activity")
        print("🚀 AppDelegate instance: \(Unmanaged.passUnretained(self).toOpaque())")

        // Track app launch time for log filtering
        LogCollectionService.shared.appLaunchTime = Date()

        // Hide dock icon - menu bar app only
        NSApp.setActivationPolicy(.accessory)

        // Setup menu bar
        setupMenuBar()

        // Prevent automatic termination when screen locks or screen saver activates
        // This tells macOS to keep the app alive even when in background
        let activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .suddenTerminationDisabled, .automaticTerminationDisabled, .idleSystemSleepDisabled],
            reason: "FTP file synchronization and monitoring"
        )
        self.backgroundActivity = activity

        print("✅ Background activity token acquired - app will stay alive when screen locked")

        // Monitor screen lock/unlock events
        setupScreenLockMonitoring()

        // Monitor system sleep/wake events
        setupSleepWakeMonitoring()

        // Monitor network changes
        setupNetworkMonitoring()

        // Start health check timer as failsafe
        setupHealthCheckTimer()

        // Auto-start configurations marked with runOnLaunch
        autoStartConfigurations()

        // Hide main window if configs exist, show it if empty
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.hideMainWindowIfConfigsExist()
        }

        // Listen for requests to open main window
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(showMainWindow),
            name: NSNotification.Name("OpenMainWindow"),
            object: nil
        )

        // Listen for sync status changes to update icon
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSyncStatusChange),
            name: NSNotification.Name("SyncStatusChanged"),
            object: nil
        )
    }

    @objc private func handleSyncStatusChange() {
        updateMenuBarIcon()
    }

    private func setupMenuBar() {
        // Create status item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        guard let button = statusItem?.button else {
            print("❌ Failed to create status item button")
            return
        }

        // Set initial icon
        updateMenuBarIcon()

        // Setup click handlers
        button.action = #selector(togglePopover)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.target = self

        // Create popover
        popover = NSPopover()
        popover?.contentSize = NSSize(width: 280, height: 400)
        popover?.behavior = .transient

        // Setup popover content
        if let syncManager = globalSyncManager, let storeManager = globalStoreManager {
            let contentView = MenuBarContentView(syncManager: syncManager, storeManager: storeManager)
            popover?.contentViewController = NSHostingController(rootView: contentView)
        }

        print("✅ Menu bar setup complete")
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem?.button else { return }

        // Check if this is a right-click
        if let event = NSApp.currentEvent, event.type == .rightMouseUp {
            showContextMenu()
        } else {
            // Left click - toggle popover
            if popover?.isShown == true {
                popover?.performClose(nil)
            } else {
                popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            }
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()

        menu.addItem(NSMenuItem(title: "Show Main Window", action: #selector(showMainWindow), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit FTP Downloader", action: #selector(quitApp), keyEquivalent: "q"))

        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    @objc private func showMainWindow() {
        print("🪟 Show Main Window clicked from menu bar")

        // First, try to activate and bring existing window to front
        NSApplication.shared.activate(ignoringOtherApps: true)

        // Look for existing main window
        var foundWindow = false
        for window in NSApplication.shared.windows {
            if window.title == "FTP Downloader" || window.identifier?.rawValue == "main" {
                print("🪟 Found existing main window, bringing to front")
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
                foundWindow = true
                break
            }
        }

        // If no window found, we need to open one
        // Since we're in AppDelegate, we'll post a notification to request window opening
        if !foundWindow {
            print("🪟 No existing window found, posting notification to open main window")
            NotificationCenter.default.post(name: NSNotification.Name("OpenMainWindow"), object: nil)
        }
    }

    private func hideMainWindowIfConfigsExist() {
        // Load configurations from Keychain (with automatic JSON migration if needed)
        let configs = ConfigurationStorage.shared.loadConfigurations()

        guard !configs.isEmpty else {
            // No configs - leave window visible for first-run experience
            print("🪟 No configurations found - leaving main window visible for setup")
            return
        }

        // Configs exist - hide the main window to go into menu bar-only mode
        print("🪟 Found \(configs.count) configuration(s) - hiding main window for menu bar-only mode")
        for window in NSApplication.shared.windows {
            if window.title == "FTP Downloader" || window.identifier?.rawValue == "main" {
                print("🪟 Hiding main window - app will run in menu bar only")
                window.orderOut(nil)
                break
            }
        }
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    private func updateMenuBarIcon() {
        Task { @MainActor in
            guard let button = statusItem?.button else { return }
            guard let syncManager = globalSyncManager else { return }

            // Use unified status function - single source of truth
            let overallStatus = syncManager.getOverallStatus()

            print("🎨 updateMenuBarIcon: overallStatus = \(overallStatus)")

            // Choose icon based on unified status
            // Priority: error/warning (red) > connected (green) > connecting (green) > idle (orange)
            let iconName: String
            switch overallStatus {
            case .error, .warning:
                iconName = "app-icon-menubar-red"  // Both error and warning use red
            case .connected, .connecting:
                iconName = "app-icon-menubar-green"  // Active states use green
            case .idle:
                iconName = "app-icon-menubar-orange"  // Idle uses orange
            }

            // Try to load the custom menu bar icon
            if let sourceIcon = NSImage(named: iconName) {
                // Create a new image at the desired size
                let targetSize = NSSize(width: 18, height: 18)
                let resizedIcon = NSImage(size: targetSize)

                resizedIcon.lockFocus()
                sourceIcon.draw(in: NSRect(origin: .zero, size: targetSize),
                               from: NSRect(origin: .zero, size: sourceIcon.size),
                               operation: .copy,
                               fraction: 1.0)
                resizedIcon.unlockFocus()

                button.image = resizedIcon
                print("🎨 Menu bar icon updated to: \(iconName)")
            } else {
                // Fallback to SF Symbol if custom icons not found
                print("⚠️ Custom icon '\(iconName)' not found, using SF Symbol fallback")

                let symbolColor: NSColor
                switch overallStatus {
                case .error, .warning:
                    symbolColor = .systemRed
                case .connected, .connecting:
                    symbolColor = .systemGreen
                case .idle:
                    symbolColor = .systemOrange
                }

                let config = NSImage.SymbolConfiguration(pointSize: 0, weight: .regular)
                    .applying(.init(paletteColors: [symbolColor]))
                if let image = NSImage(systemSymbolName: "arrow.down.circle.fill", accessibilityDescription: "FTP Downloader") {
                    button.image = image.withSymbolConfiguration(config)
                }
            }
        }
    }

    // Prevent app from quitting when window closes (menu bar app behavior)
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        print("🛑 App terminating - cleaning up all processes")

        // Clean up IOKit power notifications
        if powerNotifier != 0 {
            IODeregisterForSystemPower(&powerNotifier)
            print("✅ IOKit power notifications deregistered")
        }

        if let port = powerNotificationPort {
            IONotificationPortDestroy(port)
            powerNotificationPort = nil
            print("✅ IOKit notification port destroyed")
        }

        // End background activity
        if let activity = backgroundActivity {
            ProcessInfo.processInfo.endActivity(activity)
            print("✅ Background activity token released")
        }

        globalSyncManager?.terminateAllProcesses()

        // Cleanup demo mode if active
        Task { @MainActor in
            if DemoModeManager.shared.isDemoMode {
                print("🧹 Cleaning up demo mode on app termination")
                // Note: configurations cleanup will be handled by ContentView
                NotificationCenter.default.post(name: .cleanupDemoMode, object: nil)
            }
        }
    }

    private func setupScreenLockMonitoring() {
        // Monitor screen lock events
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { _ in
            print("🔒 Screen locked - FTP processes should continue running")
            print("🔒 Background activity: \(self.backgroundActivity != nil ? "ACTIVE" : "INACTIVE")")
        }

        // Monitor screen unlock events
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { _ in
            print("🔓 Screen unlocked - FTP processes still running")
        }

        // Monitor screen saver start
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.screensaver.didstart"),
            object: nil,
            queue: .main
        ) { _ in
            print("🖼️ Screen saver started - FTP processes should continue running")
            print("🖼️ Background activity: \(self.backgroundActivity != nil ? "ACTIVE" : "INACTIVE")")
        }

        // Monitor screen saver stop
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.screensaver.didstop"),
            object: nil,
            queue: .main
        ) { _ in
            print("🖼️ Screen saver stopped - FTP processes still running")
        }

        print("✅ Screen lock and screen saver monitoring setup complete")
    }

    private func setupSleepWakeMonitoring() {
        print("🔧 Setting up IOKit power management notifications...")
        print("🔧 This is the low-level API that works for ALL app types, including menu bar apps")

        // ALSO keep NSWorkspace notifications as backup (doesn't hurt to have both)
        // Monitor system sleep
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            let sleepTime = Date()
            print("💤💤💤 SLEEP NOTIFICATION (NSWorkspace) RECEIVED AT \(sleepTime) 💤💤💤")
            print("💤 System will sleep - stopping all Rust processes cleanly")

            // Update last active time so failsafe doesn't double-trigger
            self?.lastActiveTime = sleepTime

            // Log to notification feed
            NotificationCenter.default.post(
                name: .appSystemNotification,
                object: nil,
                userInfo: [
                    "message": "System going to sleep - stopping FTP monitoring cleanly",
                    "type": "info"
                ]
            )

            // Stop all Rust processes before sleep to avoid stuck/zombie processes
            Task { @MainActor in
                globalSyncManager?.pauseAllActiveConfigurations()
            }
        }

        // Monitor system wake - THIS IS CRITICAL
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let wakeTime = Date()
            print("⏰⏰⏰ WAKE NOTIFICATION (NSWorkspace) RECEIVED AT \(wakeTime) ⏰⏰⏰")
            print("⏰ NSWorkspace.didWakeNotification fired successfully")
            print("⏰ Notification object: \(notification)")
            print("⏰ System woke from sleep - restarting active FTP configurations")
            print("⏰ globalSyncManager is \(globalSyncManager == nil ? "NIL" : "AVAILABLE")")
            print("⏰ Thread: \(Thread.current), isMain: \(Thread.isMainThread)")

            // CRITICAL: Verify we have a sync manager before proceeding
            guard globalSyncManager != nil else {
                print("❌ ERROR: globalSyncManager is NIL - cannot restart configurations!")
                print("❌ This is a critical bug - the sync manager should always be available")
                return
            }

            // Update last active time so failsafe doesn't double-trigger
            self?.lastActiveTime = wakeTime

            // Log to notification feed
            NotificationCenter.default.post(
                name: .appSystemNotification,
                object: nil,
                userInfo: [
                    "message": "System woke from sleep - restarting FTP monitoring immediately",
                    "type": "info"
                ]
            )

            // Restart all active sync configurations with delay for network stack
            // Network stack needs time to fully initialize after wake
            print("⏰ Scheduling restart in 5 seconds to allow network stack to stabilize...")
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                print("⏰⏰⏰ EXECUTING RESTART NOW (from NSWorkspace notification) ⏰⏰⏰")
                print("⏰ Thread: \(Thread.current), isMain: \(Thread.isMainThread)")
                print("⏰ Calling restartActiveConfigurations()")

                // Double-check manager is still available
                guard let manager = globalSyncManager else {
                    print("❌ ERROR: globalSyncManager became NIL before restart!")
                    return
                }

                manager.restartActiveConfigurations()
                print("⏰ restartActiveConfigurations() completed")
            }
        }

        // IOKit power management notifications - WORKS FOR MENU BAR APPS!
        // This is the low-level API that doesn't rely on NSWorkspace
        let rootPort = IORegisterForSystemPower(
            Unmanaged.passUnretained(self).toOpaque(),
            &powerNotificationPort,
            { (refcon, notifier, messageType, messageArgument) in
                guard let refcon = refcon else { return }
                let appDelegate = Unmanaged<AppDelegate>.fromOpaque(refcon).takeUnretainedValue()
                appDelegate.handlePowerNotification(messageType: messageType, messageArgument: messageArgument)
            },
            &powerNotifier
        )

        if rootPort == 0 {
            print("❌ ERROR: Failed to register for IOKit power notifications")
        } else {
            // Add the notification port to the run loop
            if let port = powerNotificationPort {
                CFRunLoopAddSource(
                    CFRunLoopGetCurrent(),
                    IONotificationPortGetRunLoopSource(port).takeUnretainedValue(),
                    .defaultMode
                )
                print("✅ IOKit power notifications registered successfully")
                print("✅ This WILL work for menu bar apps (UIElement)")
            } else {
                print("❌ ERROR: powerNotificationPort is nil")
            }
        }

        print("✅ Sleep/wake monitoring setup complete (NSWorkspace + IOKit)")

        // VERIFICATION: Schedule a test to ensure observers are working
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            print("🔍 VERIFICATION: Sleep/wake observers are still registered")
            print("🔍 AppDelegate instance still alive: \(Unmanaged.passUnretained(self).toOpaque())")
            print("🔍 Background activity: \(self.backgroundActivity != nil ? "ACTIVE" : "INACTIVE")")
            print("🔍 IOKit power notifier: \(self.powerNotifier != 0 ? "REGISTERED" : "NOT REGISTERED")")
        }
    }

    /// Handle IOKit power management notifications
    /// This is called by the IOKit power management callback
    private func handlePowerNotification(messageType: natural_t, messageArgument: UnsafeMutableRawPointer?) {
        // IOMessage constants (from IOKit/IOMessage.h):
        // kIOMessageCanSystemSleep = 0xe0000270
        // kIOMessageSystemWillSleep = 0xe0000280
        // kIOMessageSystemHasPoweredOn = 0xe0000300

        switch messageType {
        case 0xe0000270:  // kIOMessageCanSystemSleep
            // System is about to sleep - we can veto it, but we won't
            print("💤💤💤 IOKit: System CAN sleep (kIOMessageCanSystemSleep)")
            IOAllowPowerChange(powerNotifier, Int(bitPattern: messageArgument))

        case 0xe0000280:  // kIOMessageSystemWillSleep
            // System is definitely going to sleep
            let sleepTime = Date()
            print("💤💤💤 IOKit: System WILL sleep (kIOMessageSystemWillSleep) at \(sleepTime)")
            print("💤 Stopping all Rust processes cleanly before sleep")

            // Update last active time so failsafe doesn't double-trigger
            lastActiveTime = sleepTime

            // CRITICAL: Capture which configs are running RIGHT NOW, synchronously
            // This prevents a race condition where async dispatch might delay execution
            // and allow Rust processes to exit and clear state before we can save it
            if Thread.isMainThread {
                // Already on main thread - use MainActor.assumeIsolated for safe synchronous access
                print("💤 ON MAIN THREAD: Capturing running configs state IMMEDIATELY")
                MainActor.assumeIsolated {
                    print("💤 Current configIsSyncing state: \(globalSyncManager?.configIsSyncing ?? [:])")
                    globalSyncManager?.pauseAllActiveConfigurations()
                    print("💤 ON MAIN THREAD: State captured, configs saved for resume")
                }
            } else {
                // Not on main thread - sync dispatch to main
                DispatchQueue.main.sync {
                    MainActor.assumeIsolated {
                        print("💤 SYNC DISPATCH: Capturing running configs state IMMEDIATELY")
                        print("💤 Current configIsSyncing state: \(globalSyncManager?.configIsSyncing ?? [:])")
                        globalSyncManager?.pauseAllActiveConfigurations()
                        print("💤 SYNC DISPATCH: State captured, configs saved for resume")
                    }
                }
            }

            // Now post notification asynchronously (doesn't need to be sync)
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .appSystemNotification,
                    object: nil,
                    userInfo: [
                        "message": "System going to sleep (IOKit) - stopping FTP monitoring cleanly",
                        "type": "info"
                    ]
                )
            }

            // MUST acknowledge the sleep notification
            IOAllowPowerChange(powerNotifier, Int(bitPattern: messageArgument))

        case 0xe0000300:  // kIOMessageSystemHasPoweredOn
            // System has woken from sleep
            let wakeTime = Date()
            print("⏰⏰⏰ IOKit: System HAS POWERED ON (kIOMessageSystemHasPoweredOn) at \(wakeTime)")
            print("⏰ This is the RELIABLE wake notification for menu bar apps")
            print("⏰ System woke from sleep - restarting active FTP configurations")

            // Update last active time so failsafe doesn't double-trigger
            lastActiveTime = wakeTime

            // Log to notification feed and restart configs on main thread
            DispatchQueue.main.async {
                print("⏰ IOKit wake: On main thread, globalSyncManager is \(globalSyncManager == nil ? "NIL" : "AVAILABLE")")

                guard globalSyncManager != nil else {
                    print("❌ ERROR: globalSyncManager is NIL - cannot restart configurations!")
                    return
                }

                NotificationCenter.default.post(
                    name: .appSystemNotification,
                    object: nil,
                    userInfo: [
                        "message": "System woke from sleep (IOKit) - restarting FTP monitoring",
                        "type": "info"
                    ]
                )

                // Restart all active sync configurations with delay for network stack
                print("⏰ Scheduling restart in 5 seconds to allow network stack to stabilize...")
                DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                    print("⏰⏰⏰ EXECUTING RESTART NOW (from IOKit notification) ⏰⏰⏰")
                    print("⏰ Thread: \(Thread.current), isMain: \(Thread.isMainThread)")
                    print("⏰ Calling restartActiveConfigurations()")

                    guard let manager = globalSyncManager else {
                        print("❌ ERROR: globalSyncManager became NIL before restart!")
                        return
                    }

                    manager.restartActiveConfigurations()
                    print("⏰ IOKit wake: restartActiveConfigurations() completed")
                }
            }

        default:
            print("🔔 IOKit: Unknown power message: 0x\(String(messageType, radix: 16))")
        }
    }

    /// Health check timer as failsafe to detect wake from sleep
    /// This runs every 5 seconds and detects if system time jumped forward (indicating sleep)
    private func setupHealthCheckTimer() {
        print("⏲️ Setting up health check timer (failsafe wake detection)")

        lastActiveTime = Date()

        healthCheckTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }

            let now = Date()
            let timeSinceLastCheck = now.timeIntervalSince(self.lastActiveTime)

            // Debug: Log every check to verify timer is running
            if timeSinceLastCheck > 10.0 {
                print("⏲️ Health check: \(String(format: "%.1f", timeSinceLastCheck))s since last check")
            }

            // If more than 15 seconds elapsed since last check (but timer is 5s), system likely slept
            // Reduced from 30s to 15s to be more aggressive in detecting sleep/wake
            if timeSinceLastCheck > 15.0 {
                print("⏰⏰⏰ FAILSAFE WAKE DETECTION ⏰⏰⏰")
                print("⏰ Time jumped \(String(format: "%.0f", timeSinceLastCheck))s - system likely woke from sleep")
                print("⏰ Last check: \(self.lastActiveTime)")
                print("⏰ Current time: \(now)")
                print("⏰ This is the FAILSAFE - NSWorkspace.didWakeNotification may have failed")

                // CRITICAL: Verify we have a sync manager
                guard globalSyncManager != nil else {
                    print("❌ FAILSAFE ERROR: globalSyncManager is NIL!")
                    return
                }

                // Log to notification feed
                NotificationCenter.default.post(
                    name: .appSystemNotification,
                    object: nil,
                    userInfo: [
                        "message": "System wake detected (failsafe) - waiting 5s for network, then restarting FTP monitoring",
                        "type": "warning"
                    ]
                )

                // Restart active configurations after network delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                    print("⏰ Triggering restart from failsafe wake detection (after 5s delay)")
                    print("⏰ Thread: \(Thread.current), isMain: \(Thread.isMainThread)")

                    guard let manager = globalSyncManager else {
                        print("❌ FAILSAFE ERROR: globalSyncManager became NIL before restart!")
                        return
                    }

                    manager.restartActiveConfigurations()
                    print("⏰ Failsafe restart completed")
                }
            }

            // Update last active time
            self.lastActiveTime = now
        }

        print("✅ Health check timer setup complete - checking every 5s")
    }

    /// Monitor network interface changes (Ethernet ↔ WiFi)
    private func setupNetworkMonitoring() {
        print("🌐 Setting up network change monitoring...")

        // Create reachability for internet in general
        var zeroAddress = sockaddr_in()
        zeroAddress.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        zeroAddress.sin_family = sa_family_t(AF_INET)

        guard let reachability = withUnsafePointer(to: &zeroAddress, {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                SCNetworkReachabilityCreateWithAddress(nil, $0)
            }
        }) else {
            print("❌ Failed to create network reachability")
            return
        }

        self.networkReachability = reachability

        // Get initial network status
        var flags = SCNetworkReachabilityFlags()
        SCNetworkReachabilityGetFlags(reachability, &flags)
        lastNetworkStatus = flags
        print("🌐 Initial network flags: \(flags)")

        // Setup callback for network changes
        var context = SCNetworkReachabilityContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let callback: SCNetworkReachabilityCallBack = { (_, flags, info) in
            guard let info = info else { return }
            let appDelegate = Unmanaged<AppDelegate>.fromOpaque(info).takeUnretainedValue()
            appDelegate.networkStatusChanged(flags: flags)
        }

        if SCNetworkReachabilitySetCallback(reachability, callback, &context) {
            if SCNetworkReachabilityScheduleWithRunLoop(reachability, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue) {
                print("✅ Network monitoring setup complete")
            } else {
                print("❌ Failed to schedule network monitoring")
            }
        } else {
            print("❌ Failed to set network callback")
        }
    }

    private func networkStatusChanged(flags: SCNetworkReachabilityFlags) {
        print("🌐🌐🌐 NETWORK STATUS CHANGED 🌐🌐🌐")
        print("🌐 Old flags: \(lastNetworkStatus?.rawValue ?? 0)")
        print("🌐 New flags: \(flags.rawValue)")

        // Check if this is a significant change (interface change, not just temporary dropout)
        let wasReachable = lastNetworkStatus?.contains(.reachable) ?? false
        let isReachable = flags.contains(.reachable)

        print("🌐 Was reachable: \(wasReachable), Is reachable: \(isReachable)")
        print("🌐 Connection details changed: interface likely switched")

        // If we went from reachable to reachable but flags changed significantly,
        // this likely means we switched interfaces (e.g., Ethernet → WiFi)
        if wasReachable && isReachable && lastNetworkStatus?.rawValue != flags.rawValue {
            print("🌐 Network interface change detected (e.g., Ethernet ↔ WiFi)")

            // Log to notification feed
            NotificationCenter.default.post(
                name: .appSystemNotification,
                object: nil,
                userInfo: [
                    "message": "Network interface changed - restarting FTP connections in 3 seconds",
                    "type": "warning"
                ]
            )

            // Kill and restart FTP processes after brief delay for network to stabilize
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                print("🌐 Restarting FTP processes after network change")

                // Kill all rust_ftp processes
                let killTask = Process()
                killTask.launchPath = "/usr/bin/killall"
                killTask.arguments = ["-9", "rust_ftp"]
                try? killTask.run()
                killTask.waitUntilExit()

                // Restart active configurations
                globalSyncManager?.restartActiveConfigurations()
            }
        }

        lastNetworkStatus = flags
    }

    /// Auto-start configurations marked with runOnLaunch
    private func autoStartConfigurations() {
        print("🚀 Checking for configurations marked with runOnLaunch...")

        // Small delay to ensure sync manager is fully initialized
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            print("🚀 Loading configurations from Keychain for auto-start check...")

            // Load configurations from Keychain (with automatic JSON migration if needed)
            let configurations = ConfigurationStorage.shared.loadConfigurations()

            if configurations.isEmpty {
                print("ℹ️ No configurations found")
                return
            }

            // Filter configurations that should run on launch
            let autoStartConfigs = configurations.filter { $0.runOnLaunch }

            if autoStartConfigs.isEmpty {
                print("ℹ️ No configurations marked with runOnLaunch")
                return
            }

            print("🚀 Found \(autoStartConfigs.count) configuration(s) marked with runOnLaunch:")
            for config in autoStartConfigs {
                print("   - \(config.name) (ID: \(config.id))")
            }

            // Start each configuration
            guard let syncManager = globalSyncManager else {
                print("❌ ERROR: globalSyncManager is NIL - cannot auto-start configurations")
                return
            }

            for config in autoStartConfigs {
                print("🚀 Auto-starting configuration: \(config.name)")
                syncManager.startSync(config: config)
            }

            print("✅ Auto-start complete - started \(autoStartConfigs.count) configuration(s)")
        }
    }
}

@main
struct FTPDownloaderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @State private var colorScheme: ColorScheme? = nil
    @StateObject private var helpManager = HelpManager.shared
    @StateObject private var storeManager = StoreKitManager()
    @State private var isLogCollectionOpen = false
    @State private var showPurchaseView = false
    @State private var purchaseViewTriggeredByExpiration = false // Track if shown due to expiration vs menu
    @StateObject private var demoModeManager = DemoModeManager.shared

    init() {
        // CRITICAL: Start console output capture FIRST, before any print() statements
        // This ensures we capture ALL output from the very start of the app
        OutputCapture.shared.startCapturing()

        print("✅ FTPDownloaderApp initializing")
        print("ℹ️  Configurations marked with 'runOnLaunch' will start automatically")

        // CRITICAL: Create singleton FileSyncManager ONCE at app startup
        // This prevents the dictionary from being reset when ContentView recreates
        if globalSyncManager == nil {
            print("🔧 CREATING SINGLETON FileSyncManager instance")
            let ftpService = SimpleRustFTPService_FFI()
            globalSyncManager = FileSyncManager(ftpService: ftpService)
            print("✅ SINGLETON FileSyncManager created - this should only happen ONCE")
        }

        // Setup logging
        setupLogging()

        // Setup signal handlers (AppDelegate is now automatically set up by SwiftUI)
        setupSignalHandlers()

        print("✅ FTPDownloaderApp initialization complete")
    }
    
    var body: some Scene {
        // Set global store manager reference for menu bar access
        let _ = {
            globalStoreManager = storeManager
        }()

        // Main window (hidden by default - menu bar app)
        return WindowGroup("FTP Downloader", id: "main") {
            Group {
                // Show loading state while checking purchase status
                if BuildType.current.showPurchaseUI && storeManager.isCheckingPurchaseStatus {
                    VStack(spacing: 20) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Loading...")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                // When trial expires, show purchase view as the ONLY content (App Store builds only)
                else if BuildType.current.showPurchaseUI &&
                   storeManager.isTrialExpired && !storeManager.isPurchased {
                    PurchaseView(
                        storeManager: storeManager,
                        triggeredByExpiration: true
                    )
                    .frame(minWidth: 640, minHeight: 920)
                } else {
                    // Normal app content when trial is active or purchased
                    ContentView()
                        .environmentObject(storeManager)
                        .environmentObject(demoModeManager)
                        .sheet(isPresented: $showPurchaseView) {
                            PurchaseView(
                                storeManager: storeManager,
                                triggeredByExpiration: false
                            )
                        }
                        .sheet(isPresented: $helpManager.isHelpWindowOpen) {
                            HelpWindow()
                                .frame(minWidth: 900, minHeight: 700)
                                .frame(maxWidth: 1200, maxHeight: 900)
                        }
                        .sheet(isPresented: $isLogCollectionOpen) {
                            LogCollectionView()
                        }
                }
            }
            .environmentObject(storeManager)
            .environmentObject(demoModeManager)
            .preferredColorScheme(colorScheme)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 800, height: 600)
        .commands {
            // Remove "New Window" command - single window app
            CommandGroup(replacing: .newItem) { }

            // Remove toolbar and tab commands from View menu - not used in this app
            CommandGroup(replacing: .toolbar) { }

            CommandGroup(replacing: .appInfo) {
                Button("About FTP Downloader") {
                    showCustomAboutPanel()
                }

                Divider()

                // Show license status for App Store builds
                if BuildType.current.showPurchaseUI {
                    if storeManager.isPurchased {
                        Button("License Status: Licensed") {
                            showLicenseStatus()
                        }
                        .disabled(true) // Make it non-clickable, just informational
                    } else {
                        // Only show purchase option if not already purchased
                        Button("Purchase Full Version...") {
                            purchaseViewTriggeredByExpiration = false // Manually opened, should be dismissible
                            showPurchaseView = true
                        }
                        .keyboardShortcut("p", modifiers: [.command, .shift])
                    }
                }
            }
            
            CommandGroup(after: .sidebar) {
                Menu("Appearance") {
                    Button("System") {
                        colorScheme = nil
                    }
                    .keyboardShortcut("0", modifiers: [.command])

                    Button("Light") {
                        colorScheme = .light
                    }
                    .keyboardShortcut("1", modifiers: [.command])

                    Button("Dark") {
                        colorScheme = .dark
                    }
                    .keyboardShortcut("2", modifiers: [.command])
                }
            }

            CommandGroup(replacing: .help) {
                Button("FTP Downloader Help") {
                    helpManager.openHelp()
                }
                .keyboardShortcut("?", modifiers: [.command])

                Divider()

                Button("Contact Support - Send Log File") {
                    isLogCollectionOpen = true
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])
            }

            CommandGroup(after: .appInfo) {
                Button("Start Demo Mode") {
                    NotificationCenter.default.post(name: .startDemoMode, object: nil)
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])
            }
        }
    }
    
    private func setupLogging() {
        print("🚀 FTP Downloader Starting...")
        print("📱 App Version: \(getAppVersion())")
        print("🏗️  Build Date: \(getBuildDate())")
        print("🖥️  Platform: macOS")
        print("📁 Working Directory: \(FileManager.default.currentDirectoryPath)")
        print("👤 User: \(NSUserName())")
        print("🕐 Start Time: \(Date())")
        print("=====================================")
    }
    
    private func setupSignalHandlers() {
        // AppDelegate is now automatically set up by @NSApplicationDelegateAdaptor
        // Just handle SIGTERM/SIGINT for command line kills
        signal(SIGTERM) { _ in
            print("🛑 SIGTERM received - terminating all processes")
            globalSyncManager?.terminateAllProcesses()
            exit(0)
        }

        signal(SIGINT) { _ in
            print("🛑 SIGINT received - terminating all processes")
            globalSyncManager?.terminateAllProcesses()
            exit(0)
        }

        print("✅ Termination handlers setup")
    }
    
    private func getAppVersion() -> String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
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
    
    private func showCustomAboutPanel() {
        let alert = NSAlert()
        alert.messageText = "About FTP Downloader"
        alert.informativeText = """
        Version \(getAppVersion())

        Build \(getBuildDate())

        Professional FTP synchronization tool with high-performance backend

        © 2025 Ronin Group Inc.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func showLicenseStatus() {
        let alert = NSAlert()
        alert.messageText = "License Status"
        alert.informativeText = """
        This application is fully licensed.

        Thank you for your purchase!
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
