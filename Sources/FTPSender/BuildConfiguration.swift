import Foundation

/// Build configuration for different distribution types
enum BuildType: String {
    case development = "DEV"
    case notarized = "NOTARIZED"
    case appStore = "APPSTORE"
    case testExpired = "TEST_EXPIRED"  // Dev build with expired trial for testing

    /// The current build type, determined at compile time
    static var current: BuildType {
        #if TEST_EXPIRED
        return .testExpired
        #elseif NOTARIZED_BUILD
        return .notarized
        #elseif APPSTORE_BUILD
        return .appStore
        #else
        return .development
        #endif
    }

    /// Whether to show purchase/trial UI
    var showPurchaseUI: Bool {
        switch self {
        case .development:
            return false  // No purchase UI in dev builds
        case .testExpired:
            return true   // Test purchase screen with expired trial
        case .notarized:
            return false // Notarized builds use time-based expiration only
        case .appStore:
            return true  // App Store builds use trial + purchase
        }
    }

    /// Whether to use time-based expiration
    var useTimeExpiration: Bool {
        switch self {
        case .development:
            return false // No expiration in dev
        case .testExpired:
            return false // No time-based expiration (using StoreKit trial)
        case .notarized:
            return true  // 15-day expiration
        case .appStore:
            return false // No hard expiration (trial handled by StoreKit)
        }
    }

    /// Expiration days for time-based expiration
    var expirationDays: Int? {
        switch self {
        case .development:
            return nil
        case .testExpired:
            return nil
        case .notarized:
            return 15
        case .appStore:
            return nil
        }
    }
}
