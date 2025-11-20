# Archived Rust Files

This directory contains legacy Rust files that are no longer needed after the migration to library-only FFI integration.

## Files Archived

### `main.rs.deprecated` and `main.rs.backup`
- **Original Purpose**: Standalone Rust binary FTP application
- **Why Deprecated**: The project now uses Swift as the main application with Rust providing a static library via FFI (Foreign Function Interface). The standalone binary approach was replaced by `lib.rs` which exports C-compatible functions for Swift to call.
- **Archived Date**: 2025-11-10

### `build.rs.deprecated`
- **Original Purpose**: Cargo build script that embedded Info.plist into the Rust binary for macOS App Store compliance
- **Why Deprecated**: Only needed for binary targets (using `rustc-link-arg-bins`). Since we now only build a library target, this build script is unnecessary and was causing build errors.
- **Archived Date**: 2025-11-10

## Current Architecture

The project now uses:
- **`lib.rs`**: Main Rust library with FFI exports
- **`ftp_engine.rs`**: Core FTP engine logic
- **`db.rs`**: SQLite database for file hash tracking

The Swift app links statically to the Rust library and calls its functions through the FFI bridge defined in `SimpleRustFTPService_FFI.swift`.

## If You Need to Restore

These files are kept for reference. If you need to restore the standalone binary capability:
1. Restore `main.rs` from one of the backup files
2. Add the binary target back to `Cargo.toml`:
   ```toml
   [[bin]]
   name = "rust_ftp"
   path = "src/main.rs"
   ```
3. Optionally restore `build.rs` if you need the plist embedding
