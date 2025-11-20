// Add these functions to LogCollectionView.swift after the collectLogs() function (around line 193)

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

    let alert = NSAlert()
    alert.messageText = "Copied to Clipboard"
    alert.informativeText = "The diagnostic log (\(fullContent.count) characters) has been copied to your clipboard.\n\nYou can now paste it into an email, Slack message, or any text editor."
    alert.alertStyle = .informational
    alert.addButton(withTitle: "OK")
    alert.runModal()
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
    return "FTP Downloader Support Request - \(appVersion) - \(Date().formatted(date: .abbreviated, time: .shortened))"
}

private func createEmailBody() -> String {
    var body = ""

    if !userName.isEmpty { body += "Name: \(userName)\n" }
    if !userEmail.isEmpty { body += "Email: \(userEmail)\n" }
    if !userPhone.isEmpty { body += "Phone: \(userPhone)\n" }
    if !userName.isEmpty || !userEmail.isEmpty || !userPhone.isEmpty {
        body += "\n"
    }

    if !issueDescription.isEmpty {
        body += "Issue Description:\n\(issueDescription)\n\n"
    }

    body += "Full diagnostic information is attached as a text file.\n\n"
    body += "System: macOS \(ProcessInfo.processInfo.operatingSystemVersionString)\n"
    body += "App Version: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")"

    return body
}

// REPLACE the existing sendEmail() function (around line 195) with this:
private func sendEmail() {
    let savePanel = NSSavePanel()
    savePanel.nameFieldStringValue = logService.generateLogFileName()
    savePanel.allowedContentTypes = [.plainText]
    savePanel.canCreateDirectories = true
    savePanel.message = "Save diagnostic log file to attach to email"
    savePanel.prompt = "Save for Email"

    savePanel.begin { response in
        if response == .OK, let url = savePanel.url {
            let fullContent = createFullLogContent()
            if logService.saveLogToFile(fullContent, atURL: url) {
                let subject = createEmailSubject()
                let body = createEmailBody()
                showPreEmailInstructions(fileURL: url, subject: subject, body: body)
            } else {
                showErrorAlert()
            }
        }
    }
}

// REPLACE saveLogFileInternal() function (around line 242) with this:
@discardableResult
private func saveLogFileInternal(atURL url: URL) -> URL? {
    let content = createFullLogContent()
    if logService.saveLogToFile(content, atURL: url) {
        return url
    }
    return nil
}

// REPLACE saveLogFile() function (around line 287) with this:
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

// REPLACE showSaveAlert() function (around line 322) with this:
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
