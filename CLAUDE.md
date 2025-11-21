# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Development Commands

### Build Commands
- **Release Build**: `./build.sh` - Builds complete app bundle with embedded Rust binary
- **Swift Only**: `swift build --configuration release` - Swift package build only
- **Rust Only**: `cd RustFTP && cargo build --release` - Rust FTP engine build only
- **Launch App**: `./launch_app.sh` - Launch built app bundle from terminal

### Testing Commands
- **Rust Tests**: `cd RustFTP && cargo test`
- **Manual Testing**: Use the GUI app to create FTP configurations and test connections

### Distribution Commands
- **Build for Distribution**: `./build_and_notarize_spm.sh` - Creates signed and notarized release
- **Update Build Info**: `./update_build_info.sh` - Updates version numbers for distribution

## Architecture Overview

This is a hybrid Swift/Rust macOS application for automated FTP file uploading with intelligent stabilization monitoring.

### Core Components

**Swift Frontend (SwiftUI App)**
- `FTPUploaderApp.swift`: Main SwiftUI app entry point
- `ContentView.swift`: Primary UI with configuration management and file monitoring
- `FTPConfigurationView.swift`: Configuration creation and editing interface
- `FTPConfig.swift`: Data model for FTP server configurations
- `FileSyncManager.swift`: Orchestrates file synchronization and status tracking
- `FTPService.swift`: Swift-based FTP operations using FileProvider framework
- `SimpleRustFTPService.swift`: Bridge to communicate with Rust FTP engine
- `NotificationFeed.swift` + `LiveLogsView.swift`: Real-time logging and notifications

**Rust Backend (High-Performance FTP Engine)**
- Location: `RustFTP/src/main.rs`
- Purpose: Concurrent FTP operations with advanced file stabilization
- Communication: JSON-based IPC via files (`status.json`, `result.json`)
- Features: Parallel uploads, file size monitoring, connection pooling

### Data Flow
1. User creates FTP configuration in Swift UI
2. Swift app writes config to JSON and spawns Rust process
3. Rust engine performs FTP operations, writes status updates to JSON
4. Swift app monitors JSON files and updates UI in real-time
5. File processing: discovery → stabilization monitoring → parallel upload → move to FTPU-Sent

### Key Features
- **File Stabilization**: Monitors local file sizes until stable before uploading
- **Concurrent Processing**: Parallel FTP operations for maximum throughput
- **Smart Retry Logic**: Exponential backoff for failed operations
- **Real-time Monitoring**: Live status updates and progress tracking
- **Secure Credential Storage**: macOS Keychain integration
- **Move on Success**: Successfully uploaded files are moved to FTPU-Sent directory

### Build Process
The build system creates a complete `.app` bundle containing:
1. Swift executable (main app)
2. Embedded Rust binary (`rust_ftp`) for FTP operations
3. App icon and Info.plist
4. Proper macOS app structure for distribution

### Configuration Files
- `Package.swift`: Swift Package Manager configuration with FileProvider dependency
- `RustFTP/Cargo.toml`: Rust dependencies for FTP, async, and JSON processing
- `ExportOptions.plist`: Code signing and distribution settings
- `Sources/FTPUploader/Info.plist`: macOS app bundle metadata

### Development Workflow
1. Use `./build.sh` for complete builds during development
2. Use `swift build` for faster Swift-only iterations
3. Use `cd RustFTP && cargo build --release` for Rust-only changes
4. Test configurations through the GUI interface
5. Monitor logs via the built-in live log viewer

### Architecture Considerations
- **Hybrid Design**: Swift handles UI/UX, Rust handles performance-critical FTP operations
- **Process Isolation**: Rust runs as separate process for stability and resource management
- **JSON Communication**: Simple, debuggable IPC between Swift and Rust components
- **macOS Integration**: Native Swift UI with proper macOS app lifecycle and security
