//
//  FTPServiceProtocol.swift
//  FTPDownloader
//
//  XPC Protocol for FTP operations between main app and XPC Service
//

import Foundation

/// XPC Protocol for FTP Service communication
/// This protocol defines the interface between the main app and the XPC service
@objc protocol FTPServiceProtocol {

    /// Start FTP monitoring for a configuration
    /// - Parameters:
    ///   - configID: Unique identifier for the configuration
    ///   - host: FTP server hostname or IP
    ///   - port: FTP server port
    ///   - username: FTP username
    ///   - password: FTP password
    ///   - remotePath: Remote directory to monitor
    ///   - downloadPath: Local download destination
    ///   - pollingInterval: Interval between directory checks (seconds)
    ///   - stableWaitTime: Time to wait for file stability (seconds)
    ///   - reply: Completion handler with success/error
    func startMonitoring(
        configID: String,
        host: String,
        port: Int,
        username: String,
        password: String,
        remotePath: String,
        downloadPath: String,
        pollingInterval: Int,
        stableWaitTime: Int,
        respectFilePaths: Bool,
        withReply reply: @escaping (Bool, String?) -> Void
    )

    /// Stop FTP monitoring for a configuration
    /// - Parameters:
    ///   - configID: Configuration to stop
    ///   - reply: Completion handler
    func stopMonitoring(
        configID: String,
        withReply reply: @escaping (Bool) -> Void
    )

    /// Get current status for a configuration
    /// - Parameters:
    ///   - configID: Configuration to query
    ///   - reply: Completion handler with status JSON string
    func getStatus(
        configID: String,
        withReply reply: @escaping (String?) -> Void
    )

    /// Test FTP connection
    /// - Parameters:
    ///   - host: FTP server hostname or IP
    ///   - port: FTP server port
    ///   - username: FTP username
    ///   - password: FTP password
    ///   - reply: Completion handler with success/error message
    func testConnection(
        host: String,
        port: Int,
        username: String,
        password: String,
        withReply reply: @escaping (Bool, String?) -> Void
    )
}

/// Protocol for receiving notifications from XPC service back to main app
@objc protocol FTPServiceNotificationProtocol {

    /// Notification of status change
    /// - Parameters:
    ///   - configID: Configuration that changed
    ///   - statusJSON: JSON string with status details
    func statusUpdated(configID: String, statusJSON: String)

    /// Notification of new file discovered
    /// - Parameters:
    ///   - configID: Configuration
    ///   - filename: Name of discovered file
    func fileDiscovered(configID: String, filename: String)

    /// Notification of file download progress
    /// - Parameters:
    ///   - configID: Configuration
    ///   - filename: File being downloaded
    ///   - bytesDownloaded: Bytes transferred
    ///   - totalBytes: Total file size
    func downloadProgress(
        configID: String,
        filename: String,
        bytesDownloaded: Int64,
        totalBytes: Int64
    )

    /// Notification of file download completed
    /// - Parameters:
    ///   - configID: Configuration
    ///   - filename: Downloaded filename
    ///   - localPath: Local path where file was saved
    func downloadCompleted(
        configID: String,
        filename: String,
        localPath: String
    )

    /// Notification of error
    /// - Parameters:
    ///   - configID: Configuration
    ///   - error: Error message
    func errorOccurred(configID: String, error: String)
}
