# App Review Notes - FTP Downloader

## For Apple App Review Team

Thank you for reviewing FTP Downloader! This app provides automated FTP file downloading with intelligent monitoring and high-performance concurrent processing.

---

## Quick Start - Test with Demo Mode (No FTP Server Required)

**FTP Downloader includes a built-in demo mode so you can test all features without needing an FTP server.**

### Step-by-Step Testing Instructions:

#### 1. **Launch the Application**
   - Open FTP Downloader
   - The app will automatically create a "Demo Configuration" on first launch
   - You'll see the demo configuration tab in the main interface

#### 2. **View Demo Configuration Settings**
   - Click the **⚙️ (gear icon)** on the Demo Configuration tab
   - **IMPORTANT**: Look for the **orange demo banner** at the top:
     - Banner states: "Demo Mode - This configuration cannot be edited"
     - All form fields are disabled (grayed out) to prevent editing
     - This is intentional design to distinguish demo from real configs
   - Review the pre-filled settings:
     - Server: demo.example.com
     - Username: demo_user
     - Port: 21
     - Sync intervals, aggressiveness levels, etc.
   - Click **Cancel** to close the configuration view

#### 3. **Test Connection Simulation**
   - Click the **⚙️ (gear icon)** again to reopen demo configuration
   - Click **"Test Connection"** button
   - You'll see: ✅ "Demo connection successful! (Simulated)"
   - This demonstrates the connection testing UI without a real server

#### 4. **Start Demo Session**
   - Close the configuration view
   - Click the **"Start"** button on the Demo Configuration tab
   - Observe the following simulated operations:

   **a) Status Updates:**
   - Status changes from "Not Connected" to "Connecting..." to "Connected"
   - Connection indicator turns green

   **b) Real-Time Performance Metrics:**
   - Session statistics display file counts
   - Active files/minute metric appears
   - Average MB/s speed displays
   - All metrics update in real-time with simulated data

   **c) Notification Feed:**
   - Scroll down to the notification feed area
   - You'll see simulated notifications:
     - "Session started"
     - "Files discovered"
     - "File stabilized"
     - "Downloaded: [filename]"
   - Notifications appear with timestamps and icons

#### 5. **Live Logs Viewer**
   - Click **"Live Logs"** button in the toolbar
   - A separate window opens showing detailed operation logs
   - Logs display with different notification types:
     - 🔵 Info messages
     - ✅ Success messages
     - ⚠️ Warning messages
   - All logs are simulated but demonstrate real functionality

#### 6. **Stop Demo Session**
   - Return to main window
   - Click **"Stop"** button on Demo Configuration tab
   - Status returns to "Not Connected"
   - Session statistics remain visible (showing completed session data)
   - **Note**: Stop button responds instantly (no delay/freeze)

---

## What to Look For During Demo Mode Testing

### ✅ **User Interface**
- [ ] Demo banner clearly visible in configuration view
- [ ] All form fields properly disabled in demo mode
- [ ] Orange/yellow banner color distinguishes demo mode
- [ ] Professional, clean macOS native interface
- [ ] Proper dark mode support (if testing in dark mode)

### ✅ **Performance Metrics**
- [ ] Session statistics update in real-time
- [ ] File counter increments during demo session
- [ ] Files/minute metric displays correctly
- [ ] Average speed (MB/s) shows realistic values
- [ ] Metrics formatted properly (e.g., "11 files • 8.2 files/min • 2.45 MB/s")

### ✅ **Notifications & Logging**
- [ ] Notification feed displays messages during demo
- [ ] Messages have appropriate icons and colors
- [ ] Timestamps appear on notifications
- [ ] Live Logs window opens and displays detailed logs
- [ ] Logs categorized by type (Info, Success, Warning, Error)

### ✅ **Controls & Responsiveness**
- [ ] Start button initiates demo session immediately
- [ ] Stop button responds instantly (no UI freeze)
- [ ] Configuration view opens/closes smoothly
- [ ] Test Connection button shows simulated result
- [ ] All buttons have appropriate enabled/disabled states

### ✅ **Demo Mode Safety**
- [ ] Cannot modify demo configuration settings
- [ ] Cannot save changes to demo configuration
- [ ] "Save Changes" button is disabled in demo config view
- [ ] Demo config clearly labeled to prevent confusion

---

## Testing Real FTP Configuration (Optional)

If you have access to an FTP server and wish to test real functionality:

### Creating a Real Configuration:

