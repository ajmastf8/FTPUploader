#!/bin/bash

# Comprehensive network change testing script
echo "🧪 FTPDownloader Network Interface Change Test"
echo "=============================================="
echo ""

# Check if app is running
PID=$(pgrep -x "FTPDownloader" | head -1)
if [ -z "$PID" ]; then
    echo "❌ FTPDownloader is not running"
    echo "   Please start the app first and begin an FTP sync"
    exit 1
fi

echo "✅ FTPDownloader is running (PID: $PID)"
echo ""

# Check for rust_ftp processes
RUST_PIDS=$(pgrep -x "rust_ftp")
if [ -z "$RUST_PIDS" ]; then
    echo "⚠️  No rust_ftp processes found"
    echo "   Please start an FTP sync before testing"
    echo ""
else
    echo "✅ Found rust_ftp processes:"
    ps aux | grep "rust_ftp" | grep -v grep | awk '{print "   PID " $2 ": " $11 " " $12 " " $13}'
    echo ""
fi

# Check notification files
echo "📝 Checking notification files in /tmp:"
NOTIF_FILES=$(ls -1 /tmp/ftp_notifications_*.jsonl 2>/dev/null)
if [ -z "$NOTIF_FILES" ]; then
    echo "   No notification files found"
else
    echo "$NOTIF_FILES" | while read -r file; do
        line_count=$(wc -l < "$file" 2>/dev/null || echo 0)
        echo "   $(basename "$file"): $line_count notifications"
    done
fi
echo ""

# Show current network interfaces
echo "🌐 Current Network Interfaces:"
ifconfig | grep -E "^(en|utun|lo)" | cut -d: -f1 | while read -r iface; do
    status=$(ifconfig "$iface" | grep "status:" | awk '{print $2}')
    inet=$(ifconfig "$iface" | grep "inet " | awk '{print $2}')
    if [ -n "$inet" ]; then
        echo "   $iface: $status - IP: $inet"
    else
        echo "   $iface: $status"
    fi
done
echo ""

echo "=============================================="
echo "🧪 Test Procedure:"
echo "=============================================="
echo ""
echo "1. ✅ Verify FTP sync is running in the FTPDownloader app"
echo ""
echo "2. 🔌 Change network interface:"
echo "   - If on Ethernet: Unplug cable and connect to WiFi"
echo "   - If on WiFi: Connect Ethernet cable"
echo ""
echo "3. 📋 Watch for these events in the logs below:"
echo "   a. 🌐 Network status changed"
echo "   b. 🛑 Killing rust_ftp processes"
echo "   c. 🔄 Restarting configurations"
echo "   d. ✅ Connected to FTP server"
echo ""
echo "4. 🖥️  Check the FTPDownloader UI:"
echo "   - Should show 'Network interface changed' notification"
echo "   - Should reconnect and resume scanning within 3 seconds"
echo ""
echo "=============================================="
echo "📊 Live Monitoring (Press Cmd+C to stop)"
echo "=============================================="
echo ""

# Start live monitoring with timestamps
log stream --predicate 'process == "FTPDownloader"' --level debug --style compact 2>/dev/null | \
    grep --line-buffered -E "(🌐|NETWORK|🔄|restart|RESTART|kill|SIGTERM|SIGKILL|configIsSyncing|Connected to|Failed to list|network interface)"

