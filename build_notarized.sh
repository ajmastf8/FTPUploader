#!/bin/bash

# FTP Sender Notarized Build Script
# Builds with 15-day expiration, no purchase UI
# Output: build/notarized/

set -e

echo "🏗️  FTP Sender Notarized Build"
echo "===================================="
echo "📅 15-day expiration from build date"
echo "🚫 Purchase UI disabled"
echo ""

# Check if we're in the right directory
if [ ! -f "Package.swift" ]; then
    echo "❌ Error: Package.swift not found. Please run this script from the FTPSender project root."
    exit 1
fi

# Configuration
# Use specific certificate hash to avoid "ambiguous" error with duplicate certs
# Using the second Developer ID certificate as the first one has chain issues
CERTIFICATE_NAME="5D81AE7E8E898B892D408AFF1479B2F5BA9A81D2"
TEAM_ID="6X7BH7FLQ8"
BUNDLE_ID="com.roningroupinc.ftpsender"
APPLEID="aj@ajmast.com"
APPLEIDPASS="zsbr-skjw-ippy-egwh"

# Paths
PROJECT_DIR="$(pwd)"
BUILD_DIR="build/notarized"
APP_NAME="FTPSender.app"
APP_PATH="$BUILD_DIR/$APP_NAME"
DMG_PATH="$BUILD_DIR/FTPSender.dmg"
ZIP_PATH="$BUILD_DIR/FTPSender.zip"

# Function to check if Rust binary needs rebuilding
check_rust_library() {
    local rust_library="RustFTP/target/release/librust_ftp.a"
    local rust_src_dir="RustFTP/src"
    local cargo_toml="RustFTP/Cargo.toml"

    echo "🦀 Checking Rust FTP engine binary..."

    if [ ! -f "$rust_library" ]; then
        echo "📦 Rust binary not found, building..."
        return 1
    fi

    if [ -d "$rust_src_dir" ]; then
        local newer_files=$(find "$rust_src_dir" -name "*.rs" -newer "$rust_library" 2>/dev/null)
        if [ -n "$newer_files" ]; then
            echo "🔄 Rust source files are newer than binary, rebuilding..."
            return 1
        fi
    fi

    # Check if Cargo.toml is newer (dependency changes)
    if [ -f "$cargo_toml" ] && [ "$cargo_toml" -nt "$rust_library" ]; then
        echo "🔄 Cargo.toml is newer than binary, rebuilding..."
        return 1
    fi

    echo "✅ Rust binary is up to date"
    return 0
}

# Function to build Rust binary
build_rust_library() {
    echo "🦀 Building Rust FTP engine..."
    if [ ! -d "RustFTP" ]; then
        echo "❌ Error: RustFTP directory not found"
        exit 1
    fi

    cd RustFTP
    if cargo build --release --lib; then
        cd ..
        echo "✅ Rust FTP engine built successfully"
    else
        cd ..
        echo "❌ Failed to build Rust FTP engine"
        exit 1
    fi
}

# Check and build Rust binary if needed
RUST_REBUILT=false
if ! check_rust_library; then
    build_rust_library
    RUST_REBUILT=true
fi

# If Rust library was rebuilt, clean Swift build cache to force relink
if [ "$RUST_REBUILT" = true ]; then
    echo "🔄 Rust library was rebuilt, cleaning Swift build cache to force relink..."
    rm -rf .build
fi

# Clean previous builds
echo "🧹 Cleaning previous notarized builds..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Calculate expiration date (15 days from now)
BUILD_TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
BUILD_TIMESTAMP_ISO=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
BUILD_DATE=$(date '+%Y%m%d')
BUILD_TIME=$(date '+%H%M%S')
EXPIRATION_DATE=$(date -v+15d '+%B %d, %Y')

echo "🔨 Building with NOTARIZED_BUILD flag..."
swift build --configuration release -Xswiftc "-D" -Xswiftc "NOTARIZED_BUILD"

if [ $? -ne 0 ]; then
    echo "❌ Build failed!"
    exit 1
