import Foundation
import StoreKit

class ReceiptValidator {

    // MARK: - Configuration

    /// Cached app transaction to avoid repeated async fetches
    private var cachedAppTransaction: AppTransaction?

    /// Cached purchase status
    private var cachedPurchaseStatus: (purchased: Bool, productID: String)?

    /// Product ID for the in-app purchase
    private let purchaseProductID = "FTPDownv1"

    // MARK: - Trial Management

    /// Retrieves the trial start date from App Store receipt
    /// - Returns: The original purchase date (first install) if available, nil otherwise
    /// - Note: This date persists even after app deletion/reinstall
    func getTrialStartDate() -> Date? {
        // Try to get from cached transaction first
        if let cached = cachedAppTransaction {
            return cached.originalPurchaseDate
        }

        // Not yet loaded, caller should use async version
        return nil
    }

    /// Checks if app is running in TestFlight environment
    /// - Returns: True if TestFlight, false if App Store or unknown
    func isTestFlightEnvironment() -> Bool {
        if let transaction = cachedAppTransaction {
            let isTestFlight = transaction.environment == .sandbox
            print("🔍 Environment: \(isTestFlight ? "SANDBOX (TestFlight)" : "PRODUCTION (App Store)")")
            return isTestFlight
        }

        print("⚠️ No cached transaction, cannot determine environment yet")
        return false
    }

    /// Loads and caches the app transaction (async version)
    /// - Returns: The trial start date from the receipt
    func loadTrialStartDate() async -> Date? {
        do {
            // Verify and load the app transaction
            let verificationResult = try await AppTransaction.shared
            let transaction = try checkVerified(verificationResult)

            // Cache it for future use
            self.cachedAppTransaction = transaction

            // Log environment
            let env = transaction.environment == .sandbox ? "SANDBOX (TestFlight)" : "PRODUCTION (App Store)"
            print("🔍 Transaction environment: \(env)")

            let startDate = transaction.originalPurchaseDate
            print("✅ Loaded trial start date from receipt: \(startDate)")
            return startDate

        } catch {
            print("❌ Failed to load app transaction: \(error)")

            // Fallback for TestFlight or development builds
            // Use UserDefaults as backup
            if let fallbackDate = UserDefaults.standard.object(forKey: "fallback_trial_start") as? Date {
                print("⚠️ Using fallback trial date: \(fallbackDate)")
                return fallbackDate
            }

            // First launch without receipt - save current date as fallback
            let now = Date()
            UserDefaults.standard.set(now, forKey: "fallback_trial_start")
            print("📝 Saved fallback trial date: \(now)")
            return now
        }
    }

    /// Saves the trial start date (no-op for receipt-based system)
    /// - Parameter date: Ignored - receipt automatically tracks original purchase date
    /// - Returns: Always returns true
    func saveTrialStartDate(_ date: Date) -> Bool {
        print("ℹ️ saveTrialStartDate called but ignored (receipt handles this)")
        return true
    }

    /// Checks if trial data exists
    /// - Returns: True if we can load an app transaction or have fallback data
    func hasTrialData() -> Bool {
        // Check if we have cached transaction
        if cachedAppTransaction != nil {
            return true
        }

        // Check fallback
        return UserDefaults.standard.object(forKey: "fallback_trial_start") != nil
    }

    /// Deletes trial data (for testing only)
    /// - Returns: True if deleted successfully
    /// - Warning: This only clears the fallback, can't delete receipt data
    func deleteTrialData() -> Bool {
        UserDefaults.standard.removeObject(forKey: "fallback_trial_start")
        cachedAppTransaction = nil
        print("✅ Cleared trial fallback data")
        return true
    }

    // MARK: - License Management

    /// Validates purchase status from App Store receipt
    /// - Returns: Tuple with purchase status and product ID if purchased, nil otherwise
    func getLicenseStatus() async -> (purchased: Bool, productID: String)? {
        // Return cached status if available
        if let cached = cachedPurchaseStatus {
            print("✅ Using cached purchase status")
            return cached
        }

        do {
            // Check current entitlements (active purchases)
            for await result in Transaction.currentEntitlements {
                let transaction = try checkVerified(result)

                if transaction.productID == purchaseProductID {
                    let status = (purchased: true, productID: transaction.productID)
                    cachedPurchaseStatus = status
                    print("✅ Found valid purchase: \(transaction.productID)")
                    return status
                }
            }

            print("ℹ️ No purchase found in entitlements")
            return nil

        } catch {
            print("❌ Failed to check entitlements: \(error)")
            return nil
        }
    }

    /// Synchronous version of getLicenseStatus (returns cached value only)
    /// - Returns: Cached purchase status, or nil if not yet loaded
    func getLicenseStatus() -> (purchased: Bool, productID: String)? {
        if let cached = cachedPurchaseStatus {
            return cached
        }

        print("ℹ️ Purchase status not cached, use async version")
        return nil
    }

    /// Saves license status (no-op for receipt-based system)
    /// - Parameters:
    ///   - purchased: Ignored
    ///   - productID: Ignored
    /// - Returns: Always true
    func saveLicenseStatus(purchased: Bool, productID: String) -> Bool {
        print("ℹ️ saveLicenseStatus called but ignored (receipt handles this)")
        return true
    }

    /// Checks if license data exists
    /// - Returns: True if we have a cached purchase
    func hasLicenseData() -> Bool {
        return cachedPurchaseStatus != nil
    }

    /// Deletes license data (for testing only)
    /// - Returns: Always true
    /// - Warning: Can't actually delete receipt data, only clears cache
    func deleteLicenseData() -> Bool {
        cachedPurchaseStatus = nil
        print("✅ Cleared license cache")
        return true
    }

    // MARK: - Helper Methods

    /// Verifies a transaction signature
    /// - Parameter result: The verification result from StoreKit
    /// - Returns: The verified transaction
    /// - Throws: If verification fails
    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw ReceiptError.invalidSignature
        case .verified(let transaction):
            return transaction
        }
    }
}

// MARK: - Errors

enum ReceiptError: Error {
    case invalidSignature
    case notFound
}
