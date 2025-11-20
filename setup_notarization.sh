#!/bin/bash

# Setup Script for Notarization
# This script will help you configure all the components needed for notarization

set -e

echo "🔧 Setting up notarization for FTP Downloader..."
echo "================================================"

# Check if we're in the right directory
if [ ! -f "Package.swift" ]; then
    echo "❌ Error: Please run this script from the FTPDownloader project root directory"
    exit 1
fi

# Check required tools
echo "🔍 Checking required tools..."

# Check Xcode Command Line Tools
if ! xcode-select -p &> /dev/null; then
    echo "❌ Xcode Command Line Tools not found. Installing..."
    xcode-select --install
    echo "⏳ Please complete the Xcode Command Line Tools installation and run this script again"
    exit 1
else
    echo "✅ Xcode Command Line Tools found"
fi

# Check Rust
if ! command -v cargo &> /dev/null; then
    echo "❌ Rust not found. Installing..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source ~/.cargo/env
    echo "✅ Rust installed"
else
    echo "✅ Rust found: $(cargo --version)"
fi

# Check create-dmg
if ! command -v create-dmg &> /dev/null; then
    echo "❌ create-dmg not found. Installing..."
    if command -v brew &> /dev/null; then
        brew install create-dmg
        echo "✅ create-dmg installed"
    else
        echo "❌ Homebrew not found. Please install Homebrew first:"
        echo "   /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
        exit 1
    fi
else
    echo "✅ create-dmg found"
fi

echo ""
echo "🔑 Setting up notarization credentials..."
echo "========================================"

# Get Apple ID
read -p "Enter your Apple ID email: " APPLE_ID

# Get Team ID
read -p "Enter your Team ID (6X7BH7FLQ8): " TEAM_ID
TEAM_ID=${TEAM_ID:-6X7BH7FLQ8}

# Get app-specific password
echo ""
echo "📱 You need to generate an app-specific password:"
echo "1. Go to https://appleid.apple.com"
echo "2. Sign in with your Apple ID"
echo "3. Go to 'Sign-in and Security' > 'App-Specific Passwords'"
echo "4. Click 'Generate Password'"
echo "5. Enter a label (e.g., 'FTP Downloader Notarization')"
echo "6. Copy the generated password"
echo ""
read -s -p "Enter the app-specific password: " APP_SPECIFIC_PASSWORD
echo ""

# Get certificate name
echo ""
echo "🔐 You need to find your Developer ID Application certificate:"
echo "1. Open Keychain Access"
echo "2. Look for 'Developer ID Application: [Your Name] ([Team ID])'"
echo "3. Or run: security find-identity -v -p codesigning"
echo ""
read -p "Enter the full certificate name: " CERTIFICATE_NAME

# Create keychain profile
echo ""
echo "🔑 Creating keychain profile for notarytool..."
xcrun notarytool store-credentials "notarytool-password" \
    --apple-id "$APPLE_ID" \
    --team-id "$TEAM_ID" \
    --password "$APP_SPECIFIC_PASSWORD"

if [ $? -eq 0 ]; then
    echo "✅ Keychain profile created successfully"
else
    echo "❌ Failed to create keychain profile"
    exit 1
fi

# Test the profile
echo ""
echo "🧪 Testing the keychain profile..."
if xcrun notarytool info --keychain-profile "notarytool-password" &> /dev/null; then
    echo "✅ Keychain profile test successful"
else
    echo "❌ Keychain profile test failed"
    exit 1
fi

# Update the build script with the certificate name
echo ""
echo "📝 Updating build script with your certificate..."
sed -i.bak "s/CERTIFICATE_NAME=.*/CERTIFICATE_NAME=\"$CERTIFICATE_NAME\"/" build_and_notarize_spm.sh

# Verify certificate exists
echo ""
echo "🔍 Verifying certificate exists..."
if security find-identity -v -p codesigning | grep -q "$TEAM_ID"; then
    echo "✅ Developer ID Application certificate found"
else
    echo "❌ Developer ID Application certificate not found"
    echo "   Make sure you have a valid Developer ID Application certificate"
    echo "   You can create one in your Apple Developer account"
    exit 1
fi

echo ""
echo "🎉 Setup complete! Here's what was configured:"
echo "=============================================="
echo "✅ Apple ID: $APPLE_ID"
echo "✅ Team ID: $TEAM_ID"
echo "✅ Certificate: $CERTIFICATE_NAME"
echo "✅ Keychain profile: notarytool-password"
echo "✅ ExportOptions.plist updated"
echo ""
echo "🚀 You can now run the notarization script:"
echo "   ./build_and_notarize_spm.sh"
echo ""
echo "📚 For more information, see:"
echo "   - BUILD_SCRIPTS.md"
echo "   - DISTRIBUTION_SETUP.md"
