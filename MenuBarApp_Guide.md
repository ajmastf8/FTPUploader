# FTP Downloader: Menu Bar App Guide

## Overview

FTP Downloader is a **menu bar application** that provides continuous, unattended FTP file monitoring and synchronization. It runs persistently in your macOS menu bar (status bar), providing at-a-glance status updates and requiring minimal screen space.

## How It Works

### Architecture

The application uses a **hybrid Swift/Rust architecture** designed for reliability and performance:

**Swift Frontend (macOS App)**
- Menu bar interface with status icons
- Configuration management via macOS Keychain
- Real-time status monitoring and notifications
- SwiftUI-based settings and configuration windows

**Rust Backend (FTP Engine)**
- High-performance concurrent FTP operations
- Intelligent file stabilization monitoring
- Parallel downloads with connection pooling
- SQLite database for file hash tracking

**Communication**
- Swift app spawns Rust processes for FTP operations
- JSON-based inter-process communication (IPC)
- Real-time status updates via monitored JSON files
- Process lifecycle management for reliability

### Key Components

**Menu Bar Interface** ([MenuBarContentView.swift](Sources/FTPDownloader/MenuBarContentView.swift))
- Compact popover showing all active configurations
- Color-coded status indicators (green/orange/red)
- Per-configuration start/stop controls
- Quick access to local download folders
- Session statistics (files downloaded)

**Status Icons** ([FTPDownloaderApp.swift](Sources/FTPDownloader/FTPDownloaderApp.swift:206-281))
- **Orange**: Idle - configurations loaded but not syncing
- **Green**: Active - at least one configuration syncing
- **Red**: Error/Warning - connection issues detected

**Background Operation** ([FTPDownloaderApp.swift](Sources/FTPDownloader/FTPDownloaderApp.swift:32-89))
- Runs as an "accessory" app (no dock icon)
- Persists through screen locks and screensaver
- Automatic sleep/wake handling with process management
- Network interface change detection and recovery

**Configuration Storage** ([ConfigurationStorage.swift](Sources/FTPDownloader/ConfigurationStorage.swift))
- Primary storage: macOS Keychain (secure, encrypted)
- Automatic migration from legacy JSON files
- Cache mechanism to minimize keychain prompts
- Export/import for backup and sharing

**File Hash Database** ([RustFTP/src/db.rs](RustFTP/src/db.rs))
- SQLite database for tracking downloaded files
- Per-file hash storage (XXH3 algorithm)
- Prevents re-downloading unchanged files
- Automatic cleanup of stale entries

## How to Use

### Initial Setup

1. **Launch the App**
   - After installation, FTP Downloader appears in your menu bar
   - Look for the download icon (arrow down circle)
   - On first launch, the main window opens automatically

2. **Create a Configuration**
   - Click the menu bar icon → "Show Main Window"
   - Click "New Configuration" button
   - Enter FTP server details:
     - **Name**: Friendly name for this configuration
     - **Host**: FTP server address (e.g., ftp.example.com)
     - **Port**: Usually 21 (or 22 for SFTP)
     - **Username/Password**: FTP credentials (stored in Keychain)
     - **Remote Directory**: Path on FTP server to monitor
     - **Local Directory**: Where to download files on your Mac

3. **Configure Options**
   - **Scan Interval**: How often to check for new files (seconds)
   - **Run on Launch**: Auto-start this configuration when app launches
   - **Stabilization Time**: Wait time to ensure files finish uploading (seconds)
   - **Delete After Download**: Remove files from FTP server after successful download

### Daily Operation

**Starting Sync**
- Click menu bar icon to open popover
- Click green play button next to configuration name
- Status indicator turns green when connected
- Files downloaded counter increments as files are processed

**Stopping Sync**
- Click menu bar icon to open popover
- Click red stop button next to configuration name
- Rust process terminates cleanly
- Status indicator returns to orange (idle)

**Monitoring Status**
- **Menu Bar Icon Color**: Indicates overall system state
- **Configuration Row**: Shows per-config status and stats
- **Files Downloaded**: Session counter (resets when config stops)
- **Local Folder Link**: Click folder icon to open in Finder

**Accessing Main Window**
- Right-click menu bar icon → "Show Main Window"
- Or left-click → "Show Main Window" button at bottom
- Main window shows detailed logs and configuration editor

### System Behavior

**Screen Lock / Screensaver**
- App continues running in background
- FTP processes remain active
- Background activity token prevents termination

**Sleep / Wake**
- On sleep: Cleanly stops all Rust processes
- On wake: Waits 5 seconds for network stack
- Auto-restarts configurations that were active before sleep

