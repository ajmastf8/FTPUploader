# FTP Downloader - Sales Guide

## Tagline
**Automated FTP file monitoring that lives in your menu bar - always watching, never in the way.**

## Elevator Pitch
FTP Downloader is a professional macOS menu bar application that continuously monitors FTP servers and automatically downloads new files to your Mac. Set it up once, and it runs invisibly in the background - surviving sleep/wake cycles, network changes, and system restarts. Perfect for professionals who need reliable, unattended file synchronization without the complexity of enterprise solutions.

## Core Value Proposition
Stop manually checking FTP servers for new files. FTP Downloader watches your servers 24/7 and downloads new files automatically, so you can focus on your work instead of babysitting file transfers.

## Key Benefits

### 1. Set It and Forget It
- Configure once, runs forever
- Automatic restart after Mac sleeps or wakes
- Survives network changes (WiFi to Ethernet and back)
- Auto-start on login option for true "set and forget" operation

### 2. Always Running, Never Intrusive
- Lives quietly in your menu bar - no dock icon cluttering your workspace
- One-click access to status and controls
- Main window only appears when you need it
- Minimal memory footprint - won't slow down your Mac

### 3. Visual Status at a Glance
- Color-coded menu bar icon instantly shows system status
  - **Orange**: Ready and waiting
  - **Green**: Actively downloading files
  - **Red**: Attention needed (connection issue)
- No need to open windows or check logs - just glance at your menu bar

### 4. Intelligent File Handling
- Waits for files to finish uploading before downloading (no partial files)
- Smart change detection - only downloads files that have changed
- Prevents duplicate downloads with built-in hash tracking
- Optional automatic deletion of files after successful download

### 5. Enterprise Reliability, Consumer Simplicity
- High-performance Rust engine for demanding workloads
- Handles large files and high-volume transfers with ease
- Parallel downloads for maximum speed
- Simple, intuitive interface anyone can use

### 6. Secure by Design
- All passwords stored in macOS Keychain (same security as Safari passwords)
- Never stores credentials in plain text files
- Built-in sandboxing for App Store compliance
- No telemetry or tracking - your data stays yours

## Feature List

### File Monitoring
- Continuous FTP server monitoring with configurable scan intervals
- File stabilization detection (waits for uploads to complete)
- Automatic retry with exponential backoff for failed operations
- Hash-based change tracking (XXH3 algorithm for speed)
- SQLite database for fast lookups and history

### Connection Management
- Multiple FTP server configurations
- Per-configuration start/stop controls
- Connection state monitoring with detailed error reporting
- Automatic reconnection after network changes
- Support for standard FTP (port 21)

### User Interface
- Clean menu bar popover showing all configurations
- Per-configuration status indicators (color-coded dots)
- Session statistics (files downloaded counter)
- Quick access to local download folders (click to open in Finder)
- Clickable configuration names to view details
- Right-click context menu for quick actions

### Background Operation
- Runs during screen lock and screensaver
- Automatic sleep/wake handling with clean process management
- Network interface change detection and recovery
- Launch at login support (with system approval)
- Failsafe wake detection if system notifications fail

### Configuration
- Simple setup wizard for FTP server details
- Per-configuration settings:
  - Scan interval (how often to check for new files)
  - Run on launch (automatic start when app opens)
  - Stabilization time (wait time for files to finish uploading)
  - Delete after download (clean up server after successful transfer)
- Secure credential storage in macOS Keychain
- Configuration export/import for backup and sharing

### Status & Monitoring
- Real-time connection state tracking
- Live notification feed with color-coded messages
- Session-based file counters (resets when sync stops)
- Detailed error messages with troubleshooting hints
- Console log collection for support requests

### Advanced Features
- Demo mode for testing and demonstrations
- Custom configuration cache to minimize Keychain prompts
- Automatic JSON to Keychain migration for upgrades
- Multiple configurations can run simultaneously
- Notification feed with filterable message types

## Use Cases

### 1. Media Production
**Problem**: Production studios receive footage from multiple remote cameras/sources via FTP throughout the day.
**Solution**: FTP Downloader monitors all FTP drops 24/7, automatically downloading new clips as they arrive. Editors always have the latest footage ready to work with - no manual checking required.

