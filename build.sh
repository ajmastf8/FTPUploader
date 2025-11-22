#!/bin/bash

# FTP Sender Development Build
# Builds development version - no expiration, shows trial UI for testing
# Output: build/dev/
#
# Usage:
#   ./build.sh              - Normal dev build (no purchase UI)
#   ./build.sh --test-expired - Test purchase screen (enables trial UI with expired trial)

set -e

# Parse command line arguments
TEST_EXPIRED=false
if [ "$1" = "--test-expired" ]; then
    TEST_EXPIRED=true
    echo "🍎 FTP Sender Development Build (TEST EXPIRED TRIAL)"
    echo "======================================================="
    echo "⚠️  Purchase UI enabled with expired trial for testing"
else
    echo "🍎 FTP Sender Development Build"
    echo "=================================="
fi
echo "📂 Output: build/dev/"
echo ""

# Check if we're in the right directory
if [ ! -f "Package.swift" ]; then
    echo "❌ Error: Package.swift not found. Please run this script from the FTPSender project root."
    exit 1
fi

# Function to check if Rust static library needs rebuilding
check_rust_library() {
    local rust_library="RustFTP/target/release/librust_ftp.a"
    local rust_src_dir="RustFTP/src"
    local cargo_toml="RustFTP/Cargo.toml"

    echo "🦀 Checking Rust FTP static library..."

    if [ ! -f "$rust_library" ]; then
        echo "📦 Rust static library not found, building..."
        return 1
    fi

    # Check if any Rust source files are newer
    if [ -d "$rust_src_dir" ]; then
        local newer_files=$(find "$rust_src_dir" -name "*.rs" -newer "$rust_library" 2>/dev/null)
        if [ -n "$newer_files" ]; then
            echo "🔄 Rust source files are newer than library, rebuilding..."
            return 1
        fi
    fi

    # Check if Cargo.toml is newer (dependency changes)
    if [ -f "$cargo_toml" ] && [ "$cargo_toml" -nt "$rust_library" ]; then
        echo "🔄 Cargo.toml is newer than library, rebuilding..."
        return 1
    fi

    echo "✅ Rust static library is up to date"
    return 0
}

# Function to build Rust static library
build_rust_library() {
    echo "🦀 Building Rust FTP static library..."
    if [ ! -d "RustFTP" ]; then
        echo "❌ Error: RustFTP directory not found"
        exit 1
    fi

    cd RustFTP
    if cargo build --release --lib; then
        cd ..
        echo "✅ Rust FTP static library built successfully"
        ls -lh RustFTP/target/release/librust_ftp.a
    else
        cd ..
        echo "❌ Failed to build Rust FTP static library"
        exit 1
    fi
}

# Check and build Rust static library if needed
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

# Create build directory
BUILD_DIR="build/dev"
APP_NAME="FTPSender.app"
APP_PATH="$BUILD_DIR/$APP_NAME"

echo "📦 Building FTP Sender (Development Build)..."
echo ""

# Clean previous dev builds
echo "🧹 Cleaning previous dev builds..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Build the project in release mode
echo "🔨 Building project in release mode..."
if [ "$TEST_EXPIRED" = true ]; then
    # Build with TEST_EXPIRED flag to enable purchase UI testing
    swift build --configuration release -Xswiftc "-D" -Xswiftc "TEST_EXPIRED"
else
    # Normal dev build (no special flags)
    swift build --configuration release
