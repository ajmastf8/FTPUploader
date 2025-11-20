#!/bin/bash

# Rebuild and Launch Script for FTPDownloader
# This script rebuilds Rust, builds the Swift app, and launches it

set -e  # Exit on any error

echo "🚀 FTPDownloader Rebuild and Launch Script"
echo "=========================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}📋${NC} $1"
}

print_success() {
    echo -e "${GREEN}✅${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠️${NC} $1"
}

print_error() {
    echo -e "${RED}❌${NC} $1"
}

# Check if we're in the right directory
if [ ! -f "Package.swift" ] || [ ! -d "RustFTP" ]; then
    print_error "This script must be run from the FTPDownloader project root directory"
    exit 1
fi

print_status "Starting rebuild process..."

# Step 1: Rebuild Rust
print_status "Step 1: Rebuilding Rust binary..."
cd RustFTP
if cargo build --release; then
    print_success "Rust binary rebuilt successfully"
else
    print_error "Rust build failed"
    exit 1
fi
cd ..

# Step 2: Build Swift app
print_status "Step 2: Building Swift app..."
if ./build.sh; then
    print_success "Swift app built successfully"
else
    print_error "Swift app build failed"
    exit 1
fi

# Step 3: Launch the app
print_status "Step 3: Launching the app..."
if ./launch_app.sh; then
    print_success "App launched successfully"
else
    print_error "App launch failed"
    exit 1
fi

echo ""
print_success "🎉 Rebuild and launch completed successfully!"
echo ""
echo "The app should now be running with the updated Rust binary."
echo "Check the console output for any runtime logs or errors."
