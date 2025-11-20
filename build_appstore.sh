#!/bin/bash

# FTP Downloader App Store Build Script
# Supports beta builds and version increment
# Usage:
#   ./build_appstore.sh        - Build current version for production
#   ./build_appstore.sh -beta  - Build beta (auto-increment beta number)
#   ./build_appstore.sh -inc   - Increment patch version and build

set -e

# Parse arguments
BUILD_MODE="production"
if [ "$1" = "-beta" ]; then
    BUILD_MODE="beta"
elif [ "$1" = "-inc" ]; then
    BUILD_MODE="increment"
fi

echo "🏗️  FTP Downloader App Store Build"
echo "====================================="

# Check if we're in the right directory
if [ ! -f "Package.swift" ]; then
    echo "❌ Error: Package.swift not found. Please run this script from the FTPDownloader project root."
    exit 1
fi

# Paths
BASE_BUILD_DIR="build/appstore"
RELEASE_DIR="$BASE_BUILD_DIR/release"
BETA_DIR="$BASE_BUILD_DIR/beta"
APP_NAME="FTPDownloader.app"

# Get current version from Info.plist
INFO_PLIST="Sources/FTPDownloader/Info.plist"
CURRENT_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFO_PLIST" 2>/dev/null || echo "1.0.1")

