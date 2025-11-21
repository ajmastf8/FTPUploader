import Foundation
import StoreKit
import SwiftUI

/// Manages in-app purchases and trial period for FTP Sender
@MainActor
class StoreKitManager: NSObject, ObservableObject {

    // MARK: - Published Properties

    @Published var isPurchased: Bool = false
    @Published var isLoading: Bool = false
    @Published var isCheckingPurchaseStatus: Bool = true // Prevents UI flash on launch
    @Published var purchaseError: String?
    @Published var availableProducts: [Product] = []

    // MARK: - Constants

    // Product ID from App Store Connect
    private let productID = "FTPDownv1"

    // Trial duration in days
    // TESTING: Set DEBUG_FORCE_TRIAL_EXPIRED in UserDefaults to force expiration
    // Or build with --test-expired flag to test expired trial
    private var trialDurationDays: Int {
        #if TEST_EXPIRED
        return -1  // Force expired for testing purchase screen
        #else
        if UserDefaults.standard.bool(forKey: "DEBUG_FORCE_TRIAL_EXPIRED") {
            return -1  // Force expired for testing
        }
        return 3  // Normal 3-day trial
        #endif
    }

    // UserDefaults keys
    private let firstLaunchDateKey = "firstLaunchDate"
    private let purchasedKey = "isPurchased"

    // Receipt validator for trial and purchase tracking
    private let receiptValidator = ReceiptValidator()

    // MARK: - Update Listener

    private var updateListenerTask: Task<Void, Error>? = nil

    // MARK: - Initialization

    override init() {
        super.init()

        // Check cached purchase status FIRST from UserDefaults for instant loading
        // (No keychain access = no password prompt)
        if let cachedStatus = UserDefaults.standard.object(forKey: purchasedKey) as? Bool {
            isPurchased = cachedStatus
            print("🚀 Using cached purchase status from UserDefaults: \(cachedStatus ? "PURCHASED" : "NOT PURCHASED")")

            // If cached as purchased, mark checking as complete immediately
            // We'll still verify in background but won't block UI
            if cachedStatus {
                isCheckingPurchaseStatus = false
            }
        }

        // Start listening for transaction updates
        updateListenerTask = listenForTransactions()

        Task {
            // Load trial start date from receipt (this caches it for offline use)
            _ = await receiptValidator.loadTrialStartDate()

            // Check for existing purchases from receipt
            await updatePurchaseStatus()

            // Load products
            await loadProducts()

            // Mark purchase status check as complete
            await MainActor.run {
                isCheckingPurchaseStatus = false
            }
        }
    }

    deinit {
        updateListenerTask?.cancel()
    }

    // MARK: - Trial Management

    /// Returns the first launch date from the receipt (App Store originalPurchaseDate)
    /// Falls back to UserDefaults if receipt unavailable (offline/dev builds)
    var firstLaunchDate: Date {
        // Try to get from receipt validator (most reliable - Apple-signed)
        if let receiptDate = receiptValidator.getTrialStartDate() {
            return receiptDate
        }

        // Fallback: Use current date (should only happen in dev builds without receipt)
        // This will be replaced once receipt loads
        print("⚠️ No receipt date available yet, using current date as fallback")
        return Date()
    }

    /// Checks if app is running in TestFlight
    var isTestFlight: Bool {
        return receiptValidator.isTestFlightEnvironment()
    }

    /// Returns true if the trial period is active
    var isTrialActive: Bool {
        guard !isPurchased else { return false }

        let now = Date()
        let daysSinceLaunch = Calendar.current.dateComponents([.day], from: firstLaunchDate, to: now).day ?? 0

        // Calculate the exact expiration date (trial duration days from first launch)
        let expirationDate = Calendar.current.date(byAdding: .day, value: trialDurationDays, to: firstLaunchDate) ?? firstLaunchDate

        // Trial is active if we haven't reached the expiration date yet
        let isActive = now < expirationDate

        print("Trial Status Check - First Launch: \(firstLaunchDate), Current: \(now), Expiration: \(expirationDate), Days Since: \(daysSinceLaunch), Duration: \(trialDurationDays), Active: \(isActive)")

        return isActive
    }

    /// Returns the number of trial days remaining
    var trialDaysRemaining: Int {
        guard !isPurchased else { return 0 }

        let daysSinceLaunch = Calendar.current.dateComponents([.day], from: firstLaunchDate, to: Date()).day ?? 0
        return max(0, trialDurationDays - daysSinceLaunch)
    }

    /// Returns true if the user has access to the app (either trial or purchased)
    var hasAccess: Bool {
        // TestFlight builds get unlimited access
        if isTestFlight {
            return true
        }
        return isPurchased || isTrialActive
    }

