#!/bin/bash

echo "🔧 Sleep/Wake Fix - Rebuild and Test"
echo "====================================="
echo ""

# Kill existing app
echo "1️⃣ Stopping any running instances..."
killall -9 FTPDownloader 2>/dev/null
sleep 2

# Clean old build
echo ""
echo "2️⃣ Cleaning old build..."
mv build/dev build/dev.old 2>/dev/null

# Rebuild
echo ""
echo "3️⃣ Building app with sleep/wake fixes..."
./build.sh

if [ $? -ne 0 ]; then
    echo "❌ Build failed!"
    exit 1
fi

echo ""
echo "✅ Build successful!"
echo ""
echo "4️⃣ Launching app..."
./launch_app.sh &

# Wait for app to launch
sleep 3

echo ""
echo "5️⃣ Checking if app is running..."
if pgrep -x "FTPDownloader" > /dev/null; then
    echo "✅ App is running (PID: $(pgrep -x FTPDownloader))"
else
    echo "❌ App failed to launch"
    exit 1
fi

echo ""
echo "6️⃣ Checking for AppDelegate initialization in logs..."
echo "   Looking for setup messages..."
sleep 1

# Check Console.app logs using the built-in logger
echo ""
echo "📋 Recent app initialization logs:"
log show --predicate 'process == "FTPDownloader"' --style compact --last 30s 2>/dev/null | grep -E "(AppDelegate|VERIFICATION|Sleep/wake|GUARD)" | tail -10

echo ""
echo "======================================"
echo "✅ Setup complete!"
echo ""
echo "📝 Next steps:"
echo "   1. Start an FTP configuration in the app"
echo "   2. Put your Mac to sleep (⌘⌥ Power)"
echo "   3. Wake it up"
echo "   4. Check if the configuration restarts automatically"
echo ""
echo "   To monitor live: ./diagnose_sleep_wake.sh"
echo "======================================"