**Network Changes**
- Detects interface changes (Ethernet ↔ WiFi)
- Automatically restarts FTP connections after 3 second delay
- Notification posted to feed for visibility

**Launch at Login**
- Toggle in menu bar popover settings section
- Uses macOS Login Items API (requires user approval)
- Warning shown if system approval needed

## Benefits

### Minimal Footprint
- No dock icon - menu bar only
- Compact popover interface (280px wide)
- Main window hidden by default after setup
- Low memory usage with efficient Rust backend

### Always Accessible
- Click menu bar icon anytime for instant status
- No need to switch apps or search for windows
- Quick start/stop controls without full UI
- Right-click for context menu shortcuts

### Persistent Operation
- Survives screen lock and screensaver
- Automatic sleep/wake handling
- Network resilience with auto-reconnect
- Process management prevents zombie processes

### Visual Status Feedback
- Color-coded icons for instant status awareness
- Per-configuration connection state indicators
- Session statistics for visibility into activity
- Error badges for immediate problem detection

### Secure Configuration Management
- All credentials stored in macOS Keychain
- Encrypted storage with system-level security
- No plain-text passwords in files
- Cache mechanism minimizes keychain prompts

### Intelligent File Handling
- File stabilization prevents incomplete downloads
- Hash-based change detection (only download if changed)
- SQLite database for fast lookups
- Automatic cleanup of deleted server files

### High-Performance Downloads
- Rust backend optimized for speed
- Parallel downloads with connection pooling
- Efficient memory usage
- XXH3 hashing algorithm (very fast)

## Advanced Features

### Demo Mode
- Command menu: "Start Demo Mode"
- Creates sample FTP configuration automatically
- Useful for testing and demonstrations
- Auto-cleanup when disabled

### Auto-Start on Launch
- Per-configuration "Run on Launch" setting
- Automatic sync starts 2 seconds after app launch
- Ideal for unattended operation
- Multiple configs can auto-start

### Export/Import Configurations
- Export all configurations to JSON file
- Import configurations from backup
- Useful for migrating to new Mac
- Share configurations between users (note: excludes passwords)

### Real-Time Logs
- Main window shows live log feed
- Colored notifications by severity (info/warning/error)
- Filterable by configuration
- Helps troubleshoot connection issues

## System Requirements

- macOS 12.0 (Monterey) or later
- Network access to FTP server
- Write permissions to local download directory
- Keychain access for credential storage

## File Locations

**Configuration Storage**
- Keychain: `com.roningroupinc.FTPDownloader.configs`

**File Hash Database**
- `~/Library/Application Support/FTPDownloader/file_tracking.db`

**Log Files**
- `~/Library/Containers/com.roningroupinc.FTPDownloader/Data/tmp/FTPDownloader_Console_*.log`

**Temporary Files**
- `~/Library/Containers/com.roningroupinc.FTPDownloader/Data/tmp/rust_ftp_*/*.json`

## Troubleshooting

**Menu Bar Icon Not Visible**
- Check System Settings → Control Center → Menu Bar Only
- Drag icon position in menu bar if needed

**Configuration Not Auto-Starting**
- Verify "Run on Launch" is checked in config
- Check logs in main window for errors
- Ensure FTP credentials are valid

**Files Not Downloading**
- Check menu bar popover for error indicators
- Open main window to view detailed logs
- Verify FTP server connectivity
- Check local folder write permissions

**Wake from Sleep Not Working**
- App uses both IOKit and NSWorkspace notifications
- Failsafe timer detects wake if notifications fail
- 5 second delay allows network to stabilize

**Network Change Not Detected**
- Check Console.app for network monitoring logs
- Verify network is truly reachable after switch
- Manual restart: Stop and start configuration

## Technical Details

### File Stabilization Algorithm
1. **Discovery Phase**: List all files on FTP server
2. **Monitoring Phase**: Track file sizes over time
3. **Stability Check**: Wait until size unchanged for configured duration
4. **Download Phase**: Parallel download of stable files
5. **Verification**: XXH3 hash comparison with database

### Hash Tracking
- Uses XXH3 algorithm (fastest non-cryptographic hash)
- Tracks: filename, file size, mod time, hash
- Prevents re-downloading unchanged files
- Automatic migration from legacy text-based tracking

### Process Management
- One Rust process per active configuration
- Clean termination on sleep/stop
- Zombie process prevention
- Automatic restart on wake

### IPC Communication
- Swift writes: `config.json` (FTP parameters)
- Rust writes: `status.json` (connection state)
- Rust writes: `result.json` (operation outcomes)
- Swift monitors JSON files for changes (FileSystemWatcher)

## Development

See [CLAUDE.md](CLAUDE.md) for developer documentation, build instructions, and architecture details.
