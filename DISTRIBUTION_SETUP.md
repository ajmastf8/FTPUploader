# Distribution Setup Guide

This guide covers the steps needed to prepare FTP Downloader for code signing and notarization.

## Prerequisites

### 1. Apple Developer Account
- Enroll in the Apple Developer Program ($99/year)
- Get your Team ID from [developer.apple.com](https://developer.apple.com)

### 2. Certificates and Provisioning
- **For Direct Distribution (recommended):**
  - Developer ID Application certificate
  - Developer ID Installer certificate (for .pkg installers)
  
- **For App Store Distribution:**
  - Mac App Store certificate
  - Mac App Store provisioning profile

### 3. Required Tools
```bash
# Install Xcode Command Line Tools
xcode-select --install

# Install create-dmg for DMG creation (optional)
brew install create-dmg

# Install xcnotary for notarization (alternative to xcrun notarytool)
brew install akeru-inc/tap/xcnotary
```

## Setup Steps

### 1. Configure Your Bundle Identifier
Edit the following files to use your actual bundle identifier:
- `ExportOptions.plist` - Update `distributionBundleIdentifier`
- `Sources/FTPDownloader/Info.plist` - Ensure CFBundleIdentifier matches
- Xcode project settings

### 2. Set Up Notarization Credentials
```bash
# Store your App Store Connect credentials
xcrun notarytool store-credentials "notarytool-password" \
    --apple-id "your-apple-id@example.com" \
    --team-id "YOUR_TEAM_ID" \
    --password "your-app-specific-password"
```

### 3. Update Build Scripts
Edit `build_and_notarize.sh` and replace:
- `YOUR_TEAM_ID_HERE` with your actual Team ID
- `com.yourcompany.ftpdownloader` with your bundle identifier
- `Your Name` with your developer certificate name

### 4. Configure Xcode Project
In Xcode:
1. Set your Team in Signing & Capabilities
2. Choose your Bundle Identifier
3. Enable "Automatically manage signing" or configure manual signing
4. Add the entitlements file to your target
5. Set the Info.plist file for your target

## Build and Distribution

### For Testing (Development)
```bash
./build_app.sh
```

### For Distribution (Signed & Notarized)
```bash
./build_and_notarize.sh
```

## Distribution Methods

### 1. Direct Distribution (Recommended)
- Use Developer ID certificates
- Distribute outside the App Store
- Users can download directly from your website
- Requires notarization for macOS 10.15+

### 2. App Store Distribution
- Use App Store certificates
- Submit through App Store Connect
- Apple handles distribution
- More restrictive sandbox requirements

## Troubleshooting

### Common Issues

1. **Code signing fails:**
   - Verify certificates are installed in Keychain
   - Check Team ID and Bundle Identifier match
   - Ensure entitlements are properly configured

2. **Notarization fails:**
   - Check that all libraries are properly signed
   - Verify entitlements don't conflict
   - Review notarization logs for specific errors

3. **App won't run on other Macs:**
   - Ensure proper code signing
   - Verify notarization was successful
   - Check that all dependencies are included

### Debug Commands
```bash
# Check code signature
codesign --display --verbose=2 /path/to/your.app

# Verify signature
codesign --verify --verbose=2 /path/to/your.app

# Check Gatekeeper status
spctl --assess --type execute --verbose /path/to/your.app

# View notarization history
xcrun notarytool history --keychain-profile "notarytool-password"
```

## Security Considerations

### Hardened Runtime
- Enable Hardened Runtime for notarization
- Use minimal entitlements
- Avoid `com.apple.security.cs.disable-library-validation` if possible

### Sandboxing
- Required for App Store
- Optional for direct distribution
- Limits file system and network access
- Configure entitlements carefully for FTP functionality

## Additional Resources

- [Apple Code Signing Guide](https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/)
- [Notarizing macOS Software](https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution)
- [App Sandbox Design Guide](https://developer.apple.com/library/archive/documentation/Security/Conceptual/AppSandboxDesignGuide/)