fi

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Release build successful!"
    echo ""
    echo "📱 Creating app bundle..."

    # Create app bundle structure
    mkdir -p "$APP_PATH/Contents/MacOS"
    mkdir -p "$APP_PATH/Contents/Resources"

    # Copy the Swift binary (now contains statically-linked Rust code)
    cp .build/release/FTPSender "$APP_PATH/Contents/MacOS/"
    chmod +x "$APP_PATH/Contents/MacOS/FTPSender"

    echo "✅ Swift executable copied (with embedded Rust FFI library)"

    # Copy the app icon
    if [ -f "app-icon.icns" ]; then
        cp "app-icon.icns" "$APP_PATH/Contents/Resources/"
        echo "✅ App icon copied to bundle"
    else
        echo "⚠️  Warning: app-icon.icns not found"
    fi

    # Copy menu bar icons
    if [ -f "app-icon-menubar-blue.png" ]; then
        cp "app-icon-menubar-blue.png" "$APP_PATH/Contents/Resources/"
        echo "✅ Menu bar orange icon copied to bundle"
    fi
    if [ -f "app-icon-menubar-green.png" ]; then
        cp "app-icon-menubar-green.png" "$APP_PATH/Contents/Resources/"
        echo "✅ Menu bar green icon copied to bundle"
    fi
    if [ -f "app-icon-menubar-red.png" ]; then
        cp "app-icon-menubar-red.png" "$APP_PATH/Contents/Resources/"
        echo "✅ Menu bar red icon copied to bundle"
    fi

    # Copy Help resources from SPM bundle
    if [ -d ".build/arm64-apple-macosx/release/FTPSender_FTPSender.bundle/Help" ]; then
        cp -r ".build/arm64-apple-macosx/release/FTPSender_FTPSender.bundle/Help" "$APP_PATH/Contents/Resources/"
        echo "✅ Help resources copied to bundle"
    fi

    # Get current build timestamp
    BUILD_TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    BUILD_TIMESTAMP_ISO=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    BUILD_DATE=$(date '+%Y%m%d')
    BUILD_TIME=$(date '+%H%M%S')

    # Create Info.plist
    echo "📝 Creating Info.plist for Development build: $BUILD_TIMESTAMP"
    cat > "$APP_PATH/Contents/Info.plist" << 'INFOPLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>FTPSender</string>
    <key>CFBundleIdentifier</key>
    <string>com.roningroupinc.ftpsender</string>
    <key>CFBundleName</key>
    <string>FTP Sender</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.1</string>
    <key>CFBundleVersion</key>
    <string>BUILD_VERSION_PLACEHOLDER</string>
    <key>CFBundleGetInfoString</key>
    <string>BUILD_TIMESTAMP_PLACEHOLDER</string>
    <key>BuildTimestamp</key>
    <string>BUILD_TIMESTAMP_ISO_PLACEHOLDER</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <false/>
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
INFOPLIST

    # Replace placeholders with actual values
    sed -i '' "s/BUILD_VERSION_PLACEHOLDER/$BUILD_DATE.$BUILD_TIME/g" "$APP_PATH/Contents/Info.plist"
    sed -i '' "s/BUILD_TIMESTAMP_PLACEHOLDER/Development Build - $BUILD_TIMESTAMP/g" "$APP_PATH/Contents/Info.plist"
    sed -i '' "s/BUILD_TIMESTAMP_ISO_PLACEHOLDER/$BUILD_TIMESTAMP_ISO/g" "$APP_PATH/Contents/Info.plist"

    # Clean extended attributes (resource forks) before signing
    # This prevents "resource fork, Finder information, or similar detritus not allowed" errors
    echo "🧹 Cleaning extended attributes..."
    xattr -cr "$APP_PATH"

    # Sign the app with Developer ID certificate (or fallback to ad-hoc if not available)
    # Proper signing is required for newer macOS versions to prevent SIGKILL
    echo "🔐 Signing app..."
    DEVELOPER_ID=$(security find-identity -p codesigning -v | grep "Developer ID Application" | head -1 | sed -E 's/^.*"(.+)"$/\1/')
    if [ -n "$DEVELOPER_ID" ]; then
        echo "   Using Developer ID: $DEVELOPER_ID"
        codesign --force --sign "$DEVELOPER_ID" --entitlements Sources/FTPSender/FTPSender.entitlements --options runtime "$APP_PATH" 2>&1 | grep -v "replacing existing signature" || true
        echo "✅ App signed with Developer ID (hardened runtime)"
    else
        echo "   No Developer ID found, using ad-hoc signature"
        codesign --force --sign - --entitlements Sources/FTPSender/FTPSender.entitlements "$APP_PATH" 2>&1 | grep -v "replacing existing signature" || true
        echo "✅ App signed (ad-hoc with entitlements)"
    fi

    # Verify the app bundle
    echo "🔍 Verifying app bundle..."
    if [ -d "$APP_PATH" ] && [ -f "$APP_PATH/Contents/MacOS/FTPSender" ]; then
        echo "✅ App bundle verified successfully"
        echo ""
        echo "🚀 Ready to launch with: ./launch_app.sh"
        echo "📱 App location: $APP_PATH"
        echo "📅 Build timestamp: $BUILD_TIMESTAMP"
        echo "🔢 Build version: $BUILD_DATE.$BUILD_TIME"
    else
        echo "❌ App bundle verification failed"
        exit 1
    fi

else
    echo ""
    echo "❌ Release build failed!"
    exit 1
fi
