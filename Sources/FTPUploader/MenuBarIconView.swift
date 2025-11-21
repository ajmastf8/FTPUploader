import SwiftUI
import AppKit

/// Dynamic menu bar icon that changes color based on connection status
/// Orange when no configurations are syncing, green when at least one is active
struct MenuBarIconView: View {
    @ObservedObject var syncManager: FileSyncManager

    var body: some View {
        Image(nsImage: menuBarIcon)
    }

    private var hasActiveConnections: Bool {
        // Check if any configuration is currently syncing
        let isActive = syncManager.configIsSyncing.values.contains(true)
        let activeCount = syncManager.configIsSyncing.filter { $0.value }.count
        print("🎨 MenuBarIconView.hasActiveConnections: \(isActive) (\(activeCount) active configs)")
        print("🎨 Full configIsSyncing state: \(syncManager.configIsSyncing)")
        return isActive
    }

    private var menuBarIcon: NSImage {
        // Choose icon based on connection status
        let iconName = hasActiveConnections ? "app-icon-menubar-green" : "app-icon-menubar-orange"
        print("🔍 MenuBarIconView: Using icon '\(iconName)'")


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

            resizedIcon.isTemplate = false // Use the colored versions as-is
            return resizedIcon
        }

        // Fallback to SF Symbol if custom icons not found
        let fallback = NSImage(systemSymbolName: "arrow.up.circle.fill", accessibilityDescription: "FTP Uploader") ?? NSImage()
        fallback.size = NSSize(width: 18, height: 18)
        return fallback
    }
}
