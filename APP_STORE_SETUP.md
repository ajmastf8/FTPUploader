# FTP Downloader - App Store Setup Guide

## Overview
This guide covers the complete setup for submitting FTP Downloader to the Mac App Store with a 3-day trial and $24.99 in-app purchase model.

## 1. App Store Connect Configuration

### Create App Record
1. Go to [App Store Connect](https://appstoreconnect.apple.com)
2. Click **My Apps** → **+** → **New App**
3. Fill in:
   - **Platform**: macOS
   - **Name**: FTP Downloader
   - **Primary Language**: English (U.S.)
   - **Bundle ID**: `com.roningroupinc.FTPDownloader`
   - **SKU**: FTPDownloader (or unique identifier)

### App Information
- **Category**: Utilities
- **Subtitle**: Automated FTP file downloading
- **Description**: (See APP_DESCRIPTION.md for full description)

## 2. In-App Purchase Setup

### Create In-App Purchase
1. In App Store Connect, go to your app → **In-App Purchases**
2. Click **+** to create new in-app purchase
3. Select **Non-Consumable**
4. Fill in:
   - **Reference Name**: Full Version
   - **Product ID**: `com.roningroupinc.FTPDownloader`
   - **Price**: $24.99 (Tier 25)
   - **Display Name**: FTP Downloader Full Version
   - **Description**: Unlock the full version of FTP Downloader with unlimited access to all features including automated FTP file downloading, intelligent stabilization monitoring, and concurrent processing.

### Review Information
- Add screenshot showing the purchase screen
- Note: This unlocks all features after 3-day trial

## 3. Apple Developer Portal Setup

### App ID Configuration
1. Go to [developer.apple.com](https://developer.apple.com/account)
2. Navigate to **Certificates, Identifiers & Profiles**
3. Select **Identifiers** → **App IDs**
4. Click **+** to register new App ID (if not exists):
   - **Description**: FTP Downloader
   - **Bundle ID**: `com.roningroupinc.FTPDownloader`
   - **Capabilities** (enable these):
     - ✅ App Sandbox
     - ✅ In-App Purchase
     - ✅ Network Extensions (or ensure network access)

### Provisioning Profile
1. In **Profiles**, create new profile:
   - **Type**: Mac App Store
   - **App ID**: com.roningroupinc.FTPDownloader
   - **Certificate**: Apple Distribution certificate
2. Download and save as: `FTPDownloader_App_Store.provisionprofile`
3. Place in project root directory

### Certificates Required
- ✅ **Apple Distribution**: For signing the app
- ✅ **3rd Party Mac Developer Installer**: For signing the .pkg

## 4. Build & Submit

### Build for App Store
```bash
./build_appstore.sh
```

This creates:
- `build/appstore/FTPDownloader.app` - Signed app bundle
- `build/appstore/FTPDownloader-signed.pkg` - Ready for upload

### Upload to App Store
**Option 1: Transporter App**
1. Open Transporter (from Mac App Store)
2. Drag `build/appstore/FTPDownloader-signed.pkg`
3. Click **Deliver**

**Option 2: Command Line**
```bash
xcrun altool --upload-package build/appstore/FTPDownloader-signed.pkg \
  --type macos \
  --apple-id YOUR_APPLE_ID@email.com \
  --password YOUR_APP_SPECIFIC_PASSWORD
```

## 5. Trial & Purchase System

### How It Works
1. **First Launch**: Trial starts automatically (3 days)
2. **During Trial**: Banner shows days remaining
3. **Trial Expired**: Purchase sheet appears
4. **After Purchase**: Full access, no restrictions

### Testing StoreKit
1. Open `FTPDownloader.storekit` in Xcode
2. Run app in debug mode
3. Test purchase flow (won't charge real money)
4. Test restore purchases

### Build Types
- **Development** (`swift build`): Shows trial UI, no expiration
- **App Store** (`./build_appstore.sh`): 3-day trial + purchase
- **Notarized**: Not applicable for App Store

## 6. App Review Information

### Demo Account (if needed)
Not required - trial allows full testing

### Review Notes
```
FTP Downloader offers a 3-day free trial. After the trial expires,
users can purchase the full version for $24.99 (one-time payment).

The app provides:
- Automated FTP file downloading
- Intelligent file stabilization monitoring
- Concurrent processing for maximum speed
- Connection pooling and retry logic

No server-side components or external services required.
```

### Privacy Information
- **Does your app use encryption?**: No
  - ITSAppUsesNonExemptEncryption is set to false
- **Data Collection**: None
- **Third-Party SDK**: None

## 7. Pre-Submission Checklist

- [ ] App ID created with correct bundle identifier
- [ ] In-App Purchase product created ($24.99)
- [ ] Provisioning profile downloaded and placed in project root
- [ ] App built with `./build_appstore.sh` successfully
- [ ] Code signing verified (no errors)
- [ ] Package created and signed
- [ ] Screenshots prepared (minimum 3)
- [ ] App description written
- [ ] Privacy policy URL (if required)
- [ ] Support URL set up
- [ ] Keywords chosen (max 100 characters)
- [ ] App icon (512x512 and 1024x1024)

## 8. Files Reference

### Created Configuration Files
- `FTPDownloader.entitlements` - Main app entitlements
- `HelperTool.entitlements` - Rust binary entitlements
- `FTPDownloader.storekit` - StoreKit testing configuration
- `exportOptionsAppStore.plist` - Export options
- `build_appstore.sh` - App Store build script

### Swift Files
- `StoreKitManager.swift` - Purchase logic
- `PurchaseView.swift` - Purchase UI
- `BuildConfiguration.swift` - Build type detection
- `ReceiptValidator.swift` - Receipt validation

### Bundle Identifier
`com.roningroupinc.FTPDownloader`

### Product ID
`com.roningroupinc.FTPDownloader`

## 9. Support & Updates

### Version Updates
1. Update version in `build_appstore.sh` (CFBundleShortVersionString)
2. Increment build number automatically
3. Rebuild and resubmit

### Price Changes
1. Go to App Store Connect
2. Select app → Pricing and Availability
3. Update in-app purchase price tier

## 10. Troubleshooting

### Common Issues

**"Invalid Provisioning Profile"**
- Ensure profile matches bundle ID exactly
- Check profile hasn't expired
- Re-download from developer portal

**"Code signing failed"**
- Verify certificates are installed in Keychain
- Check `security find-identity -v -p codesigning`
- Ensure using "Apple Distribution" certificate

**"Product not found"**
- Product must be created in App Store Connect first
- Wait 24 hours after creating product
- Ensure product ID matches exactly

**"Receipt not found"**
- Normal in development - receipt only exists after App Store download
- Use StoreKit testing for local testing

### Testing Checklist
- [ ] Trial starts correctly on first launch
- [ ] Days remaining counts down properly
- [ ] Purchase sheet appears when trial expires
- [ ] Purchase completes successfully
- [ ] Restore purchases works
- [ ] App functions fully after purchase
- [ ] No crashes or errors in StoreKit flow

## Next Steps
1. Create App Store listing in App Store Connect
2. Download provisioning profile
3. Run `./build_appstore.sh`
4. Upload via Transporter
5. Submit for review
