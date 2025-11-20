#!/bin/bash

# Monitor FTPDownloader logs in real-time for sleep/wake events
echo "🔍 Monitoring FTPDownloader sleep/wake events..."
echo "📝 Press Cmd+C to stop monitoring"
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
echo "=========================================="
echo ""

# Monitor Console.app logs for FTPDownloader
log stream --predicate 'process == "FTPDownloader"' --level debug 2>/dev/null | grep --line-buffered -E "(SLEEP|WAKE|FAILSAFE|pause|restart|START SYNC|Connected to)"
