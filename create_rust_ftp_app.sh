#!/bin/bash
# Create rust_ftp.app bundle structure for App Store compliance
# This allows rust_ftp to have app-sandbox entitlement with proper Info.plist

set -e

echo "🦀 Creating rust_ftp.app bundle..."

# Paths
RUST_BINARY="RustFTP/target/release/rust_ftp"
APP_BUNDLE="RustFTP/target/release/rust_ftp.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"

# Check if rust_ftp binary exists
if [ ! -f "$RUST_BINARY" ]; then
    echo "❌ Error: rust_ftp binary not found at $RUST_BINARY"
    echo "   Please build it first with: cd RustFTP && cargo build --release"
    exit 1
fi

# Remove old bundle if it exists
if [ -d "$APP_BUNDLE" ]; then
    echo "🧹 Removing old rust_ftp.app bundle..."
    rm -rf "$APP_BUNDLE"
fi

# Create app bundle structure
echo "📁 Creating app bundle structure..."
mkdir -p "$APP_MACOS"
mkdir -p "$APP_RESOURCES"

# Copy rust_ftp binary into the app bundle
echo "📦 Copying rust_ftp binary..."
cp "$RUST_BINARY" "$APP_MACOS/rust_ftp"
chmod +x "$APP_MACOS/rust_ftp"

# Create Info.plist for the app bundle
echo "📝 Creating Info.plist..."
cat > "$APP_CONTENTS/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>rust_ftp</string>
    <key>CFBundleIdentifier</key>
    <string>com.roningroupinc.FTPDownloader.rust-ftp</string>
    <key>CFBundleName</key>
    <string>rust_ftp</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

echo "✅ rust_ftp.app bundle created successfully at:"
echo "   $APP_BUNDLE"
echo ""
echo "📂 Bundle contents:"
ls -lh "$APP_MACOS"
echo ""
echo "✅ Ready for code signing with app-sandbox entitlement"
