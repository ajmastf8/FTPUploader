#!/usr/bin/env swift

import SwiftUI
import AppKit

// Minimal StoreKitManager mock for rendering
class MockStoreKitManager: ObservableObject {
    @Published var formattedPrice = "$24.99"
    @Published var isLoading = false
    @Published var purchaseError: String? = nil
    @Published var isPurchased = false
    @Published var isTrialActive = true
    @Published var trialDaysRemaining = 7

    func purchase() async {}
    func restorePurchases() async {}
}

// Feature row component
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

// Purchase view without dismiss button for screenshot
struct IAPScreenshotView: View {
    @ObservedObject var storeManager: MockStoreKitManager

    var body: some View {
        VStack(spacing: 24) {
            // Icon
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(.blue.gradient)
                .padding(.top, 20)

            // Title
            VStack(spacing: 8) {
                Text("Unlock FTP Downloader")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Your trial has ended")
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
                Text(storeManager.formattedPrice)
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundColor(.blue)

                Text("One-time purchase")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 8)

            // Buttons
            VStack(spacing: 12) {
                Button(action: {}) {
                    Text("Purchase Now")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button("Restore Purchase") {}
                    .buttonStyle(.bordered)
            }
            .padding(.horizontal, 40)

            Spacer()
        }
        .frame(width: 1024, height: 1024)
        .padding(60)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// Render view to image
func renderToImage() {
    let storeManager = MockStoreKitManager()
    let view = IAPScreenshotView(storeManager: storeManager)

    let hostingController = NSHostingController(rootView: view)
    hostingController.view.frame = CGRect(x: 0, y: 0, width: 1024, height: 1024)

    guard let bitmapRep = hostingController.view.bitmapImageRepForCachingDisplay(in: hostingController.view.bounds) else {
        print("Failed to create bitmap representation")
        return
    }

    hostingController.view.cacheDisplay(in: hostingController.view.bounds, to: bitmapRep)

    guard let imageData = bitmapRep.representation(using: .png, properties: [:]) else {
        print("Failed to create PNG data")
        return
    }

    let outputPath = "/Volumes/Photo/Working/Shop Media/FTPDownloader/IAP_Screen_1024x1024_native.png"

    do {
        try imageData.write(to: URL(fileURLWithPath: outputPath))
        print("✅ IAP screenshot saved to: \(outputPath)")
        print("📐 Dimensions: 1024x1024 pixels")
    } catch {
        print("❌ Failed to save image: \(error)")
    }
}

// Run
renderToImage()
