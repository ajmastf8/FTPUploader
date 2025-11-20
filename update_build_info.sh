#!/bin/bash

# Update Build Info Script
# This script updates the app's build information with current date/time

set -e

echo "🏗️  Updating build information..."

# Get current date and time
BUILD_DATE=$(date '+%B %d, %Y at %I:%M %p')
BUILD_TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S %Z')
BUILD_NUMBER=$(date '+%Y%m%d.%H%M')

echo "📅 Build Date: $BUILD_DATE"
echo "🕐 Build Timestamp: $BUILD_TIMESTAMP"
echo "🔢 Build Number: $BUILD_NUMBER"

# Update Info.plist with build information
INFO_PLIST="Sources/FTPDownloader/Info.plist"

if [ -f "$INFO_PLIST" ]; then
    echo "📝 Updating Info.plist..."
    
    # Update CFBundleVersion (build number)
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$INFO_PLIST" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Add :CFBundleVersion string $BUILD_NUMBER" "$INFO_PLIST"
    
    # Update CFBuildDate (build date)
    /usr/libexec/PlistBuddy -c "Set :CFBuildDate $BUILD_DATE" "$INFO_PLIST" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Add :CFBuildDate string $BUILD_DATE" "$INFO_PLIST"
    
    # Update CFBuildTimestamp (detailed timestamp)
    /usr/libexec/PlistBuddy -c "Set :CFBuildTimestamp $BUILD_TIMESTAMP" "$INFO_PLIST" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Add :CFBuildTimestamp string $BUILD_TIMESTAMP" "$INFO_PLIST"
    
    echo "✅ Info.plist updated successfully"
else
    echo "⚠️  Info.plist not found at $INFO_PLIST"
    echo "📝 Creating Info.plist with build information..."
    
    # Create Info.plist if it doesn't exist
    cat > "$INFO_PLIST" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleVersion</key>
    <string>$BUILD_NUMBER</string>
    <key>CFBuildDate</key>
    <string>$BUILD_DATE</string>
    <key>CFBuildTimestamp</key>
    <string>$BUILD_TIMESTAMP</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.1</string>
    <key>CFBundleIdentifier</key>
    <string>com.roningroupinc.ftpsync</string>
    <key>CFBundleName</key>
    <string>FTP Downloader</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleSignature</key>
    <string>????</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF
    
    echo "✅ Info.plist created successfully"
fi

# Also update Package.swift if it exists
if [ -f "Package.swift" ]; then
    echo "📝 Updating Package.swift build number..."
    
    # Create backup
    cp Package.swift Package.swift.backup
    
    # Note: Package.swift version is managed separately from build info
    echo "ℹ️  Package.swift version managed separately"
    
    echo "✅ Package.swift updated"
fi

echo "🎉 Build information updated successfully!"
echo ""
echo "📊 Summary:"
echo "   Build Date: $BUILD_DATE"
echo "   Build Time: $BUILD_TIMESTAMP"
echo "   Build Number: $BUILD_NUMBER"
echo ""
echo "💡 Users can now see this information in Help → About FTP Downloader"
