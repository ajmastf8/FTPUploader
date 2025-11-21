#!/bin/bash

# FTP Uploader App Launcher
# Launches the .app bundle from terminal to see logs

echo "🚀 FTP Uploader App Launcher"
echo "============================"

# Check if we're in the right directory
if [ ! -f "Package.swift" ]; then
    echo "❌ Error: Package.swift not found. Please run this script from the FTPUploader project root."
    exit 1
fi

# Look for app bundle (dev build by default)
BUILD_DIR="build/dev"
APP_NAME="FTPUploader.app"
APP_PATH="$BUILD_DIR/$APP_NAME"

if [ ! -d "$APP_PATH" ]; then
    echo "❌ App bundle not found at: $APP_PATH"
    echo ""
    echo "Please build the app first with:"
    echo "  ./build.sh"
    exit 1
fi

echo "📱 Found app bundle at: $APP_PATH"
echo ""
echo "🚀 Launching FTP Uploader app..."
echo "📋 Logs will appear below:"
echo "================================"
echo ""

# Launch the app from terminal to see logs
"$APP_PATH/Contents/MacOS/FTPUploader"
