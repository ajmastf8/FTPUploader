import SwiftUI

// MARK: - Notification Feed View
struct NotificationFeed: View {
    let configId: UUID
    @ObservedObject var syncManager: FileSyncManager
    @State private var notifications: [NotificationItem] = []
    @State private var isExpanded = true // Start expanded by default
    @State private var selectedFilter: NotificationItem.NotificationType? = .success // Start with Success selected
    @State private var stateUpdateObserver: NSObjectProtocol?
    @State private var downloadObserver: NSObjectProtocol?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("Live Notifications")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                // Current operation status
                HStack {
                    Image(systemName: "circle.fill")
                        .foregroundColor(syncManager.isConfigSyncing(configId) ? .green : .gray)
                        .font(.system(size: 6))
                    Text(syncManager.getConfigCurrentOperation(configId))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                

                
                // Filter controls
                HStack(spacing: 4) {
                    // Individual type filters (custom order, excluding progress)
                    ForEach([NotificationItem.NotificationType.success, .info, .warning, .error], id: \.self) { type in
                        Button(action: {
                            selectedFilter = selectedFilter == type ? nil : type
                        }) {
                            HStack(spacing: 2) {
                                Image(systemName: type.icon)
                                    .font(.system(size: 8))
                                Text(type.rawValue.capitalized)
                                    .font(.caption2)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(selectedFilter == type ? type.color : Color(NSColor.controlBackgroundColor))
                                )
                                .foregroundColor(selectedFilter == type ? .white : type.color)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    // All notifications filter (at the end)
                    Button(action: {
                        selectedFilter = nil
                    }) {
                        Text("All")
                            .font(.caption2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(selectedFilter == nil ? Color.accentColor : Color(NSColor.controlBackgroundColor))
                            )
                            .foregroundColor(selectedFilter == nil ? .white : .secondary)
                    }
                    .buttonStyle(.plain)
                }
                
                // Expand/Collapse button
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isExpanded.toggle()
                    }
                }) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)
            
            // Notification Feed
            if isExpanded {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        if filteredNotifications.isEmpty {
                            // Empty state
                            HStack {
                                Spacer()
                                VStack(spacing: 8) {
                                    Image(systemName: selectedFilter != nil ? "line.3.horizontal.decrease.circle" : "bell.slash")
                                        .font(.system(size: 24))
                                        .foregroundColor(.secondary)
                                    Text(selectedFilter != nil ? "No \(selectedFilter?.rawValue.capitalized ?? "") notifications" : "No notifications yet")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 20)
                        } else {
                            ForEach(filteredNotifications) { notification in
                                NotificationRow(notification: notification)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                }
                .frame(height: 200)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(NSColor.controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
                .padding(.horizontal, 16)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .onAppear {
            print("📱 NotificationFeed: Subscribing to notifications for config \(configId)")
            subscribeToNotifications()
        }
        .onDisappear {
            print("📱 NotificationFeed: Unsubscribing from notifications")
            unsubscribeFromNotifications()
        }
    }
    
    // MARK: - Computed Properties
    private var filteredNotifications: [NotificationItem] {
        guard let filter = selectedFilter else {
            return notifications
        }
        return notifications.filter { $0.type == filter }
    }
    
    // MARK: - Notification Subscription
    private func subscribeToNotifications() {
        let configIdCapture = configId

        // Subscribe to state updates (connected, scanning, waiting, error)
        stateUpdateObserver = NotificationCenter.default.addObserver(
            forName: .rustStateUpdate,
            object: nil,
            queue: .main
        ) { notification in
            guard let notifConfigId = notification.userInfo?["configId"] as? UUID,
                  notifConfigId == configIdCapture,
                  let message = notification.userInfo?["message"] as? String else {
                return
            }

            // Add notification - timestamp is when we receive it
            let notificationItem = NotificationItem(
                configId: configIdCapture,
                message: message,
                type: Self.determineNotificationType(from: message),
                timestamp: Date(),
                filename: nil,
                progress: nil
            )

            // Add to beginning (newest first)
            notifications.insert(notificationItem, at: 0)

            // Keep only last 100 notifications to prevent memory growth
            if notifications.count > 100 {
                notifications.removeLast()
            }
        }

        // Subscribe to download completions (for file download notifications)
        downloadObserver = NotificationCenter.default.addObserver(
            forName: .rustDownloadSpeedUpdate,
            object: nil,
            queue: .main
        ) { notification in
            print("📱 NotificationFeed: Received .rustDownloadSpeedUpdate notification")
            print("📱 NotificationFeed: userInfo = \(notification.userInfo ?? [:])")

            guard let notifConfigId = notification.userInfo?["configId"] as? UUID,
                  notifConfigId == configIdCapture,
                  let filename = notification.userInfo?["filename"] as? String else {
                print("📱 NotificationFeed: Failed guard - configId or filename missing")
                print("📱 NotificationFeed: notifConfigId = \(notification.userInfo?["configId"] as? UUID)")
                print("📱 NotificationFeed: expectedConfigId = \(configIdCapture)")
                print("📱 NotificationFeed: filename = \(notification.userInfo?["filename"] as? String)")
                return
            }

            print("📱 NotificationFeed: Adding download notification for filename: \(filename)")

            // Add notification for file download
            let notificationItem = NotificationItem(
                configId: configIdCapture,
                message: "✅ \(filename)",
                type: .success,
                timestamp: Date(),
                filename: filename,
                progress: nil
            )

            // Add to beginning (newest first)
            notifications.insert(notificationItem, at: 0)

            // Keep only last 100 notifications to prevent memory growth
            if notifications.count > 100 {
                notifications.removeLast()
            }

            print("📱 NotificationFeed: Total notifications now: \(notifications.count)")
        }

        print("📱 NotificationFeed: Subscribed to notifications")
    }

    private func unsubscribeFromNotifications() {
        if let observer = stateUpdateObserver {
            NotificationCenter.default.removeObserver(observer)
            stateUpdateObserver = nil
        }
        if let observer = downloadObserver {
            NotificationCenter.default.removeObserver(observer)
            downloadObserver = nil
        }
        print("📱 NotificationFeed: Unsubscribed from notifications")
    }

    private static func determineNotificationType(from message: String) -> NotificationItem.NotificationType {
        let lowercased = message.lowercased()

        if lowercased.contains("✅") || lowercased.contains("success") || lowercased.contains("completed") {
            return .success
        } else if lowercased.contains("❌") || lowercased.contains("error") || lowercased.contains("failed") {
            return .error
        } else if lowercased.contains("⚠️") || lowercased.contains("warning") {
            return .warning
        } else {
            return .info
        }
    }
}

// MARK: - Notification Row View
struct NotificationRow: View {
    let notification: NotificationItem
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Main notification row
            HStack(alignment: .top, spacing: 8) {
                // Icon
                Image(systemName: notification.type.icon)
                    .foregroundColor(notification.type.color)
                    .font(.system(size: 12))
                
                // Content
                VStack(alignment: .leading, spacing: 2) {
                    // Message
                    Text(notification.message)
                        .font(.system(.caption2, design: notification.type == .info ? .default : .monospaced))
                        .foregroundColor(.primary)
                        .lineLimit(isExpanded ? nil : (notification.type == .info ? 3 : 2))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // Progress bars removed - notifications are for completed actions only
                    // Filename display removed - filename is now included in the main message
                }
                
                Spacer()
                
                // Timestamp
                Text(formatTimestamp(notification.timestamp))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                // Expand button for long messages
                if notification.message.count > 100 {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isExpanded.toggle()
                        }
                    }) {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            // Divider between notifications
            if notification.id != NotificationItem(configId: UUID(), message: "", type: .info, timestamp: Date(), filename: nil, progress: nil).id {
                Divider()
                    .opacity(0.3)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(notification.type.color.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(notification.type.color.opacity(0.2), lineWidth: 1)
        )
    }
    
    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

#Preview {
    NotificationFeed(
        configId: UUID(),
        syncManager: FileSyncManager(ftpService: SimpleRustFTPService_FFI())
    )
    .padding()
}

