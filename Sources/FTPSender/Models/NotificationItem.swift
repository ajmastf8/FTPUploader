import Foundation
import SwiftUI

// MARK: - Notification Models
struct NotificationItem: Identifiable, Equatable, Codable {
    let id: UUID
    let configId: UUID
    let message: String
    let type: NotificationType
    let timestamp: Date
    let filename: String?
    let progress: Double?
    
    init(configId: UUID, message: String, type: NotificationType = .info, timestamp: Date = Date(), filename: String? = nil, progress: Double? = nil) {
        self.id = UUID()
        self.configId = configId
        self.message = message
        self.type = type
        self.timestamp = timestamp
        self.filename = filename
        self.progress = progress
    }
    
    enum NotificationType: String, CaseIterable, Codable {
        case info = "info"
        case success = "success"
        case warning = "warning"
        case error = "error"
        
        var icon: String {
            switch self {
            case .info: return "info.circle.fill"
            case .success: return "checkmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .error: return "xmark.circle.fill"
            }
        }
        
        var color: Color {
            switch self {
            case .info: return .blue
            case .success: return .green
            case .warning: return .orange
            case .error: return .red
            }
        }
    }
}