# Function to archive existing builds before creating new one
# Move all existing builds to old/ directory, keep only last 2 in old/
archive_old_builds() {
    local DIR=$1
    local OLD_DIR="$DIR/old"
    local PATTERN=$2  # e.g., "FTPDownloader-*-beta*.app" or "FTPDownloader-*.app"

    mkdir -p "$OLD_DIR"

    # Get list of ALL builds in main directory (excluding old/ subdirectory)
    # Use -d flag to list directories themselves, not their contents
    local builds=($(ls -td "$DIR"/$PATTERN 2>/dev/null | grep -v "/old/"))

    # Move ALL existing builds to old/
    if [ ${#builds[@]} -gt 0 ]; then
        echo "📦 Archiving existing builds..."
        for build in "${builds[@]}"; do
            if [ -e "$build" ]; then
                local basename=$(basename "$build")
                local base="${basename%.app}"  # Remove .app extension

                # Move .app, .pkg, and -signed.pkg to old/
                if [ -e "$DIR/${base}.app" ]; then
                    mv "$DIR/${base}.app" "$OLD_DIR/" && echo "   Moved ${base}.app to old/"
                fi
                if [ -e "$DIR/${base}.pkg" ]; then
                    mv "$DIR/${base}.pkg" "$OLD_DIR/" && echo "   Moved ${base}.pkg to old/"
                fi
                if [ -e "$DIR/${base}-signed.pkg" ]; then
                    mv "$DIR/${base}-signed.pkg" "$OLD_DIR/" && echo "   Moved ${base}-signed.pkg to old/"
                fi
            fi
        done
    fi

    # Clean up old/ directory - keep only last 2
    local old_builds=($(ls -td "$OLD_DIR"/$PATTERN 2>/dev/null))
    if [ ${#old_builds[@]} -gt 2 ]; then
        echo "🗑️  Cleaning old archives (keeping last 2)..."
        for ((i=2; i<${#old_builds[@]}; i++)); do
            local build="${old_builds[$i]}"
            if [ -e "$build" ]; then
                local basename=$(basename "$build")
                local base="${basename%.app}"

                # Remove .app, .pkg, and -signed.pkg
                rm -rf "$OLD_DIR/${base}.app"
                rm -f "$OLD_DIR/${base}.pkg"
                rm -f "$OLD_DIR/${base}-signed.pkg"

                echo "   Deleted $basename"
            fi
        done
    fi
}

# Determine version and build number based on mode
if [ "$BUILD_MODE" = "beta" ]; then
    echo "🧪 Beta Build Mode"
    mkdir -p "$BETA_DIR"

    # Read beta number from tracking file, or start at 1
    BETA_VERSION_FILE="$BETA_DIR/beta_version.txt"
    if [ -f "$BETA_VERSION_FILE" ]; then
        LAST_BETA=$(cat "$BETA_VERSION_FILE")
        BETA_NUMBER=$((LAST_BETA + 1))
    else
        BETA_NUMBER=1
    fi

    # Write new beta number to tracking file
    echo "$BETA_NUMBER" > "$BETA_VERSION_FILE"
    VERSION="$CURRENT_VERSION"
    # Use pure timestamp for build number (always increases lexicographically)
    BUILD_NUMBER=$(date '+%Y%m%d%H%M%S')
    BUILD_DIR="$BETA_DIR"
    FILE_SUFFIX="-${VERSION}-beta${BETA_NUMBER}"

    echo "📦 Beta #${BETA_NUMBER}"
    echo "📱 Version: ${VERSION}"
    echo "🔢 Build: ${BUILD_NUMBER}"
    echo ""

    # Archive existing builds before creating new one
    archive_old_builds "$BETA_DIR" "FTPDownloader-*-beta*.app"

elif [ "$BUILD_MODE" = "increment" ]; then
    echo "⬆️  Increment Version Mode"
    mkdir -p "$RELEASE_DIR"

    # Increment patch version (1.0.1 -> 1.0.2)
    IFS='.' read -ra VERSION_PARTS <<< "$CURRENT_VERSION"
    MAJOR="${VERSION_PARTS[0]}"
    MINOR="${VERSION_PARTS[1]}"
    PATCH="${VERSION_PARTS[2]}"
    NEW_PATCH=$((PATCH + 1))
    NEW_VERSION="${MAJOR}.${MINOR}.${NEW_PATCH}"

    # Update Info.plist with new version
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${NEW_VERSION}" "$INFO_PLIST"

    VERSION="$NEW_VERSION"
    # Use pure timestamp for build number (always increases lexicographically)
    BUILD_NUMBER=$(date '+%Y%m%d%H%M%S')
    BUILD_DIR="$RELEASE_DIR"
    FILE_SUFFIX="-${VERSION}"

    echo "📱 Old Version: ${CURRENT_VERSION}"
    echo "📱 New Version: ${VERSION}"
    echo "🔢 Build: ${BUILD_NUMBER}"
    echo ""

    # Archive existing builds before creating new one
    archive_old_builds "$RELEASE_DIR" "FTPDownloader-*.app"

else
    echo "📦 Production Build Mode"
    mkdir -p "$RELEASE_DIR"

    VERSION="$CURRENT_VERSION"
    # Use pure timestamp for build number (always increases lexicographically)
    BUILD_NUMBER=$(date '+%Y%m%d%H%M%S')
    BUILD_DIR="$RELEASE_DIR"
    FILE_SUFFIX="-${VERSION}"

    echo "📱 Version: ${VERSION}"
    echo "🔢 Build: ${BUILD_NUMBER}"
    echo ""

    # Archive existing builds before creating new one
    archive_old_builds "$RELEASE_DIR" "FTPDownloader-*.app"
fi

echo "📁 Output: $BUILD_DIR"
echo ""

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

    # Check if any Rust source files are newer
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

# Create build directory (don't clean it to preserve previous builds)
mkdir -p "$BUILD_DIR"

# Calculate timestamps
BUILD_TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
BUILD_TIMESTAMP_ISO=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

echo "🔨 Building with APPSTORE_BUILD flag..."
swift build --configuration release -Xswiftc "-D" -Xswiftc "APPSTORE_BUILD"

if [ $? -ne 0 ]; then
    echo "❌ Build failed!"
    exit 1
fi

echo "✅ Build successful!"
echo ""
echo "📱 Creating app bundle..."

# Set app path with version in filename
APP_PATH="$BUILD_DIR/FTPDownloader${FILE_SUFFIX}.app"

# Create app bundle structure
mkdir -p "$APP_PATH/Contents/MacOS"
mkdir -p "$APP_PATH/Contents/Resources"

# Embed provisioning profile if it exists
if [ -f "FTPDownloader_App_Store.provisionprofile" ]; then
    xattr -d com.apple.quarantine "FTPDownloader_App_Store.provisionprofile" 2>/dev/null || true
    cp "FTPDownloader_App_Store.provisionprofile" "$APP_PATH/Contents/embedded.provisionprofile"
    echo "✅ Provisioning profile embedded"
elif ls *.provisionprofile 1> /dev/null 2>&1; then
    xattr -d com.apple.quarantine *.provisionprofile 2>/dev/null || true
    cp *.provisionprofile "$APP_PATH/Contents/embedded.provisionprofile"
    echo "✅ Provisioning profile embedded"
else
    echo "⚠️  Warning: No provisioning profile found. Download from developer.apple.com"
fi

# Copy the Swift binary
cp .build/release/FTPDownloader "$APP_PATH/Contents/MacOS/"
chmod +x "$APP_PATH/Contents/MacOS/FTPDownloader"

# Copy resources
if [ -f "app-icon.icns" ]; then
    cp "app-icon.icns" "$APP_PATH/Contents/Resources/"
    echo "✅ App icon copied"
fi

# Copy menu bar icons
if [ -f "app-icon-menubar-orange.png" ]; then
    cp "app-icon-menubar-orange.png" "$APP_PATH/Contents/Resources/"
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

# Create Info.plist
echo "📝 Creating Info.plist..."
cat > "$APP_PATH/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>FTPDownloader</string>
    <key>CFBundleIdentifier</key>
    <string>com.roningroupinc.FTPDownloader</string>
    <key>CFBundleName</key>
    <string>FTP Downloader</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUMBER}</string>
    <key>CFBundleGetInfoString</key>
    <string>App Store Build - $BUILD_TIMESTAMP</string>
    <key>BuildTimestamp</key>
    <string>$BUILD_TIMESTAMP_ISO</string>
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
EOF

# Code sign all executables with App Store certificate and entitlements
echo ""
echo "🔐 Code signing executables for App Store..."
PROJECT_DIR="$(pwd)"
SIGNING_CERT="Apple Distribution: Ronin Group Inc. (6X7BH7FLQ8)"
APP_ENTITLEMENTS="$PROJECT_DIR/Sources/FTPDownloader/FTPDownloader.entitlements"

# Clean up any extended attributes and resource forks that can cause signing issues
echo "🧹 Cleaning up extended attributes..."
xattr -cr "$APP_PATH"
find "$APP_PATH" -type f -name "._*" -delete
find "$APP_PATH" -type f -name ".DS_Store" -delete

# Sign the main executable with entitlements and identifier
echo "📱 Signing FTPDownloader with entitlements..."
codesign --force --sign "$SIGNING_CERT" \
    --entitlements "$APP_ENTITLEMENTS" \
    --identifier "com.roningroupinc.FTPDownloader" \
    --options runtime \
    --timestamp \
    "$APP_PATH/Contents/MacOS/FTPDownloader"
echo "  ✅ FTPDownloader signed"

# Sign the entire app bundle with identifier
echo "📦 Signing app bundle..."
codesign --force --sign "$SIGNING_CERT" \
    --entitlements "$APP_ENTITLEMENTS" \
    --identifier "com.roningroupinc.FTPDownloader" \
    --options runtime \
    --timestamp \
    "$APP_PATH"
echo "  ✅ App bundle signed"

# Verify code signature
echo ""
echo "🔍 Verifying signatures..."
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
echo "✅ Signature verification complete"

# Create .pkg installer for App Store submission
echo ""
echo "📦 Creating .pkg installer for App Store..."
PKG_PATH="$BUILD_DIR/FTPDownloader${FILE_SUFFIX}.pkg"
SIGNED_PKG_PATH="$BUILD_DIR/FTPDownloader${FILE_SUFFIX}-signed.pkg"

# Create a copy with the standard name for packaging
# This ensures the installed app is named "FTPDownloader.app" without version suffix
PACKAGE_APP_PATH="$BUILD_DIR/FTPDownloader.app"
if [ "$APP_PATH" != "$PACKAGE_APP_PATH" ]; then
    echo "📝 Creating package copy without version suffix..."
    # Remove any existing copy first to avoid stale versions
    rm -rf "$PACKAGE_APP_PATH"
    cp -R "$APP_PATH" "$PACKAGE_APP_PATH"
    echo "✅ Created $PACKAGE_APP_PATH from $APP_PATH"
fi

productbuild --component "$PACKAGE_APP_PATH" /Applications "$PKG_PATH"

if [ $? -eq 0 ]; then
    echo "✅ Package created successfully!"

    # Sign the package
    echo ""
    echo "🔐 Signing package for App Store..."
    productsign --sign "3rd Party Mac Developer Installer: Ronin Group Inc. (6X7BH7FLQ8)" \
        "$PKG_PATH" "$SIGNED_PKG_PATH"

    if [ $? -eq 0 ]; then
        echo "✅ Package signed successfully!"

        # Verify signature
        echo ""
        echo "🔍 Verifying signature..."
        pkgutil --check-signature "$SIGNED_PKG_PATH"

        echo ""
        echo "✅ App Store build complete!"
        echo "================================================"
        echo "📊 Build Summary:"
        echo "   Mode: $BUILD_MODE"
        echo "   Version: ${VERSION}"
        echo "   Build: ${BUILD_NUMBER}"
        if [ "$BUILD_MODE" = "beta" ]; then
            echo "   Beta #: ${BETA_NUMBER}"
        fi
        echo ""
        echo "📂 Output Files:"
        echo "   📱 App: $APP_PATH"
        echo "   📦 Package: $PKG_PATH"
        echo "   🔐 Signed Package: $SIGNED_PKG_PATH"
        echo ""

        if [ "$BUILD_MODE" = "beta" ]; then
            echo "🧪 BETA BUILD - Upload to TestFlight:"
            echo "   1. Open Transporter app"
            echo "   2. Drag: $SIGNED_PKG_PATH"
            echo "   3. In App Store Connect → TestFlight tab"
            echo "   4. Select build ${BUILD_NUMBER}"
            echo "   5. Distribute to testers"
            echo ""
            echo "🔄 Next beta: ./build_appstore.sh -beta"
            echo "📦 Release: ./build_appstore.sh -inc"
        elif [ "$BUILD_MODE" = "increment" ]; then
            echo "📦 PRODUCTION BUILD - Ready to release:"
            echo "   Version incremented: ${CURRENT_VERSION} → ${VERSION}"
            echo ""
            echo "📤 Upload to App Store:"
            echo "   1. Open Transporter app"
            echo "   2. Drag: $SIGNED_PKG_PATH"
            echo "   3. Submit for review in App Store Connect"
            echo ""
            echo "🧪 Test first: ./build_appstore.sh -beta"
        else
            echo "📤 UPLOAD TO APP STORE:"
            echo "   1. Open Transporter app"
            echo "   2. Drag: $SIGNED_PKG_PATH"
            echo "   3. Click 'Deliver'"
            echo ""
            echo "🧪 Build beta: ./build_appstore.sh -beta"
            echo "⬆️  Increment: ./build_appstore.sh -inc"
        fi
        echo "================================================"
    else
        echo "❌ Failed to sign package"
        exit 1
    fi
else
    echo "❌ Failed to create package"
    exit 1
fi