    /// Returns true if trial has expired and not purchased
    var isTrialExpired: Bool {
        // TestFlight builds never expire
        if isTestFlight {
            return false
        }
        return !isPurchased && !isTrialActive
    }

    // MARK: - Product Loading

    /// Loads available products from the App Store
    func loadProducts() async {
        isLoading = true
        purchaseError = nil

        do {
            // Request products from the App Store
            let products = try await Product.products(for: [productID])

            await MainActor.run {
                self.availableProducts = products
                self.isLoading = false

                // If no products were returned, show an error
                if products.isEmpty {
                    self.purchaseError = "Product not available. Please check your internet connection and try again."
                }
            }
        } catch {
            await MainActor.run {
                self.purchaseError = "Failed to load products. Please check your internet connection and try again."
                self.isLoading = false
                print("Product loading error: \(error)")
            }
        }
    }

    // MARK: - Purchase Management

    /// Purchases the full version of the app
    func purchase() async {
        guard let product = availableProducts.first else {
            purchaseError = "Product not available. Please check your internet connection and try again."
            // Try reloading products
            await loadProducts()
            return
        }

        isLoading = true
        purchaseError = nil

        do {
            let result = try await product.purchase()

            switch result {
            case .success(let verification):
                // Verify the transaction
                let transaction = try checkVerified(verification)

                // Update purchase status
                await updatePurchaseStatus()

                // Finish the transaction
                await transaction.finish()

                await MainActor.run {
                    self.isLoading = false
                }

            case .userCancelled:
                await MainActor.run {
                    self.isLoading = false
                }

            case .pending:
                await MainActor.run {
                    self.purchaseError = "Purchase is pending approval"
                    self.isLoading = false
                }

            @unknown default:
                await MainActor.run {
                    self.purchaseError = "Unknown purchase result"
                    self.isLoading = false
                }
            }
        } catch {
            await MainActor.run {
                self.purchaseError = "Purchase failed: \(error.localizedDescription)"
                self.isLoading = false
            }
        }
    }

    /// Restores previous purchases
    func restorePurchases() async {
        isLoading = true
        purchaseError = nil

        do {
            try await AppStore.sync()
            await updatePurchaseStatus()

            await MainActor.run {
                self.isLoading = false

                if !self.isPurchased {
                    self.purchaseError = "No previous purchases found"
                }
            }
        } catch {
            await MainActor.run {
                self.purchaseError = "Failed to restore purchases: \(error.localizedDescription)"
                self.isLoading = false
            }
        }
    }

    // MARK: - Transaction Verification

    /// Verifies a transaction is legitimate
    func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreError.failedVerification
        case .verified(let safe):
            return safe
        }
    }

    // MARK: - Purchase Status

    /// Updates the purchase status by checking current entitlements
    func updatePurchaseStatus() async {
        // TESTING: Allow bypassing purchase check for testing trial expiration
        if UserDefaults.standard.bool(forKey: "DEBUG_BYPASS_PURCHASE_CHECK") {
            await MainActor.run {
                self.isPurchased = false
                UserDefaults.standard.set(false, forKey: purchasedKey)
            }
            print("🧪 DEBUG: Bypassing purchase check - isPurchased forced to false")
            return
        }

        var hasPurchase = false

        // Check for active transactions
        for await result in Transaction.currentEntitlements {
            do {
                let transaction = try checkVerified(result)

                // Check if this transaction is for our product
                if transaction.productID == productID {
                    hasPurchase = true
                    break
                }
            } catch {
                print("Transaction verification failed: \(error)")
            }
        }

        await MainActor.run {
            self.isPurchased = hasPurchase

            // Cache purchase status in UserDefaults for fast loading on next launch
            // This avoids the StoreKit delay, especially important for purchased users
            UserDefaults.standard.set(hasPurchase, forKey: purchasedKey)
        }
    }

    // MARK: - Transaction Listener

    /// Listens for transaction updates from the App Store
    func listenForTransactions() -> Task<Void, Error> {
        return Task.detached { @MainActor [weak self] in
            guard let self = self else { return }

            for await result in Transaction.updates {
                do {
                    let transaction = try self.checkVerified(result)

                    await self.updatePurchaseStatus()

                    await transaction.finish()
                } catch {
                    print("Transaction update failed: \(error)")
                }
            }
        }
    }

    // MARK: - Formatted Price

    /// Returns the formatted price for the product
    var formattedPrice: String {
        // Show actual price if available, otherwise show placeholder for development
        if let product = availableProducts.first {
            return product.displayPrice
        } else {
            // In development/testing mode, show a default price
            return "$24.99"
        }
    }
}

// MARK: - Store Errors

enum StoreError: Error {
    case failedVerification
}
