import SwiftUI
import WebKit

struct HelpView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()

        // Enable searching
        webView.configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        // Load the help content
        loadHelpContent(in: webView)

        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        // No updates needed
    }

    private func loadHelpContent(in webView: WKWebView) {
        if let helpPath = Bundle.main.path(forResource: "FTPDownloaderHelp", ofType: "html", inDirectory: "Help") {
            let helpURL = URL(fileURLWithPath: helpPath)
            webView.loadFileURL(helpURL, allowingReadAccessTo: helpURL.deletingLastPathComponent())
        } else {
            // Fallback to embedded HTML if bundle resource not found
            let htmlContent = generateFallbackHTML()
            webView.loadHTMLString(htmlContent, baseURL: nil)
        }
    }

    private func generateFallbackHTML() -> String {
        return """
        <!DOCTYPE html>
        <html>
        <head>
            <title>FTP Downloader Help</title>
            <style>
                body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; padding: 20px; line-height: 1.6; }
                .header { text-align: center; margin-bottom: 30px; }
                .section { margin-bottom: 30px; }
                h1 { color: #007AFF; }
                h2 { color: #007AFF; border-bottom: 2px solid #007AFF; padding-bottom: 5px; }
            </style>
        </head>
        <body>
            <div class="header">
                <h1>🚀 FTP Downloader Help</h1>
                <p>High-performance automated FTP file downloading</p>
            </div>

            <div class="section">
                <h2>Quick Start</h2>
                <ol>
                    <li>Click "New Configuration" to create your first FTP setup</li>
                    <li>Enter your FTP server details and test the connection</li>
                    <li>Configure local download directory and remote paths</li>
                    <li>Choose appropriate aggressiveness level for your server</li>
                    <li>Click "Start" to begin monitoring and downloading</li>
                </ol>
            </div>

            <div class="section">
                <h2>Aggressiveness Levels</h2>
                <ul>
                    <li><strong>Conservative (3):</strong> Gentle on servers, most reliable</li>
                    <li><strong>Moderate (10):</strong> Balanced performance (recommended)</li>
                    <li><strong>Aggressive (20):</strong> High speed for robust servers</li>
                    <li><strong>Extreme (50):</strong> Very high speed for enterprise servers</li>
                    <li><strong>Maximum (100):</strong> Maximum speed for high-capacity servers</li>
                    <li><strong>Ultra (150):</strong> Ultra-high speed for enterprise infrastructure</li>
                    <li><strong>Extreme Max (200):</strong> Maximum theoretical performance</li>
                </ul>
            </div>

            <div class="section">
                <h2>Key Features</h2>
                <ul>
                    <li><strong>File Stabilization:</strong> Waits for files to finish uploading before downloading</li>
                    <li><strong>Concurrent Processing:</strong> Multiple files downloaded simultaneously</li>
                    <li><strong>Real-time Monitoring:</strong> Live performance tracking and logs</li>
                    <li><strong>Auto-tuning:</strong> Automatically adjusts performance based on server response</li>
                    <li><strong>Multiple Configurations:</strong> Manage multiple FTP servers simultaneously</li>
                </ul>
            </div>

            <div class="section">
                <h2>Troubleshooting</h2>
                <ul>
                    <li><strong>Connection Failed:</strong> Check server address, credentials, and network</li>
                    <li><strong>Slow Performance:</strong> Try lower aggressiveness level</li>
                    <li><strong>Files Not Downloading:</strong> Verify directory paths and permissions</li>
                    <li><strong>Authentication Error:</strong> Confirm username and password</li>
                </ul>
            </div>

            <div class="section">
                <h2>Support</h2>
                <p>Application Version: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.1")<br>
                \(getExpirationInfo())<br>
                Contact support for assistance or newer versions.</p>
            </div>
        </body>
        </html>
        """
    }

    private func getExpirationInfo() -> String {
        if BuildType.current.useTimeExpiration {
            if let buildTimestampString = Bundle.main.infoDictionary?["BuildTimestamp"] as? String,
               let buildDate = ISO8601DateFormatter().date(from: buildTimestampString),
               let expirationDate = Calendar.current.date(byAdding: .day, value: 30, to: buildDate) {
                let formatter = DateFormatter()
                formatter.dateStyle = .long
                formatter.timeStyle = .none
                return "Expires: \(formatter.string(from: expirationDate))"
            }
        }
        return "No expiration"
    }
}

struct HelpWindow: View {
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header with search
            HStack {
                Text("FTP Downloader Help")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Spacer()

                // Search field
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)

                    TextField("Search help...", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 300)
                        .onSubmit {
                            performSearch()
                        }
                }

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            // Help content
            HelpView()
                .frame(minWidth: 800, minHeight: 600)
        }
    }

    private func performSearch() {
        // This would integrate with the WebView's search functionality
        // For now, it's a placeholder for future enhancement
        print("Searching for: \(searchText)")
    }
}

// Helper for opening help window
class HelpManager: ObservableObject {
    static let shared = HelpManager()
    @Published var isHelpWindowOpen = false

    private init() {}

    func openHelp() {
        isHelpWindowOpen = true
    }

    // Alternative method using NSHelpManager for native macOS help
    func openNativeHelp() {
        if let helpBook = Bundle.main.object(forInfoDictionaryKey: "CFBundleHelpBookName") as? String {
            NSHelpManager.shared.openHelpAnchor("", inBook: helpBook)
        } else {
            // Fallback to opening help window
            openHelp()
        }
    }
}