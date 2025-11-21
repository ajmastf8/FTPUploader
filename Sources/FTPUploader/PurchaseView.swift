import SwiftUI
import StoreKit

/// View displayed when trial expires or for showing purchase options
struct PurchaseView: View {
    @ObservedObject var storeManager: StoreKitManager
    var triggeredByExpiration: Bool = false // Track if opened due to expiration vs menu
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow

    private func quitApp() {
        // Always force quit - this ensures the app closes even if sheet was non-dismissible
        // Using exit(0) because NSApplication.shared.terminate(nil) gets blocked by sheets
        exit(0)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 24) {
                // Icon
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(.blue.gradient)
                    .padding(.top, 20)

            // Title
            VStack(spacing: 8) {
                Text("Trial Expired")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.orange)

                Text("Purchase to continue using FTP Uploader")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }

            // Features list
            VStack(alignment: .leading, spacing: 16) {
                FeatureRow(icon: "arrow.down.circle", title: "Automated Downloads", description: "Intelligent FTP file downloading")
                FeatureRow(icon: "gauge.with.dots.needle.67percent", title: "Smart Monitoring", description: "File stabilization detection")
                FeatureRow(icon: "arrow.triangle.branch", title: "Concurrent Processing", description: "Parallel downloads for speed")
                FeatureRow(icon: "network", title: "Connection Pooling", description: "Optimized FTP operations")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            // Pricing
            VStack(spacing: 12) {
                if storeManager.availableProducts.isEmpty && storeManager.isLoading {
                    ProgressView()
                        .scaleEffect(1.5)
                        .frame(height: 60)
                    Text("Loading pricing...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } else {
                    Text(storeManager.formattedPrice)
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .foregroundColor(.blue)

                    Text("One-time purchase")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 8)

            // Error message and retry button
            if let error = storeManager.purchaseError {
                VStack(spacing: 8) {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    if storeManager.availableProducts.isEmpty {
                        Button("Retry Loading Products") {
                            Task {
                                await storeManager.loadProducts()
                            }
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                        .foregroundColor(.blue)
                    }
                }
            }

            // Buttons
            VStack(spacing: 12) {
                Button(action: {
                    Task {
                        await storeManager.purchase()
                    }
                }) {
                    HStack {
                        if storeManager.isLoading {
                            ProgressView()
                                .scaleEffect(0.8)
                                .frame(width: 16, height: 16)
                        }
                        Text(storeManager.isLoading ? "Processing..." : "Purchase Now")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(storeManager.isLoading || storeManager.availableProducts.isEmpty)

                Button("Restore Purchase") {
                    Task {
                        await storeManager.restorePurchases()
                    }
                }
                .buttonStyle(.bordered)
                .disabled(storeManager.isLoading)

                // Quit button - allows user to exit the app
                Button("Quit App") {
                    quitApp()
                }
                .buttonStyle(.borderless)
                .foregroundColor(.secondary)
                .disabled(storeManager.isLoading)
            }
            .padding(.horizontal, 40)

                Spacer()
            }
            .frame(width: 640, height: 920)
            .padding(40)

            // Close button - only quits the app when trial expired
            Button(action: {
                // When trial expired, X button quits the app (same as Quit App button)
                quitApp()
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(16)
        }
    }
}

/// Single feature row in the purchase view
struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.blue)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
    }
}

// MARK: - Trial Status Banner

/// Compact banner showing trial status (for when trial is active)
struct TrialStatusBanner: View {
    @ObservedObject var storeManager: StoreKitManager
    @State private var showPurchaseView = false

    var body: some View {
        if !storeManager.isPurchased && storeManager.isTrialActive {
            HStack {
                Image(systemName: "clock.fill")
                    .foregroundColor(.orange)

                Text("Trial: \(storeManager.trialDaysRemaining) day\(storeManager.trialDaysRemaining == 1 ? "" : "s") remaining")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Spacer()

                Button("Unlock Full Version") {
                    showPurchaseView = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.orange.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .sheet(isPresented: $showPurchaseView) {
                PurchaseView(storeManager: storeManager)
            }
        }
    }
}

#Preview {
    PurchaseView(storeManager: StoreKitManager())
}
