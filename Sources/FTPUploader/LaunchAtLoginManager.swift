import Foundation
import ServiceManagement
import SwiftUI

/// Manages "Launch at Login" functionality using SMAppService (macOS 13+)
/// This allows the app to automatically start when the user logs in
@MainActor
class LaunchAtLoginManager: ObservableObject {
    static let shared = LaunchAtLoginManager()

    @Published private(set) var isEnabled: Bool = false
    @Published private(set) var status: SMAppService.Status = .notRegistered

    private let service: SMAppService

    private init() {
        // Use the main app bundle identifier for login item
        self.service = SMAppService.mainApp
        updateStatus()
    }

    /// Check and update the current launch at login status
    func updateStatus() {
        status = service.status
        isEnabled = (status == .enabled)

        print("🚀 Launch at Login status: \(statusString)")
    }

    /// Enable launch at login
    func enable() throws {
        print("🚀 Enabling Launch at Login...")

        try service.register()
        updateStatus()
        print("✅ Launch at Login enabled successfully")
    }

    /// Disable launch at login
    func disable() throws {
        print("🚀 Disabling Launch at Login...")

        try service.unregister()
        updateStatus()
        print("✅ Launch at Login disabled successfully")
    }

    /// Toggle launch at login status
    func toggle() {
        do {
            if isEnabled {
                try disable()
            } else {
                try enable()
            }
        } catch {
            print("❌ Failed to toggle Launch at Login: \(error)")
        }
    }

    /// Human-readable status string
    private var statusString: String {
        switch status {
        case .notRegistered:
            return "Not Registered"
        case .enabled:
            return "Enabled"
        case .requiresApproval:
            return "Requires Approval (check System Settings > Login Items)"
        case .notFound:
            return "Not Found"
        @unknown default:
            return "Unknown"
        }
    }
}
