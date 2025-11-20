//
//  main.swift
//  RustFTPService
//
//  XPC Service entry point for Rust FTP operations
//

import Foundation

// XPC Service main entry point
// This creates an NSXPCListener and waits for connections from the main app
class ServiceDelegate: NSObject, NSXPCListenerDelegate {

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        // Configure the connection
        newConnection.exportedInterface = NSXPCInterface(with: FTPServiceProtocol.self)

        // Create the service object that implements the protocol
        let exportedObject = RustFTPServiceImplementation()
        newConnection.exportedObject = exportedObject

        // Set up interface for callbacks from service to main app
        newConnection.remoteObjectInterface = NSXPCInterface(with: FTPServiceNotificationProtocol.self)

        // Store the connection reference in the service implementation
        exportedObject.clientConnection = newConnection

        // Handle connection invalidation
        newConnection.invalidationHandler = {
            print("XPC connection invalidated")
        }

        newConnection.interruptionHandler = {
            print("XPC connection interrupted")
        }

        // Start the connection
        newConnection.resume()

        print("✅ XPC Service: Accepted new connection from main app")
        return true
    }
}

// Start the XPC service listener
let delegate = ServiceDelegate()
let listener = NSXPCListener.service()
listener.delegate = delegate

print("🚀 RustFTPService XPC Service starting...")
listener.resume()

// Keep the service running
RunLoop.main.run()
