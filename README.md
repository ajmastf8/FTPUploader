# FTP Downloader

A high-performance hybrid Swift/Rust macOS application for automated FTP file downloading with intelligent stabilization monitoring, concurrent processing, and real-time performance optimization.

## 🚀 Overview

FTP Downloader combines the elegant user experience of SwiftUI with the raw performance power of Rust to deliver enterprise-grade FTP automation. The app intelligently monitors FTP servers, stabilizes files before download, and processes multiple files concurrently for maximum throughput.

## ✨ Key Features

### 🎯 **Intelligent File Processing**
- **Smart File Stabilization**: Monitors file sizes until stable before downloading to prevent incomplete transfers
- **Concurrent Processing**: High-performance Rust engine handles parallel downloads with configurable connection pools
- **Real-time Performance Tracking**: Live monitoring of download speeds, connection times, and throughput metrics
- **Auto-tuning Aggressiveness**: Automatically adjusts connection strategies based on server performance

### ⚙️ **Advanced Configuration Management**
- **Multiple Server Profiles**: Save and manage unlimited FTP server configurations
- **Connection Testing**: Built-in connectivity verification before saving configurations
- **Flexible Download Modes**: Choose between "Delete After Download" or "Keep After Download"
- **Directory Structure Preservation**: Maintain original FTP directory hierarchy locally
- **Secure Credential Storage**: macOS Keychain integration for encrypted password storage

### 📊 **Performance & Monitoring**
- **7 Aggressiveness Levels**: From Conservative (3 connections) to Extreme Max (200 connections)
- **Real-time Statistics**: Live files/second tracking, connection times, and session reports
- **Comprehensive Logging**: Real-time activity feed with detailed operation logs
- **Progress Visualization**: Visual progress bars and status indicators for all operations
- **Background Processing**: Non-blocking UI with background file processing

### 🔄 **Smart Synchronization**
- **Configurable Sync Intervals**: From 0.1 seconds to 2 hours
- **Multi-directory Monitoring**: Watch multiple FTP directories simultaneously
- **Automatic Retry Logic**: Exponential backoff for failed operations
- **Session Persistence**: Resume operations after app restart
- **File State Management**: Track files through discovery → stabilization → download → cleanup

### 🎨 **Modern macOS Experience**
- **Native SwiftUI Interface**: Modern, responsive macOS design
- **Live Log Viewer**: Dedicated window for real-time operation monitoring
- **Tabbed Configuration Interface**: Easy switching between multiple server configurations
- **Notification Center Integration**: System notifications for important events
- **Dark Mode Support**: Full macOS appearance adaptation

## 🏗️ Technical Architecture

### **Hybrid Swift/Rust Design**
```
┌─────────────────┐    JSON IPC    ┌──────────────────┐
│   Swift Frontend │ ◄────────────► │   Rust Backend   │
│                 │                │                  │
│ • SwiftUI Interface             │ • High-Performance FTP │
│ • Configuration Management      │ • Concurrent Processing │
│ • Real-time Monitoring          │ • File Stabilization   │
│ • macOS Integration             │ • Connection Pooling    │
└─────────────────┘                └──────────────────┘
```

### **Core Components**

**Swift Frontend (SwiftUI App)**
- `FTPDownloaderApp.swift`: Main app entry point with lifecycle management
- `ContentView.swift`: Primary interface with configuration tabs and monitoring
- `FTPConfigurationView.swift`: Configuration creation and editing interface
- `FileSyncManager.swift`: Orchestrates synchronization and communicates with Rust engine
- `NotificationFeed.swift` + `LiveLogsView.swift`: Real-time logging and status updates

**Rust Backend (High-Performance Engine)**
- Location: `RustFTP/src/main.rs`
- Purpose: Concurrent FTP operations with advanced file stabilization
- Communication: JSON-based IPC via status and result files
- Features: Parallel downloads, connection pooling, smart retry logic

### **Data Flow**
1. **Configuration**: User creates FTP configuration in Swift UI
2. **Process Spawn**: Swift app writes config to JSON and spawns Rust process
3. **FTP Operations**: Rust engine performs concurrent FTP operations
4. **Status Updates**: Rust writes real-time status updates to JSON files
5. **UI Updates**: Swift monitors JSON files and updates interface in real-time
6. **File Processing**: Discovery → Stabilization → Parallel Download → Cleanup

## 🛠️ Installation & Setup

### **Prerequisites**
- macOS 13.0 (Ventura) or later
- Xcode 15.0+ (for building from source)
- Rust 1.70+ (for building Rust components)

### **Quick Start**
1. **Download & Build**:
   ```bash
   git clone https://github.com/your-repo/FTPDownloader.git
   cd FTPDownloader
   ./build.sh  # Builds complete app bundle
   ```

2. **Launch Application**:
   ```bash
   ./launch_app.sh
   ```

3. **Create Your First Configuration**:
   - Click "New Configuration"
   - Enter FTP server details (address, username, password, port)
   - Test connection to verify credentials
   - Set local download directory
   - Configure sync intervals and aggressiveness level
   - Add FTP directories to monitor

## 📖 Usage Guide

### **1. Configuration Setup**
- **Server Details**: Enter FTP server address, credentials, and port (default: 21)
- **Local Path**: Choose where downloaded files will be saved
- **Sync Settings**: Configure how often to check for new files (0.1s - 2hr)
- **Stabilization**: Set how long to wait for file size stability (0-60s)
- **Download Mode**: Choose "Delete After Download" or "Keep After Download"
- **Aggressiveness**: Select connection strategy based on server capacity

