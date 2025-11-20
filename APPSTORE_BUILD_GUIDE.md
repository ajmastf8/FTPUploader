# App Store Build Guide

## Quick Reference

```bash
# Build beta (auto-increments beta number)
./build_appstore.sh -beta

# Increment version and build for production
./build_appstore.sh -inc

# Build current version for production
./build_appstore.sh
```

## Your Versioning Strategy

```
Current Version: 1.0.1

Beta Testing:
  ./build_appstore.sh -beta  →  1.0.1 (build 20251028.143000)
  ./build_appstore.sh -beta  →  1.0.1 (build 20251028.150000)
  ./build_appstore.sh -beta  →  1.0.1 (build 20251029.091500)

Production Release:
  ./build_appstore.sh -inc   →  1.0.2 (build 20251029.120000)
```

**Note:** Build numbers use timestamps (YYYYMMDD.HHMMSS) to ensure they always increase, satisfying App Store Connect requirements.

## How It Works

### Beta Builds (`./build_appstore.sh -beta`)

1. **Looks at** `build/appstore/beta/` directory
2. **Finds** highest beta number (e.g., `FTPDownloader-1.0.1-beta2.app`)
3. **Increments** to next beta (creates `FTPDownloader-1.0.1-beta3.app`)
4. **Uses** build number `1.0.1.3` (version stays at `1.0.1`)
5. **Outputs to** `build/appstore/beta/`

**Files Created:**
```
build/appstore/beta/
├── FTPDownloader-1.0.1-beta3.app
├── FTPDownloader-1.0.1-beta3.pkg
└── FTPDownloader-1.0.1-beta3-signed.pkg  ← Upload this to TestFlight

build/appstore/beta/old/
├── FTPDownloader-1.0.1-beta2.app         (previous beta)
└── FTPDownloader-1.0.1-beta1.app         (2 betas back)
```

### Version Increment (`./build_appstore.sh -inc`)

1. **Reads** current version from `Sources/FTPDownloader/Info.plist`
2. **Increments** patch version (1.0.1 → 1.0.2)
3. **Updates** Info.plist with new version
4. **Uses** timestamp build number (e.g., `20251029120000`)
5. **Outputs to** `build/appstore/release/`

**Files Created:**
```
build/appstore/release/
├── FTPDownloader-1.0.2.app
├── FTPDownloader-1.0.2.pkg
└── FTPDownloader-1.0.2-signed.pkg  ← Upload this to App Store

build/appstore/release/old/
├── FTPDownloader-1.0.1.app         (previous release)
└── (keeps last 2 releases)
```

### Production Build (`./build_appstore.sh`)

1. **Reads** current version from Info.plist (no changes)
2. **Uses** timestamp build number
3. **Outputs to** `build/appstore/release/`

## Example Workflow

### Week 1-3: Develop New Features
```bash
# Make code changes, test locally with ./build.sh
```

### Week 4: Start Beta Testing
```bash
./build_appstore.sh -beta
# Creates: 1.0.1 (build 1.0.1.1)
# Upload FTPDownloader-1.0.1-beta1-signed.pkg to TestFlight
```

### Week 5: Fix Bugs & Iterate
```bash
./build_appstore.sh -beta
# Creates: 1.0.1 (build 1.0.1.2)
# Upload FTPDownloader-1.0.1-beta2-signed.pkg to TestFlight

./build_appstore.sh -beta
# Creates: 1.0.1 (build 1.0.1.3)
# Upload FTPDownloader-1.0.1-beta3-signed.pkg to TestFlight
```

### Week 6: Ready for Production
```bash
./build_appstore.sh -inc
# Creates: 1.0.2 (build 1.0.2.0)
# Upload FTPDownloader-1.0.2-signed.pkg to App Store
# Submit for review
```

## Directory Structure

```
build/appstore/
├── release/
│   ├── FTPDownloader-1.0.2.app              (current release)
│   ├── FTPDownloader-1.0.2.pkg
│   ├── FTPDownloader-1.0.2-signed.pkg       ← Upload to App Store
│   └── old/
│       ├── FTPDownloader-1.0.1.app          (previous release)
│       ├── FTPDownloader-1.0.1.pkg
│       └── FTPDownloader-1.0.1-signed.pkg
└── beta/
    ├── FTPDownloader-1.0.1-beta3.app        (current beta)
    ├── FTPDownloader-1.0.1-beta3.pkg
    ├── FTPDownloader-1.0.1-beta3-signed.pkg ← Upload to TestFlight
    └── old/
        ├── FTPDownloader-1.0.1-beta2.app    (kept - 1 back)
        ├── FTPDownloader-1.0.1-beta2.pkg
        ├── FTPDownloader-1.0.1-beta2-signed.pkg
        ├── FTPDownloader-1.0.1-beta1.app    (kept - 2 back)
        ├── FTPDownloader-1.0.1-beta1.pkg
        └── FTPDownloader-1.0.1-beta1-signed.pkg
```

**Auto-cleanup:** The script automatically:
- Keeps current build in main directory
- Moves previous builds to `old/` subdirectory
- Keeps last 2 builds in `old/`, deletes older ones

## Key Benefits

✅ **No manual tracking** - Script automatically finds and increments beta numbers
✅ **Version in filename** - Easy to identify which build is which
✅ **Separate directories** - Betas don't clutter production builds
✅ **Clean versioning** - Version stays at 1.0.1 during testing, only bumps for release
✅ **Preserves history** - Old builds stay in directories for reference

## Upload to App Store Connect

### For Beta (TestFlight)
1. Run: `./build_appstore.sh -beta`
2. Open **Transporter** app
3. Drag: `build/appstore/beta/FTPDownloader-1.0.1-betaX-signed.pkg`
4. Click **Deliver**
5. In **App Store Connect** → **TestFlight** tab
6. Select build `1.0.1.X`
7. Add testers and distribute

### For Production
1. Run: `./build_appstore.sh -inc` (increments version)
2. Open **Transporter** app
3. Drag: `build/appstore/FTPDownloader-1.0.2-signed.pkg`
4. Click **Deliver**
5. In **App Store Connect** → **App Store** tab
6. Submit for review

## FAQs

**Q: How does the script know which beta number to use?**
A: It scans `build/appstore/beta/` for existing files like `FTPDownloader-1.0.1-beta2.app`, finds the highest number (2), and increments (creates beta3).

**Q: What if I delete the beta directory?**
A: It starts over at beta1.

**Q: Can I build beta 1 again?**
A: Yes, just delete the beta directory or manually delete files with higher beta numbers.

**Q: What if I want to skip to version 1.1.0?**
A: Manually edit `Sources/FTPDownloader/Info.plist` to set version to 1.0.9, then run `./build_appstore.sh -inc` to go to 1.1.0.

**Q: Do I have to upload every beta?**
A: No! Build as many betas as you want locally. Only upload the ones you want testers to see.

**Q: What's the difference between the three .pkg files?**
A:
- `.app` = The application bundle
- `.pkg` = Unsigned installer package
- `-signed.pkg` = Signed installer (THIS is what you upload)

## Version History Tracking

The script automatically tracks versions in filenames:

```
Current: 1.0.1
Betas:   1.0.1 (builds 1.0.1.1, 1.0.1.2, 1.0.1.3, ...)
Release: 1.0.2 (build 1.0.2.0)
Betas:   1.0.2 (builds 1.0.2.1, 1.0.2.2, ...)
Release: 1.0.3 (build 1.0.3.0)
```

All builds are preserved in their directories with version numbers in filenames!