1. Click **"New Configuration"** button in toolbar
2. Enter FTP server details:
   - Server Address: your.ftp.server.com
   - Username: your_username
   - Password: your_password
   - Port: 21 (standard FTP)
3. Click **"Test Connection"**
   - Should return success or error based on credentials
4. Click **"Browse"** to select local download directory
   - macOS file picker will request folder access permission
5. Click **"Browse FTP"** to select remote directories
   - Connects to FTP server and lists available directories
   - Select directories to monitor
6. Configure sync settings:
   - Sync interval (how often to check for files)
   - Stabilization interval (how long to wait for file stability)
   - Aggressiveness (connection count: 3-200)
7. Click **"Create Configuration"**
8. Click **"Start"** to begin real FTP monitoring

### Real FTP Features to Test:
- Connection to actual FTP server
- Directory browsing and selection
- File discovery and monitoring
- Actual file downloads to local directory
- Session statistics tracking real operations
- Multiple configuration management

---

## Privacy & Permissions

### Required Permissions:
- **Network Access**: For FTP server connections
- **File System Access**: User grants access when selecting download folder
- **Keychain Access**: Passwords stored securely in macOS Keychain

### Privacy Commitment:
- ✅ No data collection or analytics
- ✅ No telemetry or tracking
- ✅ All data stored locally only
- ✅ Direct FTP connections (no proxy/relay servers)
- ✅ No third-party data sharing

---

## Known Behaviors (Not Bugs)

### Demo Configuration:
- **Demo config is read-only by design** - Prevents confusion between demo and real configs
- **Demo config not saved to disk** - Recreated fresh each session
- **Simulated metrics may seem "too perfect"** - Real-world usage has normal variance
- **Instant connection success** - Real FTP servers require actual network time

### Performance:
- **Stop button responds instantly** - We fixed a previous deadlock issue
- **File counts accurate** - We implemented deduplication to prevent double-counting
- **Metrics exclude idle time** - Active files/min only counts download time, not waiting time

---

## Technical Architecture

### Hybrid Swift/Rust Design:
- **Swift Frontend**: SwiftUI native interface, configuration management
- **Rust Backend**: High-performance FTP engine (embedded static library)
- **Communication**: FFI (Foreign Function Interface) bridge
- **Benefits**: Combines macOS native UI with Rust performance

### Why This Matters:
- Rust handles intensive FTP operations without blocking UI
- Swift provides native macOS experience and integration
- FFI allows both components to work seamlessly together

---

## System Requirements

- **macOS**: 13.0 (Ventura) or later
- **Architecture**: Apple Silicon (M1, M2, M3)
- **Disk Space**: 50 MB
- **Network**: Required for FTP server connections

---

## Support & Contact

If you have questions during review or need assistance testing specific features, please contact:

**Developer Contact**: [Your Email]
**Support Website**: [Your Website]

---

## Summary - What Makes This App Valuable

### For Users:
1. **Automated FTP Monitoring**: Set it and forget it - continuously monitors FTP servers
2. **Intelligent File Handling**: Prevents downloading incomplete files via stabilization
3. **High Performance**: Concurrent downloads with 3-200 connection pools
4. **Enterprise Ready**: Suitable for business workflows with high file volumes
5. **Risk-Free Demo**: Test all features without FTP server setup

### For App Store:
1. **Fills a Gap**: No comparable automated FTP app with this level of performance
2. **Professional Quality**: Native Swift UI, production-ready Rust engine
3. **User-Friendly**: Demo mode lowers barrier to entry
4. **Privacy Focused**: Local-only storage, no data collection
5. **Well-Maintained**: Active development, responsive to user needs

---

## Testing Checklist for Review

- [ ] Launch app successfully
- [ ] Demo configuration appears automatically
- [ ] Open demo configuration settings (verify banner and disabled fields)
- [ ] Test connection in demo mode (verify simulated success)
- [ ] Start demo session (verify status changes and metrics)
- [ ] View notification feed (verify simulated messages appear)
- [ ] Open Live Logs window (verify detailed logging)
- [ ] Stop demo session (verify instant response, no freeze)
- [ ] Optionally test real FTP connection (if FTP server available)
- [ ] Verify app doesn't crash or hang during normal use
- [ ] Check that permissions are requested appropriately
- [ ] Confirm privacy policy compliance (no data collection)

---

**Thank you for reviewing FTP Downloader!**

We've designed this app to be both powerful for enterprise users and accessible for newcomers through demo mode. If you have any questions or need clarification on any feature, please don't hesitate to reach out.