### **2. Performance Tuning**

#### **Aggressiveness Levels**
- **Conservative (3 connections)**: Gentle on servers, most reliable
- **Moderate (10 connections)**: Balanced performance, recommended default
- **Aggressive (20 connections)**: High speed for robust servers
- **Extreme (50 connections)**: Very high speed for enterprise servers
- **Maximum (100 connections)**: Maximum speed for high-capacity servers
- **Ultra (150 connections)**: Ultra-high speed for enterprise infrastructure
- **Extreme Max (200 connections)**: Maximum theoretical performance

#### **Sync Intervals**
- **0.1s - 1s**: Near real-time monitoring for time-critical applications
- **5s - 30s**: Standard monitoring for regular file transfers
- **1hr - 2hr**: Light monitoring for low-frequency file drops

### **3. Monitoring & Management**
- **Configuration Tabs**: Switch between multiple server configurations
- **Real-time Status**: Monitor connection status, download speeds, file counts
- **Live Logs**: Dedicated window showing detailed operation logs
- **Session Statistics**: Track performance metrics and download history
- **Start/Stop Controls**: Independent control of each configuration

### **4. File Processing States**
- **Pending**: File discovered, queued for processing
- **Monitoring**: File size being checked for stability
- **Downloading**: File actively being downloaded
- **Completed**: File successfully downloaded
- **Failed**: Download failed, automatic retry scheduled
- **Deleted**: File removed from server (if Delete mode enabled)

## ⚡ Performance Features

### **Concurrent Operations**
- **Parallel Downloads**: Multiple files processed simultaneously
- **Connection Pooling**: Efficient reuse of FTP connections
- **Async Processing**: Non-blocking operations for maximum throughput
- **Resource Management**: Intelligent memory and connection management

### **Smart Optimization**
- **Auto-tuning**: Automatic adjustment of connection strategies
- **Performance Tracking**: Real-time monitoring of files/second rates
- **Adaptive Timeouts**: Dynamic timeout adjustment based on server response
- **Batch Processing**: Efficient grouping of operations

## 🔧 Development

### **Build Commands**
```bash
# Complete app bundle build
./build.sh

# Swift-only build (faster iteration)
swift build --configuration release

# Rust-only build
cd RustFTP && cargo build --release

# Run tests
cd RustFTP && cargo test

# Launch built app
./launch_app.sh
```

### **Distribution**
```bash
# Build signed and notarized release
./build_and_notarize_spm.sh

# Update version numbers
./update_build_info.sh
```

### **Project Structure**
```
FTPDownloader/
├── Sources/FTPDownloader/     # Swift frontend
│   ├── FTPDownloaderApp.swift # Main app entry
│   ├── ContentView.swift      # Primary interface
│   ├── FTPConfig.swift        # Configuration model
│   ├── FileSyncManager.swift  # Sync orchestration
│   └── ...                    # Additional Swift files
├── RustFTP/                   # Rust backend
│   ├── src/main.rs           # FTP engine
│   ├── Cargo.toml            # Rust dependencies
│   └── ...                   # Rust modules
├── build.sh                  # Build scripts
├── Package.swift             # Swift package config
└── README.md                 # This file
```

## 🔒 Security Features

- **macOS Keychain Integration**: Encrypted storage of FTP credentials
- **Secure Communication**: Support for FTPS when available
- **Permission Validation**: Proper file system permission handling
- **Sandbox Compliance**: macOS security model compliance
- **Network Security**: Configurable transport security settings

## 🐛 Troubleshooting

### **Common Issues**
1. **Connection Failed**:
   - Verify server address, port, and credentials
   - Check firewall settings and network connectivity
   - Test with FTP client like FileZilla first

2. **Authentication Error**:
   - Confirm username and password are correct
   - Check if server requires specific authentication methods

3. **Permission Denied**:
   - Ensure local download directory is writable
   - Check FTP server permissions for specified directories

4. **Poor Performance**:
   - Try lower aggressiveness level
   - Increase stabilization interval
   - Check network bandwidth and server capacity

### **Performance Optimization**
- **Server Capacity**: Match aggressiveness level to server capabilities
- **Network Conditions**: Adjust for bandwidth and latency
- **File Patterns**: Optimize sync intervals based on file arrival frequency
- **Local Storage**: Use SSD storage for optimal download speeds

## 📝 Configuration File Format

FTP configurations are stored as JSON files with the following structure:
```json
{
  "id": "uuid",
  "name": "Configuration Name",
  "serverAddress": "ftp.example.com",
  "port": 21,
  "username": "user",
  "localDownloadPath": "/path/to/downloads",
  "syncDirectories": ["/remote/path1", "/remote/path2"],
  "syncInterval": 5.0,
  "stabilizationInterval": 10.0,
  "downloadMode": "delete",
  "downloadAggressiveness": 10,
  "autoTuneAggressiveness": true
}
```

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🤝 Contributing

Contributions are welcome! Please feel free to submit issues and pull requests.

### **Development Guidelines**
- Follow Swift and Rust coding standards
- Add tests for new functionality
- Update documentation for feature changes
- Test on multiple macOS versions

## 📞 Support

For support, bug reports, or feature requests:
- Open an issue on GitHub
- Contact the development team
- Check the troubleshooting section above

---

**Note**: This application expires on November 1, 2025. Contact support for updated versions.