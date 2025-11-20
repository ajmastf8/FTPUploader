# Notarization Setup Guide for FTP Downloader

This guide will walk you through setting up notarization for your FTP Downloader app without using Xcode's GUI tools.

## 🚀 Quick Start

1. **Run the setup script:**
   ```bash
   ./setup_notarization.sh
   ```

2. **Verify your setup:**
   ```bash
   ./verify_setup.sh
   ```

3. **Build and notarize:**
   ```bash
   ./build_and_notarize.sh
   ```

## 📋 Prerequisites

### 1. Apple Developer Account
- **Paid Apple Developer Program membership** ($99/year)
- **Developer ID Application certificate** (for distribution outside App Store)

### 2. Required Tools
- **Xcode Command Line Tools** (automatically installed by setup script)
- **Rust toolchain** (automatically installed by setup script)
- **Homebrew** (for installing create-dmg)
- **create-dmg** (automatically installed by setup script)

## 🔑 What You'll Need to Provide

### 1. Apple ID
- Your Apple ID email address
- Used for notarization authentication

### 2. Team ID
- Your Apple Developer Team ID
- Found in your Apple Developer account
- Default: `6X7BH7FLQ8` (already configured)

### 3. App-Specific Password
- **NOT your regular Apple ID password**
- Generate at [appleid.apple.com](https://appleid.apple.com)
- Go to "Sign-in and Security" → "App-Specific Passwords"
- Create a new password with label "FTP Downloader Notarization"

### 4. Developer ID Application Certificate
- Must be installed in your Keychain
- Format: `Developer ID Application: [Your Name] ([Team ID])`
- Find it by running: `security find-identity -v -p codesigning`

## 🛠️ Setup Process

### Step 1: Run Setup Script
```bash
./setup_notarization.sh
```

The script will:
- ✅ Check and install required tools
- ✅ Prompt for your credentials
- ✅ Create the notarytool keychain profile
- ✅ Update configuration files
- ✅ Verify your certificate

### Step 2: Verify Setup
```bash
./verify_setup.sh
```

This confirms everything is working:
- ✅ All tools are installed
- ✅ Credentials are configured
- ✅ Certificates are available
- ✅ Project configuration is valid
- ✅ Build process works

### Step 3: Build and Notarize
```bash
./build_and_notarize.sh
```

This will:
1. 🦀 Build the Rust FTP library
2. 🔨 Build the macOS app with Xcode
3. 📦 Export and sign the app
4. 🍎 Submit for notarization
5. 📎 Staple the notarization ticket
6. 💿 Create a distributable DMG

## 🔍 Troubleshooting

### Common Issues

#### 1. "Xcode Command Line Tools not found"
```bash
xcode-select --install
```

#### 2. "No Developer ID Application certificates found"
- Go to [developer.apple.com](https://developer.apple.com)
- Certificates → Identifiers → Certificates
- Create a new "Developer ID Application" certificate
- Download and install it in Keychain Access

#### 3. "Keychain profile test failed"
- Check your app-specific password
- Ensure you're using the correct Team ID
- Try recreating the profile:
  ```bash
  xcrun notarytool delete-credentials "notarytool-password"
  ./setup_notarization.sh
  ```

#### 4. "create-dmg not found"
```bash
brew install create-dmg
```

#### 5. "Rust not found"
```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source ~/.cargo/env
```

### Manual Certificate Installation

If the automatic setup fails:

1. **Download certificate** from Apple Developer portal
2. **Double-click** the `.cer` file
3. **Add to Keychain** when prompted
4. **Trust the certificate** in Keychain Access
5. **Run setup again**

## 📱 Notarization Process

### What Happens During Notarization

1. **Submission**: App is uploaded to Apple's servers
2. **Scanning**: Apple scans for malware and policy violations
3. **Review**: Automated and manual review process
4. **Approval**: Notarization ticket is generated
5. **Stapling**: Ticket is attached to your app

### Notarization Requirements

- ✅ No malware or suspicious code
- ✅ Proper code signing
- ✅ Valid Developer ID certificate
- ✅ Follows Apple's security guidelines
- ✅ No unsigned or invalid code

## 🎯 Distribution

### After Successful Notarization

Your app will:
- ✅ Pass Gatekeeper checks on other Macs
- ✅ Install without security warnings
- ✅ Be trusted by macOS security systems
- ✅ Work on all supported macOS versions

### Distribution Methods

1. **Direct download** from your website
2. **DMG file** (created automatically)
3. **ZIP archive** (created automatically)
4. **Package managers** (Homebrew, etc.)

## 🔒 Security Best Practices

### Code Signing
- Always sign with Developer ID Application certificate
- Include all dependencies in the signature
- Verify signatures before distribution

### Notarization
- Notarize every release
- Keep notarization tickets
- Monitor Apple's security requirements

### Distribution
- Host files securely (HTTPS)
- Verify file integrity (checksums)
- Keep old versions for rollback

## 📚 Additional Resources

- [Apple Developer Documentation](https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution)
- [Code Signing Guide](https://developer.apple.com/support/code-signing/)
- [Notarization Troubleshooting](https://developer.apple.com/help/app-store-connect/notarize-macos-software)

## 🆘 Getting Help

If you encounter issues:

1. **Check the logs** in the build output
2. **Run verification script** to identify problems
3. **Check Apple Developer status** for your account
4. **Verify certificate expiration** dates
5. **Ensure all tools are up to date**

## 🎉 Success!

Once everything is set up, you can:
- Build and notarize with a single command
- Distribute your app securely
- Pass all macOS security checks
- Focus on development, not distribution setup

---

**Remember**: Notarization is required for all macOS software distributed outside the App Store. This setup ensures your app meets Apple's security requirements and provides a smooth user experience.