fi

echo "✅ Build successful!"
echo ""
echo "📱 Creating app bundle..."

# Create app bundle structure
mkdir -p "$APP_PATH/Contents/MacOS"
mkdir -p "$APP_PATH/Contents/Resources"

# Copy the Swift binary
cp .build/release/FTPSender "$APP_PATH/Contents/MacOS/"
chmod +x "$APP_PATH/Contents/MacOS/FTPSender"

# Copy resources
if [ -f "app-icon.icns" ]; then
    cp "app-icon.icns" "$APP_PATH/Contents/Resources/"
    echo "✅ App icon copied"
fi

# Copy menu bar icons (color-coded status indicators)
if [ -f "app-icon-menubar-blue.png" ]; then
    cp "app-icon-menubar-blue.png" "$APP_PATH/Contents/Resources/"
    echo "✅ Menu bar orange icon copied"
fi
if [ -f "app-icon-menubar-green.png" ]; then
    cp "app-icon-menubar-green.png" "$APP_PATH/Contents/Resources/"
    echo "✅ Menu bar green icon copied"
fi
if [ -f "app-icon-menubar-red.png" ]; then
    cp "app-icon-menubar-red.png" "$APP_PATH/Contents/Resources/"
    echo "✅ Menu bar red icon copied"
fi

echo "✅ Swift executable copied (with embedded Rust FFI library)"

# Create Info.plist with build timestamp
echo "📝 Creating Info.plist with 15-day expiration..."
cat > "$APP_PATH/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>FTPSender</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>FTP Sender</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.1</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_DATE.$BUILD_TIME</string>
    <key>CFBundleGetInfoString</key>
    <string>Notarized Build - $BUILD_TIMESTAMP - Expires: $EXPIRATION_DATE</string>
    <key>BuildTimestamp</key>
    <string>$BUILD_TIMESTAMP_ISO</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
    <key>CFBundleIconFile</key>
    <string>app-icon.icns</string>
    <key>ITSAppUsesNonExemptEncryption</key>
    <false/>
</dict>
</plist>
EOF

# Code signing
echo "🔐 Signing app bundle..."
echo "Using certificate: $CERTIFICATE_NAME"

# Sign the main app binary with entitlements and identifier
echo "📱 Signing main app binary (with embedded Rust FFI library)..."
codesign --force --options runtime --sign "$CERTIFICATE_NAME" \
    --entitlements "$PROJECT_DIR/Sources/FTPSender/FTPSender.entitlements" \
    --identifier "com.roningroupinc.ftpsender" \
    --timestamp \
    "$APP_PATH/Contents/MacOS/FTPSender"
echo "✅ Main binary signed"

# Sign the app bundle (without --deep to preserve individual signatures)
echo "📦 Signing app bundle..."
codesign --force --options runtime --sign "$CERTIFICATE_NAME" \
    --entitlements "$PROJECT_DIR/Sources/FTPSender/FTPSender.entitlements" \
    --timestamp \
    "$APP_PATH"
echo "✅ App bundle signed"

echo "✅ Code signing complete"

# Verify signature
echo "🔍 Verifying signature..."
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
spctl --assess --type exec --verbose=4 "$APP_PATH" || echo "⚠️  Note: App will be accepted after notarization"

# Set the app bundle icon using fileicon (after code signing)
if command -v fileicon >/dev/null 2>&1; then
    fileicon set "$APP_PATH" "$PROJECT_DIR/app-icon.icns" 2>/dev/null && echo "✅ App bundle custom icon set"
fi

# Create professional DMG
echo "📦 Creating professional DMG..."
cd "$BUILD_DIR"

# Create a temporary directory for DMG contents
DMG_TEMP_DIR="dmg_temp"
mkdir -p "$DMG_TEMP_DIR"

# Copy the app to the temp directory
cp -R "$APP_NAME" "$DMG_TEMP_DIR/"

# Create Applications folder alias
ln -s /Applications "$DMG_TEMP_DIR/Applications"

