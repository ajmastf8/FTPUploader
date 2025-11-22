import SwiftUI
import AppKit

struct LogCollectionView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var logService = LogCollectionService.shared

    @State private var selectedCollectionType: LogCollectionType = .currentSession
    @State private var includeSystemInfo = true
    @State private var collectedLogs = ""
    @State private var isCollecting = false
    @State private var showingPreview = false
    @State private var issueDescription = ""
    @State private var userName = ""
    @State private var userEmail = ""
    @State private var userPhone = ""
    @State private var showCopiedAlert = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                VStack(spacing: 8) {
                    Text("Send Support Log")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text("Collect and send diagnostic information to support")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                // Two-column layout for form fields
                HStack(alignment: .top, spacing: 20) {
                    // Left Column
                    VStack(alignment: .leading, spacing: 16) {
                        // Contact Information
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Contact Information")
                                .font(.headline)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Name: *")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                TextField("Your name (required)", text: $userName)
                                    .textFieldStyle(.roundedBorder)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Email: *")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                TextField("your.email@example.com (required)", text: $userEmail)
                                    .textFieldStyle(.roundedBorder)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Phone (optional):")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                TextField("Phone number", text: $userPhone)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }

                        // Log Collection Options
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Log Collection Settings")
                                .font(.headline)

                            VStack(alignment: .leading, spacing: 8) {
                                Text("Time Period / Error Count:")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)

                                Picker("Collection Type", selection: $selectedCollectionType) {
                                    ForEach(LogCollectionType.allCases, id: \.self) { type in
                                        Text(type.displayName).tag(type)
                                    }
                                }
                                .pickerStyle(.menu)
                            }

                            Toggle("Include System Information", isOn: $includeSystemInfo)
                                .help("Includes macOS version, hardware info, and memory specs")
                        }
                    }
                    .frame(maxWidth: .infinity)

                    // Right Column
                    VStack(alignment: .leading, spacing: 16) {
                        // Issue Description
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Describe the issue you're experiencing: *")
                                .font(.headline)

                            TextEditor(text: $issueDescription)
                                .frame(height: 200)
                                .overlay(
                                    Group {
                                        if issueDescription.isEmpty {
                                            Text("Please describe the issue you're experiencing (required)")
                                                .foregroundColor(.secondary)
                                                .padding(.leading, 5)
                                                .padding(.top, 8)
                                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                                .allowsHitTesting(false)
                                        }
                                    }
                                )
                                .background(Color(NSColor.textBackgroundColor))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                                )
                        }
                    }
                    .frame(maxWidth: .infinity)
                }

                // Preview Section
                if showingPreview && !collectedLogs.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Log Preview")
                                .font(.headline)

                            Spacer()

                            Text("\(collectedLogs.components(separatedBy: .newlines).count) lines")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        ScrollView {
                            Text(collectedLogs)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(Color(NSColor.labelColor))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                                .background(Color(NSColor.textBackgroundColor))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                                )
                        }
                        .frame(height: 250)
                    }
                }

                Spacer()

            // Action Buttons
            HStack(spacing: 12) {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                if !showingPreview {
                    Button("Collect Logs") {
                        collectLogs()
                    }
                    .disabled(isCollecting)
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button("Copy to Clipboard") {
                        copyToClipboard()
                    }
                    .disabled(collectedLogs.isEmpty)

                    Button("Save to File") {
                        saveLogFile()
                    }

                    Button("Send Email") {
                        sendEmail()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(collectedLogs.isEmpty || isContactInfoMissing())
                    .help(isContactInfoMissing() ? "Please fill in Name, Email, and Issue Description to send" : "Send diagnostic logs via email")
                }

                if isCollecting {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }

                // Show helper text if Send Email is disabled
                if showingPreview && isContactInfoMissing() {
                    Text("⚠️ Please fill in all required fields (*) above to enable Send Email button")
                        .font(.caption)
                        .foregroundColor(.orange)
                        .padding(.top, 8)
                }
            }
            .padding(24)
        }
        .frame(width: 950, height: 800)
        .alert("Copied to Clipboard", isPresented: $showCopiedAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("The diagnostic log has been copied to your clipboard.\n\nYou can now paste it into an email, Slack message, or any text editor.")
        }
    }

    private func collectLogs() {
        isCollecting = true

        // Capture values before entering detached task
        let collectionType = selectedCollectionType
        let includeSystemInfo = includeSystemInfo
        let logService = logService

        // Run on background thread to avoid blocking UI
        Task.detached(priority: .userInitiated) {
            let logs = logService.collectLogs(type: collectionType, includeSystemInfo: includeSystemInfo)

            await MainActor.run { [self] in
                self.collectedLogs = logs
                self.showingPreview = true
                self.isCollecting = false
            }
        }
    }

    private func copyToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        var fullContent = ""
        fullContent += "CONTACT INFORMATION\n"
        fullContent += String(repeating: "-", count: 40) + "\n"
        if !userName.isEmpty { fullContent += "Name: \(userName)\n" }
        if !userEmail.isEmpty { fullContent += "Email: \(userEmail)\n" }
        if !userPhone.isEmpty { fullContent += "Phone: \(userPhone)\n" }
        fullContent += "\n"
        if !issueDescription.isEmpty {
            fullContent += "ISSUE DESCRIPTION\n"
            fullContent += String(repeating: "-", count: 40) + "\n"
            fullContent += "\(issueDescription)\n\n"
        }
        fullContent += collectedLogs

        pasteboard.setString(fullContent, forType: .string)

        // Show SwiftUI alert instead of NSAlert
        showCopiedAlert = true
    }

    private func createFullLogContent() -> String {
        var content = ""

        content += "\n"
        content += String(repeating: "=", count: 80) + "\n"
        content += "                FTP DOWNLOADER SUPPORT REQUEST\n"
        content += String(repeating: "=", count: 80) + "\n\n"

        content += "SUPPORT REQUEST DETAILS\n"
        content += String(repeating: "-", count: 40) + "\n"
        content += "Generated: \(Date().formatted(date: .complete, time: .complete))\n\n"

        content += "CONTACT INFORMATION\n"
        content += String(repeating: "-", count: 40) + "\n"
        if !userName.isEmpty { content += "Name:  \(userName)\n" }
        if !userEmail.isEmpty { content += "Email: \(userEmail)\n" }
        if !userPhone.isEmpty { content += "Phone: \(userPhone)\n" }
        content += "\n"

        content += "ISSUE DESCRIPTION\n"
        content += String(repeating: "-", count: 40) + "\n"
        if !issueDescription.isEmpty {
            content += "\(issueDescription)\n\n"
        } else {
            content += "No description provided.\n\n"
        }

        content += collectedLogs

        return content
    }

    private func createEmailSubject() -> String {
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        return "FTP Sender Support Request - \(appVersion) - \(Date().formatted(date: .abbreviated, time: .shortened))"
    }

    private func createEmailBody(logFileName: String) -> String {
        var body = ""

        // Contact information
        if !userName.isEmpty { body += "Name: \(userName)\n" }
        if !userEmail.isEmpty { body += "Email: \(userEmail)\n" }
        if !userPhone.isEmpty { body += "Phone: \(userPhone)\n" }
        if !userName.isEmpty || !userEmail.isEmpty || !userPhone.isEmpty {
            body += "\n"
        }

        // Issue description
        if !issueDescription.isEmpty {
            body += "Issue Description:\n\(issueDescription)\n\n"
        }

        // System information
        body += "System: macOS \(ProcessInfo.processInfo.operatingSystemVersionString)\n"
        body += "App Version: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.1")\n\n"

        // Instructions about the log file
        body += "========================================\n"
        body += "DIAGNOSTIC LOG FILE\n"
        body += "========================================\n\n"
        body += "A diagnostic log file has been saved:\n"
        body += "\(logFileName)\n\n"
        body += "Please attach this file to this email before sending.\n\n"
        body += "To attach:\n"
        body += "1. Look for 'Attach' or paperclip icon in your email app\n"
        body += "2. Browse to where you saved the file\n"
        body += "3. Select: \(logFileName)\n"
        body += "4. Send email\n"

        return body
    }

    private func sendEmail() {
        // Ask user where to save the log file (required for sandboxed apps)
        let savePanel = NSSavePanel()
        let fileName = logService.generateLogFileName()
        savePanel.nameFieldStringValue = fileName
        savePanel.allowedContentTypes = [.plainText]
        savePanel.canCreateDirectories = true
        savePanel.message = "Save diagnostic log file to attach to email"
        savePanel.prompt = "Save"

        // Start in Downloads folder
        if let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            savePanel.directoryURL = downloadsURL
        }

        savePanel.begin { response in
            guard response == .OK, let fileURL = savePanel.url else {
                return
            }

            let fullContent = self.createFullLogContent()
            guard self.logService.saveLogToFile(fullContent, atURL: fileURL) else {
                self.showErrorAlert()
                return
            }

            // Create email with instructions (logs are in saved file)
            let subject = self.createEmailSubject()
            let body = self.createEmailBody(logFileName: fileURL.lastPathComponent)

            // URL encode
            guard let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let encodedBody = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
                self.showErrorAlert()
                return
            }

            // Open email client
            let mailtoURL = "mailto:support@roningroupinc.com?subject=\(encodedSubject)&body=\(encodedBody)"
            if let url = URL(string: mailtoURL) {
                NSWorkspace.shared.open(url)

                // Show alert with file location
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    let alert = NSAlert()
                    alert.messageText = "Email Opened - Attach Log File"
                    alert.informativeText = "Your email app has opened with a pre-filled support request.\n\nDiagnostic log saved to:\n\(fileURL.path)\n\nPlease attach this file to your email before sending."
                    alert.alertStyle = .informational
                    alert.addButton(withTitle: "OK")
                    alert.addButton(withTitle: "Show in Finder")

                    let response = alert.runModal()
                    if response == .alertSecondButtonReturn {
                        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
                    }
                }
            } else {
                self.showErrorAlert()
            }
        }
    }

    private func isContactInfoMissing() -> Bool {
        let nameEmpty = userName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let emailEmpty = userEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let descriptionEmpty = issueDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return nameEmpty || emailEmpty || descriptionEmpty
    }

    @discardableResult
    private func saveLogFileInternal(atURL url: URL) -> URL? {
        let content = createFullLogContent()
        if logService.saveLogToFile(content, atURL: url) {
            return url
        }
        return nil
    }

    private func saveLogFile() {
        let savePanel = NSSavePanel()
        savePanel.nameFieldStringValue = logService.generateLogFileName()
        savePanel.allowedContentTypes = [.plainText]
        savePanel.canCreateDirectories = true
        savePanel.message = "Choose where to save the support log file"
        savePanel.prompt = "Save Log"

        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                let fullContent = createFullLogContent()
                if logService.saveLogToFile(fullContent, atURL: url) {
                    showSaveSuccessAlert(fileURL: url)
                } else {
                    showErrorAlert()
                }
            }
        }
    }

    private func showPreEmailInstructions(fileURL: URL, subject: String, body: String) {
        let alert = NSAlert()
        alert.messageText = "Ready to Send Support Email"
        alert.informativeText = "Your diagnostic log has been saved to:\n\n\(fileURL.path)\n\nWhen you click OK, your email app will open with a pre-filled support request. Please attach the log file above to the email before sending to support@roningroupinc.com"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK - Open Email")
        alert.addButton(withTitle: "Show Log File in Finder")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            // User clicked OK - Open Email, so open the email app
            if let emailURL = logService.createEmailURL(subject: subject, body: body) {
                NSWorkspace.shared.open(emailURL)
            }
            dismiss()
        } else if response == .alertSecondButtonReturn {
            // User clicked Show File in Finder
            NSWorkspace.shared.selectFile(fileURL.path, inFileViewerRootedAtPath: fileURL.deletingLastPathComponent().path)
            // Show the dialog again after showing file
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.showPreEmailInstructions(fileURL: fileURL, subject: subject, body: body)
            }
        }
        // If user clicked Cancel, do nothing - they stay in the log collection dialog
    }

    private func showSaveSuccessAlert(fileURL: URL) {
        let alert = NSAlert()
        alert.messageText = "Log File Saved"
        alert.informativeText = "Support log has been saved to:\n\(fileURL.path)\n\nYou can attach this file to an email to support@roningroupinc.com"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Show in Finder")
        alert.addButton(withTitle: "Copy Path")

        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            NSWorkspace.shared.selectFile(fileURL.path, inFileViewerRootedAtPath: fileURL.deletingLastPathComponent().path)
        } else if response == .alertThirdButtonReturn {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(fileURL.path, forType: .string)
        }
    }

    private func showErrorAlert() {
        let alert = NSAlert()
        alert.messageText = "Error Saving Log File"
        alert.informativeText = "Unable to save the diagnostic log file. Please try again or contact support directly at support@roningroupinc.com"
        alert.alertStyle = .critical
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

#Preview {
    LogCollectionView()
}