#!/bin/bash

echo "🔍 Live Sleep/Wake Monitor"
echo "=========================="
echo ""
echo "This will show you EXACTLY what happens during sleep/wake."
echo ""
echo "📝 Instructions:"
echo "   1. Start an FTP configuration in the app"
echo "   2. Put your Mac to sleep (close lid or ⌘⌥ Power)"
echo "   3. Wait a few seconds"
echo "   4. Wake it up"
echo "   5. Watch this terminal for the magic!"
echo ""
echo "Watching console log file..."
echo "======================================"
echo ""

# Find the latest console log
LOG_FILE=$(ls -t /var/folders/yj/qj_3wbgn1xxbnrtflz73_5qh0000gn/T/FTPDownloader_Console_*.log 2>/dev/null | head -1)

if [ -z "$LOG_FILE" ]; then
    echo "❌ No console log found - is the app running?"
    exit 1
fi

echo "📋 Monitoring: $LOG_FILE"
echo ""

# Tail the log and highlight sleep/wake events
tail -f "$LOG_FILE" | while read line; do
    if echo "$line" | grep -q -E "(💤|⏰|SLEEP|WAKE|pause|restart|shutdown file)"; then
        echo "🔴 $line"
    elif echo "$line" | grep -q -E "(🧹|Cleaning|Removed shutdown)"; then
        echo "🟢 $line"
    fi
done
