#!/bin/bash

# Test script to verify sleep/wake detection is working
# This monitors system logs for our app's sleep/wake messages

echo "🔍 Monitoring FTP Downloader sleep/wake behavior..."
echo "💤 Put your Mac to sleep now, then wake it up"
echo "📊 Watching for sleep/wake notifications..."
echo ""

# Monitor unified log for our app's sleep/wake messages
log stream --predicate 'process == "FTPDownloader"' --level debug | grep -E "(SLEEP NOTIFICATION|WAKE NOTIFICATION|pauseAllActiveConfigurations|restartActiveConfigurations)"