# Create professional DMG with icon and Applications alias
echo "🎨 Creating professional DMG with custom icon..."

# Check if create-dmg is available
if command -v create-dmg >/dev/null 2>&1; then
    echo "✅ Using create-dmg for professional DMG creation..."

    # Remove the Applications link if it exists to avoid conflicts
    rm -f "$DMG_TEMP_DIR/Applications"

    # Use create-dmg with icon support
    create-dmg \
        --volname "FTP Sender" \
        --volicon "$PROJECT_DIR/app-icon.icns" \
        --window-pos 200 120 \
        --window-size 600 400 \
        --icon-size 100 \
        --icon "$APP_NAME" 175 190 \
        --hide-extension "$APP_NAME" \
        --app-drop-link 425 190 \
        "FTPSender.dmg" \
        "$DMG_TEMP_DIR"

    # Recreate the Applications link after DMG creation
    ln -s /Applications "$DMG_TEMP_DIR/Applications"

    if [ $? -eq 0 ]; then
        echo "✅ Professional DMG created with custom icon successfully!"
    else
        echo "⚠️  Failed to create DMG with create-dmg, falling back to basic approach"
        hdiutil create -volname "FTP Sender" -srcfolder "$DMG_TEMP_DIR" -ov -format UDZO "FTPSender.dmg"
    fi
else
    echo "ℹ️  create-dmg not found, using basic hdiutil approach..."
    # Create basic DMG
    hdiutil create -volname "FTP Sender" -srcfolder "$DMG_TEMP_DIR" -ov -format UDZO "FTPSender.dmg"
fi

# Set the DMG file icon (the file itself, not just the volume)
echo "🎨 Setting DMG file icon..."
# Find the actual DMG file (in case create-dmg created a conflicted name)
ACTUAL_DMG=$(ls -t FTPSender*.dmg 2>/dev/null | head -1)
if [ -n "$ACTUAL_DMG" ] && [ -f "$ACTUAL_DMG" ]; then
    # Move it to the expected name if different
    if [ "$ACTUAL_DMG" != "FTPSender.dmg" ]; then
        mv "$ACTUAL_DMG" "FTPSender.dmg"
    fi
    if command -v fileicon >/dev/null 2>&1; then
        if fileicon set "FTPSender.dmg" "$PROJECT_DIR/app-icon.icns" 2>/dev/null; then
            echo "✅ DMG file icon set successfully"
        else
            echo "⚠️  Failed to set DMG file icon"
        fi
    else
        echo "ℹ️  fileicon tool not found, DMG file icon not set"
        echo "   Install with: brew install fileicon"
    fi
else
    echo "⚠️  DMG file not found"
fi

# Clean up temp directory
rm -rf "$DMG_TEMP_DIR"

cd "$PROJECT_DIR"

# Sign DMG
echo "🔐 Signing DMG..."
codesign --force --sign "$CERTIFICATE_NAME" \
    --timestamp \
    "$DMG_PATH"

# Create ZIP for notarization
echo "📦 Creating ZIP for notarization..."
cd "$BUILD_DIR"
zip -r "FTPSender.zip" "$APP_NAME"
cd -

# Submit for notarization
echo "📤 Submitting for notarization..."
xcrun notarytool submit "$ZIP_PATH" \
    --apple-id "$APPLEID" \
    --password "$APPLEIDPASS" \
    --team-id "$TEAM_ID" \
    --wait

# Staple notarization ticket
echo "📎 Stapling notarization ticket to app..."
xcrun stapler staple "$APP_PATH"

echo "📎 Stapling notarization ticket to DMG..."
xcrun stapler staple "$DMG_PATH"

echo ""
echo "✅ Notarized build complete!"
echo "📂 Output directory: $BUILD_DIR"
echo "📱 App: $APP_PATH"
echo "💿 DMG: $DMG_PATH"
echo "📅 Build date: $BUILD_TIMESTAMP"
echo "⏰ Expires: $EXPIRATION_DATE (30 days)"
echo ""
echo "Ready for distribution!"
