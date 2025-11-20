#!/bin/bash

echo "🔍 Sleep/Wake Diagnostic Tool"
echo "=============================="
echo ""

# Check if app is running
echo "1️⃣ Checking if FTPDownloader is running..."
if pgrep -x "FTPDownloader" > /dev/null; then
    echo "✅ FTPDownloader is running (PID: $(pgrep -x FTPDownloader))"
else
    echo "❌ FTPDownloader is NOT running"
    echo "   Please launch the app first!"
    exit 1
fi

echo ""
echo "2️⃣ Checking for recent wake notifications in system log..."
# Look for wake events in the last 5 minutes
log show --predicate 'eventMessage CONTAINS "Wake"' --last 5m --info | head -20

echo ""
echo "3️⃣ Checking FTPDownloader logs for sleep/wake activity..."
# Get FTPDownloader logs from last 5 minutes
log show --predicate 'process == "FTPDownloader"' --last 5m --info | grep -i -E "(sleep|wake|💤|⏰)" | tail -30

echo ""
echo "4️⃣ Live monitoring starting now..."
echo "   💤 Put your Mac to sleep, then wake it up"
echo "   📊 Press Ctrl+C to stop monitoring"
echo ""

# Stream live logs
log stream --predicate 'process == "FTPDownloader"' --level info | while read line; do
    # Highlight important lines
    if echo "$line" | grep -q -E "(💤|⏰|SLEEP|WAKE|pause|restart)"; then
        echo "🔴 $line"
    fi
done
