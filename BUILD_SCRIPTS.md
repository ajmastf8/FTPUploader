# FTP Downloader - Build Scripts

## Quick Commands
- **Build & Run**: `./build_and_run.sh` (production build + launch)
- **Dev Build**: `./dev_run.sh` (debug build + launch)
- **Quick Launch**: `./launch.sh` (launch existing build)
- **View Logs**: `./view_logs.sh` (real-time monitoring)
- **Build Only**: `swift build -c release` (Swift Package Manager)
- **Rust Build**: `cd RustFTP && cargo build --release`

## Build Scripts Overview

### `./build_and_run.sh` - Production Build
- Cleans previous builds
- Builds in release mode for optimal performance
- Launches app in background (GUI works normally)
- Logs written to `ftp_downloader.log`

### `./dev_run.sh` - Development Build
- Builds in debug mode (faster compilation)
- Launches app in background
- Logs written to `ftp_downloader_debug.log`
- Perfect for rapid development iterations

### `./launch.sh` - Quick Launch
- No building (assumes app exists)
- Fastest startup time
- Launches existing app in background
- Logs written to `ftp_downloader_launch.log`

### `./view_logs.sh` - Log Monitoring
```bash
./view_logs.sh          # Release logs
./view_logs.sh debug    # Debug logs  
./view_logs.sh launch   # Launch logs
```

## Architecture & Build Process

### Hybrid Swift/Rust Build
- **Swift Frontend**: SwiftUI app with Swift Package Manager
- **Rust Backend**: FTP processing engine built with Cargo
- **Integration**: Rust binary embedded in Swift app bundle
- **Build Order**: Rust first, then Swift with embedded binary

### Build Outputs
- **App Bundle**: `build/FTPDownloader.app`
- **DMG**: `build/FTPDownloader.dmg` (for distribution)
- **ZIP**: `build/FTPDownloader.zip` (for notarization)

## Development Workflow

### 1. Initial Setup
```bash
# Make scripts executable
chmod +x *.sh

# Install dependencies
brew install fswatch  # For watch mode
```

### 2. Development Cycle
```bash
# Build and run for development
./dev_run.sh

# Make code changes...

# Quick rebuild and relaunch
./dev_run.sh

# Or just launch existing build
./launch.sh
```

### 3. Production Testing
```bash
# Build and run production version
./build_and_run.sh

# Monitor logs
./view_logs.sh
```

## Troubleshooting

### Common Issues
- **Script Permission**: `chmod +x *.sh`
- **Build Cache**: `swift package clean`
- **Rust Issues**: `cd RustFTP && cargo clean && cargo build --release`
- **GUI Input**: All scripts launch in background - terminal input works normally

### Build Errors
- Verify `Package.swift` exists in project root
- Check `Sources/FTPDownloader/` directory structure
- Ensure Xcode Command Line Tools installed
- Run `swift --version` to verify Swift installation

### Log Access
- Logs persist even after terminal closure
- Use `./view_logs.sh` anytime to monitor activity
- Log files located in project root directory

## Key Features

### Background Launch
- All scripts launch app in background using `nohup`
- GUI works normally without terminal input capture
- Terminal remains free for other commands
- App continues running independently

### Real-time Logging
- Comprehensive logging of all operations
- FTP connections, file operations, errors
- Performance metrics and status updates
- Easy debugging and monitoring

### Flexible Build Options
- Debug vs Release builds
- Watch mode for continuous development
- Standalone launch for testing
- Production-ready distribution builds

## Customization

Scripts can be modified for:
- Different build configurations
- Additional logging options
- Custom build flags
- Pre/post build hooks
- Environment-specific settings

All scripts designed to be simple and hackable for specific development needs.