### 2. Data Collection
**Problem**: Remote sensors or instruments upload measurement data to FTP servers on a schedule.
**Solution**: Researchers configure FTP Downloader to monitor their data servers, ensuring continuous collection without manual intervention. Data is ready for analysis immediately upon upload.

### 3. Print Services
**Problem**: Clients upload print-ready files to FTP servers, but staff must constantly check for new submissions.
**Solution**: FTP Downloader watches client FTP folders and downloads new orders automatically. Staff receive visual notification via menu bar icon color change when new jobs arrive.

### 4. Automated Workflows
**Problem**: Businesses receive invoices, reports, or documents from partners via FTP and need them ingested into local systems.
**Solution**: FTP Downloader monitors partner FTP folders and downloads files to a watched folder where other automation tools pick them up. Creates a seamless automated pipeline.

### 5. Content Distribution
**Problem**: News agencies, stock photo services, or content providers deliver files via FTP that need to be available locally ASAP.
**Solution**: FTP Downloader ensures files arrive on the local system within seconds of appearing on the FTP server, with no manual checking required.

## Target Customers

### Primary Audiences
- **Media professionals** (video editors, photographers, designers)
- **IT administrators** managing automated file transfers
- **Researchers and scientists** collecting remote data
- **Small businesses** receiving files from partners/clients
- **Print shops and service bureaus** accepting customer uploads

### Customer Profile
- Uses Mac as primary workstation
- Needs reliable, unattended file synchronization
- Wants simplicity over complex enterprise features
- Values "set it and forget it" reliability
- Prefers native Mac apps over web-based solutions

## Competitive Advantages

### vs. Manual FTP Clients (FileZilla, Transmit, etc.)
- **Automatic**: No need to remember to check for new files
- **Always running**: Works even when you're not at your desk
- **Smarter**: Waits for files to finish uploading, tracks changes, prevents duplicates

### vs. Enterprise FTP Solutions
- **Simpler**: No complex configuration or IT department required
- **More affordable**: One-time purchase vs. expensive subscriptions
- **Native Mac experience**: Designed for macOS, not a cross-platform Java app

### vs. Cloud Sync Services (Dropbox, etc.)
- **Works with existing FTP servers**: No need to migrate infrastructure
- **More control**: You own the server and data
- **Purpose-built**: Designed specifically for FTP monitoring, not general file sync

## Objection Handling

### "I already have an FTP client"
Traditional FTP clients require you to manually connect and check for new files. FTP Downloader does this automatically 24/7, so you never miss new files. It's like having an assistant whose only job is to check your FTP server and download new files.

### "Why not just use a script or cron job?"
Scripts require technical knowledge to set up, debug, and maintain. FTP Downloader provides a user-friendly interface, visual status indicators, error handling, and automatic recovery from network issues - all without writing a single line of code.

### "My FTP server doesn't get many files"
Even if you only receive a few files per week, wouldn't you rather know immediately when they arrive instead of checking manually multiple times per day? FTP Downloader runs silently in the background, using minimal resources, so there's no downside to leaving it running.

### "I'm worried about security"
FTP Downloader stores all passwords in macOS Keychain - the same secure system Safari uses for your passwords. Credentials are never stored in plain text files. The app is sandboxed for App Store compliance, meaning it can only access folders you explicitly grant permission to.

### "What if my Mac goes to sleep?"
That's exactly when FTP Downloader shines. It detects when your Mac sleeps, cleanly stops all transfers, then automatically resumes monitoring when your Mac wakes up. You don't have to do anything - it just works.

## Pricing Strategy Considerations

### Value-Based Pricing
- Time saved checking FTP servers manually (hours per week)
- Cost of missed files due to manual process failures
- Value of "peace of mind" from automated monitoring
- Replacement cost vs. building custom solution or hiring developer

### Positioning
- **Premium over consumer tools**: More than basic FTP clients ($20-40 range)
- **Fraction of enterprise solutions**: Less than enterprise FTP automation ($500+ range)
- **Comparable to professional productivity tools**: Similar to other pro Mac utilities ($40-80 range)

### Suggested Price Points
- **One-time purchase**: $49.99 (positioning as professional tool)
- **Trial period**: 15 days (enough time to set up and see value)
- **Educational discount**: 40% off for students/teachers
- **Volume licensing**: Available for businesses (5+ seats)

## Sales Messaging

### Homepage Hero
**"Stop checking. Start automating."**
FTP Downloader monitors your FTP servers 24/7 and downloads new files automatically - so you can focus on your work, not file transfers.

