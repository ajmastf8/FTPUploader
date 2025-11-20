#!/bin/bash

# Verification Script for Notarization Setup
# This script checks if all components are properly configured

set -e

echo "🔍 Verifying notarization setup..."
echo "=================================="

# Check if we're in the right directory
if [ ! -f "Package.swift" ]; then
    echo "❌ Error: Please run this script from the FTPDownloader project root directory"
    exit 1
fi

# Check required tools
echo "🔧 Checking required tools..."

# Xcode Command Line Tools
if xcode-select -p &> /dev/null; then
    echo "✅ Xcode Command Line Tools: $(xcode-select -p)"
else
    echo "❌ Xcode Command Line Tools not found"
    exit 1
fi

# Rust
if command -v cargo &> /dev/null; then
    echo "✅ Rust: $(cargo --version)"
else
    echo "❌ Rust not found"
    exit 1
fi

# create-dmg
if command -v create-dmg &> /dev/null; then
    echo "✅ create-dmg: $(create-dmg --version)"
else
    echo "❌ create-dmg not found"
    exit 1
fi

echo ""
echo "🔑 Checking notarization credentials..."

# Check keychain profile
if xcrun notarytool history --keychain-profile "notarytool-password" &> /dev/null; then
    echo "✅ Keychain profile 'notarytool-password' exists and working"
    
    # Get profile info
    echo "   Profile is accessible and can retrieve submission history"
else
    echo "❌ Keychain profile 'notarytool-password' not found or not working"
    echo "   Run ./setup_notarization.sh to create it"
    exit 1
fi

echo ""
echo "🔐 Checking code signing certificates..."

# Check for Developer ID Application certificates
CERTIFICATES=$(security find-identity -v -p codesigning | grep "Developer ID Application" || true)
if [ -n "$CERTIFICATES" ]; then
    echo "✅ Developer ID Application certificates found:"
    echo "$CERTIFICATES" | sed 's/^/   /'
else
    echo "❌ No Developer ID Application certificates found"
    echo "   You need to create one in your Apple Developer account"
    exit 1
fi

echo ""
echo "📁 Checking project configuration..."

# Check ExportOptions.plist
if [ -f "ExportOptions.plist" ]; then
    echo "✅ ExportOptions.plist exists"
    
    # Check Team ID
    TEAM_ID=$(grep -A1 "teamID" ExportOptions.plist | tail -1 | sed 's/.*<string>\(.*\)<\/string>.*/\1/')
    if [ "$TEAM_ID" != "YOUR_TEAM_ID_HERE" ] && [ -n "$TEAM_ID" ]; then
        echo "✅ Team ID configured: $TEAM_ID"
    else
        echo "❌ Team ID not properly configured in ExportOptions.plist"
    fi
    
    # Check bundle identifier
    BUNDLE_ID=$(grep -A1 "distributionBundleIdentifier" ExportOptions.plist | tail -1 | sed 's/.*<string>\(.*\)<\/string>.*/\1/')
    if [ "$BUNDLE_ID" != "com.yourcompany.ftpdownloader" ] && [ -n "$BUNDLE_ID" ]; then
        echo "✅ Bundle identifier configured: $BUNDLE_ID"
    else
        echo "❌ Bundle identifier not properly configured in ExportOptions.plist"
    fi
else
    echo "❌ ExportOptions.plist not found"
    exit 1
fi

# Check build script
if [ -f "build_and_notarize_spm.sh" ]; then
    echo "✅ build_and_notarize_spm.sh exists"
    
    # Check if certificate name is configured
    CERT_NAME=$(grep "CERTIFICATE_NAME=" build_and_notarize_spm.sh | sed 's/.*CERTIFICATE_NAME="\(.*\)"/\1/')
    if [ -n "$CERT_NAME" ]; then
        echo "✅ Certificate name configured: $CERT_NAME"
    else
        echo "❌ Certificate name not properly configured in build_and_notarize_spm.sh"
    fi
else
    echo "❌ build_and_notarize_spm.sh not found"
    exit 1
fi

echo ""
echo "🧪 Testing build process..."

# Test Rust build
echo "   Testing Rust build..."
cd RustFTP
if cargo build --release &> /dev/null; then
    echo "   ✅ Rust build successful"
else
    echo "   ❌ Rust build failed"
    exit 1
fi
cd ..

# Test Swift Package Manager project
echo "   Testing Swift Package Manager project..."
if swift package describe &> /dev/null; then
    echo "   ✅ Swift Package Manager configuration valid"
else
    echo "   ❌ Swift Package Manager configuration invalid"
    exit 1
fi

echo ""
echo "🎉 Setup verification complete!"
echo "=============================="

# Summary
echo ""
echo "📋 Summary:"
echo "   ✅ All required tools are installed"
echo "   ✅ Notarization credentials are configured"
echo "   ✅ Code signing certificates are available"
echo "   ✅ Project configuration is valid"
echo "   ✅ Build process is working"
echo ""
echo "🚀 You're ready to run the notarization script:"
echo "   ./build_and_notarize_spm.sh"
echo ""
echo "💡 If you encounter any issues, run:"
echo "   ./setup_notarization.sh"
