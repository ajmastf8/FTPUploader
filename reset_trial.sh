#!/bin/bash

# Reset FTP Downloader Trial and Purchase Data
# Use this to test trial expiration and purchase flow

echo "🔄 Resetting FTP Downloader trial and purchase data..."

# Kill the app if running
echo "🛑 Stopping app..."
pkill -9 FTPDownloader 2>/dev/null || echo "   App not running"

# Delete all app data (including purchases, trial info, configurations)
echo "🗑️  Deleting app data..."
if [ -d ~/Library/Containers/com.roningroupinc.FTPDownloader ]; then
    rm -rf ~/Library/Containers/com.roningroupinc.FTPDownloader
    echo "   ✅ App data deleted"
else
    echo "   ℹ️  No app data found"
fi

# Delete preferences
echo "🗑️  Deleting preferences..."
defaults delete com.roningroupinc.FTPDownloader 2>/dev/null || echo "   No preferences found"

# Delete trial data from Keychain (NEW - prevents reinstall bypass)
echo "🔐 Deleting trial data from Keychain..."
security delete-generic-password -s "com.roningroupinc.FTPDownloader.trial" -a "trial_first_launch" 2>/dev/null && echo "   ✅ Keychain trial data deleted" || echo "   ℹ️  No trial data found in Keychain"

echo ""
echo "🧪 Setting debug flags for testing..."
defaults write com.roningroupinc.FTPDownloader DEBUG_FORCE_TRIAL_EXPIRED -bool true
defaults write com.roningroupinc.FTPDownloader DEBUG_BYPASS_PURCHASE_CHECK -bool true
echo "   ✅ Trial forced to expire"
echo "   ✅ Purchase status bypassed (set to false)"

echo ""
echo "✅ Reset complete!"
echo "🚀 Launch the app to test trial expiration and purchase screen"
echo ""
echo "📝 What was done:"
echo "   - Deleted all app data (trial date, purchases, configs)"
echo "   - Deleted trial data from Keychain (prevents reinstall bypass)"
echo "   - Set DEBUG_FORCE_TRIAL_EXPIRED and DEBUG_BYPASS_PURCHASE_CHECK flags"
echo "   - App will show purchase screen immediately on launch"
echo ""
echo "🔄 To disable debug flags:"
echo "   defaults delete com.roningroupinc.FTPDownloader DEBUG_FORCE_TRIAL_EXPIRED"
echo "   defaults delete com.roningroupinc.FTPDownloader DEBUG_BYPASS_PURCHASE_CHECK"