### Feature Callouts
- **Works While You Sleep**: Literally. Automatic sleep/wake handling means you never miss files.
- **Know at a Glance**: Color-coded menu bar icon shows status without opening a window.
- **Smart Downloads**: Waits for files to finish uploading and only downloads what's changed.
- **Set It Once**: Launch at login, auto-start configurations, and automatic recovery mean true "set and forget" operation.

### Call to Action
"Download free 15-day trial" (with no credit card required)

## Demo Script

### Opening (30 seconds)
"FTP Downloader is a menu bar app that automatically monitors FTP servers and downloads new files. Let me show you how simple it is..."

### Setup Demo (2 minutes)
1. Click menu bar icon → Show Main Window
2. Click "New Configuration"
3. Fill in FTP server details (use demo values)
4. Enable "Run on Launch" checkbox
5. Click Save
6. Click green play button in menu bar popover

### Active Monitoring Demo (1 minute)
1. Show orange icon turning green when sync starts
2. Upload a file to FTP server (or use demo mode)
3. Show file counter incrementing in menu bar popover
4. Click folder icon to show downloaded file in Finder

### Sleep/Wake Demo (1 minute)
1. Put Mac to sleep
2. Wait 5 seconds, wake Mac
3. Show logs: "System woke from sleep - restarting FTP monitoring"
4. Point out that sync resumed automatically

### Closing (30 seconds)
"And that's it. FTP Downloader now runs silently in the background, checking your server and downloading new files automatically. You'll see the menu bar icon change color when files arrive, but otherwise, it stays out of your way."

## FAQ

**Q: Does it support SFTP or FTPS?**
A: Currently supports standard FTP (port 21). SFTP support is planned for a future update.

**Q: How many configurations can I create?**
A: Unlimited. All configurations can run simultaneously.

**Q: Does it work on Apple Silicon Macs?**
A: Yes, native Apple Silicon support.

**Q: What macOS version is required?**
A: macOS 12 (Monterey) or later.

**Q: Can I schedule different scan intervals for different times of day?**
A: Not currently, but this is a popular feature request.

**Q: What happens if my Mac runs out of disk space?**
A: Downloads will fail gracefully with an error message, and you'll see a red status indicator.

**Q: Can I filter which files get downloaded (by extension, name, etc.)?**
A: Not in the current version, but file filtering is planned for a future update.

**Q: How do I get support?**
A: Use Help → Contact Support to collect logs and send them via email.

## Marketing Channels

### Primary
- Mac App Store (discoverability, trust, easy updates)
- Product website with demo video
- YouTube tutorials and use case demos

### Secondary
- Mac productivity blogs and review sites
- Professional forums (media production, print services, etc.)
- Social media (Twitter, Reddit r/macapps, r/productivity)

### Partnerships
- FTP server hosting providers (affiliate programs)
- Industry-specific software vendors (integrations)
- Mac management tool vendors (enterprise bundles)

## Success Metrics

### Adoption
- Trial download rate
- Trial-to-paid conversion rate
- Average time to first configuration
- Daily active users (configurations running)

### Engagement
- Average number of configurations per user
- Average files downloaded per day
- Retention rate (still using after 30/60/90 days)

### Satisfaction
- App Store rating and reviews
- Support ticket volume and resolution time
- Feature request frequency and themes
- Refund/churn rate

## Roadmap Teases (for sales conversations)

### Coming Soon
- SFTP (Secure FTP) support
- File filtering by name pattern or extension
- Bandwidth throttling for large transfers
- Download scheduling (active hours)

### Under Consideration
- Two-way sync (upload local changes to server)
- Integration with popular cloud storage services
- REST API for automation and scripting
- Team features (shared configurations, central management)

---

## Closing Thoughts

FTP Downloader solves a specific problem exceptionally well: automatically monitoring FTP servers and downloading new files without manual intervention. The key to successful sales is identifying customers who currently check FTP servers manually and showing them how much time and frustration they'll save with automation.

Focus on the "set it and forget it" reliability, the visual status feedback (color-coded menu bar icon), and the peace of mind that comes from knowing files are being downloaded automatically - even when they're away from their desk, asleep, or working on something else.

The app sells itself once users see how simple the setup is and how reliably it runs in the background. The 15-day trial gives them plenty of time to experience that reliability firsthand.
