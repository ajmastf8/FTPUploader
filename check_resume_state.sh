#!/bin/bash

# Check the current state of FTPDownloader resume functionality
echo "🔍 FTPDownloader Resume State Diagnostic"
echo "=========================================="
echo ""

# Check build timestamp
if [ -d "build/dev/FTPDownloader.app" ]; then
    BUILD_TIME=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" build/dev/FTPDownloader.app 2>/dev/null)
    echo "📦 Latest Build: $BUILD_TIME"
    echo "   Location: build/dev/FTPDownloader.app"
else
    echo "⚠️  No build found at build/dev/FTPDownloader.app"
fi
echo ""

# Check if app is running
PID=$(pgrep -x "FTPDownloader" | head -1)
if [ -n "$PID" ]; then
    echo "✅ FTPDownloader is running (PID: $PID)"

    # Check how long it's been running
    START_TIME=$(ps -p "$PID" -o lstart= 2>/dev/null)
    echo "   Started: $START_TIME"

    # Check rust_ftp processes
    RUST_COUNT=$(pgrep -x "rust_ftp" | wc -l | tr -d ' ')
    if [ "$RUST_COUNT" -gt 0 ]; then
        echo "   ✅ $RUST_COUNT rust_ftp process(es) running"
        ps aux | grep "rust_ftp" | grep -v grep | awk '{print "      PID " $2 " started " $9}'
    else
        echo "   ℹ️  No rust_ftp processes running"
    fi
else
    echo "❌ FTPDownloader is not running"
fi
echo ""

# Check notification files
echo "📝 Notification Files:"
NOTIF_COUNT=$(ls -1 /tmp/ftp_notifications_*.jsonl 2>/dev/null | wc -l | tr -d ' ')
if [ "$NOTIF_COUNT" -gt 0 ]; then
    echo "   Found $NOTIF_COUNT notification file(s):"
    ls -1 /tmp/ftp_notifications_*.jsonl 2>/dev/null | while read -r file; do
        SIZE=$(wc -l < "$file" 2>/dev/null || echo 0)
        MODIFIED=$(stat -f "%Sm" -t "%H:%M:%S" "$file" 2>/dev/null)
        echo "      $(basename "$file"): $SIZE lines (modified $MODIFIED)"

        # Show last 3 notifications
        if [ "$SIZE" -gt 0 ]; then
            echo "      Recent notifications:"
            tail -3 "$file" | jq -r '"\(.timestamp | tonumber / 1000 | strftime("%H:%M:%S")): \(.notification_type) - \(.message)"' 2>/dev/null | sed 's/^/         /'
        fi
    done
else
    echo "   No notification files found"
fi
echo ""

# Check network interfaces
echo "🌐 Current Network Status:"
ACTIVE_IFACE=""
for iface in en0 en1 en2 en3 en4 en5; do
    if ifconfig "$iface" 2>/dev/null | grep -q "status: active"; then
        IP=$(ifconfig "$iface" | grep "inet " | awk '{print $2}')
        TYPE="Unknown"
        if ifconfig "$iface" | grep -q "media:.*Ethernet"; then
            TYPE="Ethernet"
        elif ifconfig "$iface" | grep -q "media:.*Wi-Fi"; then
            TYPE="WiFi"
        fi
        echo "   ✅ $iface ($TYPE): Active - IP: $IP"
        ACTIVE_IFACE="$iface"
    fi
done
echo ""

# Check recent logs for resume-related activity
echo "📋 Recent Resume Activity (last 50 lines):"
echo "   Looking for sleep/wake/network events..."
log show --predicate 'process == "FTPDownloader"' --last 5m --style compact 2>/dev/null | \
    grep -E "(SLEEP|WAKE|NETWORK|restart|pause|resume)" | \
    tail -20 | \
    sed 's/^/   /'

if [ $? -ne 0 ] || [ -z "$(log show --predicate 'process == "FTPDownloader"' --last 5m 2>/dev/null)" ]; then
    echo "   No recent activity found"
fi
echo ""

echo "=========================================="
echo "🧪 Quick Test Commands:"
echo "=========================================="
echo ""
echo "Test sleep/wake resume:"
echo "  ./monitor_sleep_wake.sh"
echo ""
echo "Test network interface changes:"
echo "  ./test_network_change.sh"
echo ""
echo "Build and launch latest version:"
echo "  ./build.sh && ./launch_app.sh"
echo ""

