# App Store Entitlement Configuration

This document describes the entitlement configuration required for submitting FTP Downloader to the Mac App Store with the embedded Rust binary.

## Summary

The app has been configured with proper entitlements for App Store submission:
- **App Sandbox**: Enabled (required for Mac App Store)
- **Rust Binary**: Signed with appropriate entitlements for sandboxed execution
- **Network Access**: Configured for FTP connections
- **File Access**: Configured for user-selected files and downloads folder

## Entitlement Files

### 1. Main App Entitlements
**File**: `Sources/FTPDownloader/FTPDownloader.entitlements`

**Status**: ✅ App Sandbox enabled

```xml
<key>com.apple.security.app-sandbox</key>
<true/>

<key>com.apple.security.network.client</key>
<true/>

<key>com.apple.security.files.user-selected.read-write</key>
<true/>

<key>com.apple.security.files.downloads.read-write</key>
<true/>
```

### 2. Rust Binary Entitlements
**File**: `RustFTP.entitlements` (created)

**Purpose**: Allows the Rust binary to run within the sandboxed app environment

```xml
<key>com.apple.security.cs.allow-unsigned-executable-memory</key>
<true/>

<key>com.apple.security.cs.disable-library-validation</key>
<true/>

<key>com.apple.security.network.client</key>
<true/>

<key>com.apple.security.files.user-selected.read-write</key>
<true/>

<key>com.apple.security.files.downloads.read-write</key>
<true/>

<key>com.apple.security.inherit</key>
<true/>
```

## Code Signing Process

### Development Builds

For local development and testing (already applied):
```bash
codesign --force --sign - \
         --entitlements RustFTP.entitlements \
         build/dev/FTPDownloader.app/Contents/Resources/rust_ftp
```

### App Store Distribution

The `build_notarized.sh` script now includes proper entitlement configuration.

For reference, the signing process is:

1. **Sign the Rust binary** with Developer ID and entitlements:
```bash
codesign --force \
         --sign "Developer ID Application: Ronin Group Inc. (6X7BH7FLQ8)" \
         --entitlements RustFTP.entitlements \
         --options runtime \
         build/dist/FTPDownloader.app/Contents/Resources/rust_ftp
```

2. **Sign the main app bundle** with proper provisioning:
```bash
codesign --force \
         --sign "Developer ID Application: Ronin Group Inc. (6X7BH7FLQ8)" \
         --entitlements Sources/FTPDownloader/FTPDownloader.entitlements \
         --options runtime \
         build/dist/FTPDownloader.app
```

3. **Notarize the app** for Gatekeeper:
```bash
xcrun notarytool submit FTPDownloader.app.zip \
         --apple-id "your-apple-id" \
         --team-id "6X7BH7FLQ8" \
         --wait
```

4. **Staple the notarization ticket**:
```bash
xcrun stapler staple build/dist/FTPDownloader.app
```

## Verification Steps

### 1. Verify Code Signature
```bash
codesign --display --verbose=4 build/dev/FTPDownloader.app/Contents/Resources/rust_ftp
codesign --verify --verbose=4 build/dev/FTPDownloader.app/Contents/Resources/rust_ftp
```

### 2. Verify Entitlements Applied
```bash
codesign --display --entitlements - build/dev/FTPDownloader.app/Contents/Resources/rust_ftp
```

### 3. Verify Gatekeeper Acceptance (Distribution builds only)
```bash
spctl --assess --type execute --verbose build/dist/FTPDownloader.app/Contents/Resources/rust_ftp
spctl --assess --type execute --verbose build/dist/FTPDownloader.app
```

### 4. Test Sandbox Behavior
```bash
# Test that the binary can execute within sandbox constraints
sandbox-exec -f /usr/share/sandbox/bsd.sb \
    build/dev/FTPDownloader.app/Contents/Resources/rust_ftp
```

## Important Notes

1. **Certificate Chain Issue**: During development, we encountered a certificate chain validation error with the Developer ID certificate. This is resolved by using ad-hoc signing (`--sign -`) for development builds.

2. **Production Signing**: For App Store submission, use the actual Developer ID certificate. The build_and_notarize_spm.sh script should be updated to include signing the Rust binary.

3. **Binary Location**: The Rust binary is located at:
   - Development: `build/dev/FTPDownloader.app/Contents/Resources/rust_ftp`
   - The build script correctly places it in the Resources folder

4. **Hardened Runtime**: The `--options runtime` flag enables Hardened Runtime, which is required for notarization.

5. **Inherited Entitlements**: The Rust binary includes `com.apple.security.inherit` to allow it to inherit permissions from the parent sandboxed app.

## Next Steps for App Store Submission

1. Update `build_and_notarize_spm.sh` to include Rust binary signing:
   - Add signing step for rust_ftp before signing the app bundle
   - Use the same Developer ID certificate as the main app
   - Apply RustFTP.entitlements

2. Test the fully signed and notarized build locally

3. Submit to App Store Connect for review

## Testing Status

✅ Rust FTP implementation verified working reliably across multiple sync cycles
✅ Entitlement files created and configured
✅ App Sandbox enabled
✅ Development signing applied and verified
⏳ Production signing pending (requires update to build_and_notarize_spm.sh)
⏳ Notarization pending
