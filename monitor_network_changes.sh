#!/bin/bash

# Monitor FTPDownloader logs for network interface changes and restart behavior
echo "🌐 Monitoring FTPDownloader network change detection..."
echo "📝 This will show you when:"
echo "   - Network interface changes are detected (Ethernet ↔ WiFi)"
echo "   - FTP processes are killed and restarted"
echo "   - Configurations are resumed after network changes"
echo ""
echo "🧪 Testing Steps:"
echo "   1. Start FTP sync on Ethernet"
echo "   2. Unplug Ethernet and connect to WiFi (or vice versa)"
echo "   3. Watch for network detection and restart messages below"
echo ""
echo "📋 Press Cmd+C to stop monitoring"
echo ""
echo "==========================================="
echo ""

# Get the app's process ID
PID=$(pgrep -x "FTPDownloader" | head -1)

if [ -z "$PID" ]; then
    echo "❌ FTPDownloader is not running"
    exit 1
fi

echo "✅ Found FTPDownloader PID: $PID"
echo "👀 Monitoring console output..."
echo ""
echo "==========================================="
echo ""

# Monitor Console.app logs for FTPDownloader with focus on network and restart events
log stream --predicate 'process == "FTPDownloader"' --level debug 2>/dev/null | \
    grep --line-buffered -E "(🌐|NETWORK|🔄|restart|RESTART|kill|SIGTERM|SIGKILL|configIsSyncing|Connected to|Failed to list)"

