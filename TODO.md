# FTP Downloader TODO - RAW File Handling Improvements

## 📸 RAW File Format Challenges

### Current Issues with .acr and Other RAW Files
- **Large File Sizes**: RAW files (ACR, CR2, NEF, ARW, etc.) are typically 20-50MB+ each
- **Binary Data**: Complex binary structures that may stress FTP connections
- **Active Writing**: Camera software may still be writing metadata/previews
- **Server Timeouts**: Large files can exceed FTP server connection timeouts
- **Transfer Interruptions**: Higher chance of network issues during long transfers

### Affected RAW Formats
- `.acr` - Adobe Camera Raw
- `.cr2` - Canon RAW
- `.nef` - Nikon RAW
- `.arw` - Sony RAW
- `.dng` - Adobe Digital Negative
- `.raf` - Fujifilm RAW
- `.orf` - Olympus RAW
- `.rw2` - Panasonic RAW

## 🚀 Enhancement Ideas

### 1. Smart RAW File Detection
```rust
// Add to file filtering logic
fn is_raw_file(filename: &str) -> bool {
    let raw_extensions = [".acr", ".cr2", ".nef", ".arw", ".dng", ".raf", ".orf", ".rw2"];
    let lower_filename = filename.to_lowercase();
    raw_extensions.iter().any(|ext| lower_filename.ends_with(ext))
}
```

### 2. Enhanced Stabilization for RAW Files
- **Longer Stabilization Periods**: Default 30-60s for RAW files vs 5-15s for regular files
- **Multiple Size Checks**: Verify file size stability multiple times
- **Metadata Completion Check**: Wait for sidecar files (.xmp, .xml) to appear
- **Progressive Timeout**: Exponentially increase timeout for larger files

### 3. Optimized Transfer Strategy for RAW Files
- **Reduced Concurrency**: Limit parallel connections when RAW files detected
- **Larger Buffer Sizes**: Use bigger transfer buffers for large binary files
- **Resume Capability**: Implement FTP RESUME for interrupted large file transfers
- **Integrity Verification**: MD5/SHA verification for completed RAW file transfers

### 4. RAW-Specific Configuration Options
```rust
#[derive(Debug, Deserialize, Clone)]
struct RawFileConfig {
    pub enabled: bool,
    pub stabilization_multiplier: f64,  // Multiply standard stabilization by this factor
    pub max_parallel_raw_downloads: usize,  // Limit concurrent RAW downloads
    pub enable_resume: bool,  // Enable resume for interrupted transfers
    pub verify_integrity: bool,  // Enable post-download verification
    pub wait_for_sidecar_files: bool,  // Wait for .xmp/.xml files
    pub sidecar_timeout: u64,  // Seconds to wait for sidecar files
}
```

### 5. Intelligent File Grouping
- **Detect Photo Sessions**: Group related files (RAW + JPEG + sidecar)
- **Batch Processing**: Download complete photo sets together
- **Priority Handling**: Process smaller files first, queue RAW files
- **Session Completion**: Wait for shooting session to complete before processing

## 🔧 Implementation Strategy

### Phase 1: Detection and Classification
- [ ] Add RAW file extension detection
- [ ] Implement file size-based classification (Small/Medium/Large/XLarge)
- [ ] Create file type metadata in download queue
- [ ] Add RAW file statistics to session reports

### Phase 2: Enhanced Stabilization
- [ ] Implement size-based stabilization timeouts
- [ ] Add progressive timeout algorithm for large files
- [ ] Create sidecar file detection and waiting
- [ ] Implement multiple stability verification rounds

### Phase 3: Optimized Transfer Logic
- [ ] Add file-size-aware connection pooling
- [ ] Implement transfer resume capability
- [ ] Create integrity verification system
- [ ] Add progress reporting for large file transfers

### Phase 4: Advanced Configuration
- [ ] Add RAW-specific settings to FTP config
- [ ] Create UI controls for RAW file handling
- [ ] Implement automatic detection and optimization
- [ ] Add performance tuning recommendations

## 🎯 Smart Algorithm Concepts

### Adaptive Stabilization Algorithm
```rust
fn calculate_stabilization_timeout(file_size: u64, file_type: FileType) -> Duration {
    let base_timeout = match file_type {
        FileType::Raw => 30,      // 30s base for RAW files
        FileType::Large => 15,    // 15s for large non-RAW
        FileType::Standard => 5,  // 5s for standard files
    };

    // Scale by file size (add 1s per 10MB)
    let size_factor = (file_size / (10 * 1024 * 1024)).max(1);
    Duration::from_secs(base_timeout * size_factor)
}
```

### Session-Aware Processing
```rust
// Detect if files belong to the same photo session
fn detect_photo_session(files: &[FileInfo]) -> Vec<PhotoSession> {
    // Group by timestamp proximity and filename patterns
    // Wait for session completion before processing
    // Handle burst mode and bracketed shots
}
```

### Progressive Download Strategy
```rust
// Download order optimization
fn optimize_download_order(files: &[FileInfo]) -> Vec<FileInfo> {
    files.sort_by(|a, b| {
        // Priority: Small files first, then medium, then RAW files
        // Within same size class: alphabetical order
        // Special handling for related files (RAW + JPEG pairs)
    });
}
```

## 📊 Monitoring and Analytics

### RAW File Metrics
- [ ] Track RAW file download success rates
- [ ] Monitor average download times by file size
- [ ] Measure stabilization accuracy for RAW files
- [ ] Report server performance with large files

### Performance Insights
- [ ] Files/minute rate for different file types
- [ ] Bandwidth utilization during RAW transfers
- [ ] Connection stability metrics for large files
- [ ] Optimal aggressiveness levels for RAW workflows

## 🔮 Future Enhancements

### Advanced RAW Workflow Integration
- [ ] **Lightroom Integration**: Detect when Lightroom finishes importing
- [ ] **Capture One Support**: Handle Capture One session detection
- [ ] **Tethered Shooting**: Special handling for live tethered capture
- [ ] **Backup Verification**: Ensure RAW files are completely transferred

### Cloud Storage Optimization
- [ ] **Direct Cloud Upload**: Option to upload RAW files directly to cloud storage
- [ ] **Compression Detection**: Detect and handle compressed RAW formats
- [ ] **Metadata Preservation**: Ensure all EXIF/metadata is preserved
- [ ] **Folder Structure**: Maintain photographer's folder organization

### Professional Photography Features
- [ ] **Multi-Camera Support**: Handle multiple camera streams simultaneously
- [ ] **Event Mode**: Special handling for event/wedding photography workflows
- [ ] **Client Delivery**: Automatic sorting for client delivery workflows
- [ ] **Backup Redundancy**: Multiple destination support for critical shoots

## 💡 Configuration UI Enhancements

### RAW File Settings Panel
- Toggle for enhanced RAW file handling
- Stabilization timeout multiplier slider
- Max concurrent RAW downloads setting
- Resume capability enable/disable
- Integrity verification options

### Workflow Presets
- **Event Photography**: High-speed, multiple cameras, immediate transfer
- **Studio Work**: Quality focus, integrity verification, organized delivery
- **Landscape/Travel**: Bandwidth-conscious, smart grouping, cloud backup
- **Sports/Action**: Burst handling, priority for key shots, rapid preview

## 🚨 Risk Mitigation

### Large File Transfer Risks
- **Connection Timeouts**: Implement progressive timeout increases
- **Server Overload**: Automatic aggressiveness reduction for large files
- **Disk Space**: Pre-flight disk space checking for large transfers
- **Network Interruption**: Resume capability and retry logic

### Data Integrity Concerns
- **Corruption Detection**: Hash verification for critical files
- **Partial Transfers**: Never delete source until verification complete
- **Backup Validation**: Verify file accessibility after transfer
- **Metadata Preservation**: Ensure creation times and EXIF data intact

---

## 📝 Notes

### Current Behavior Analysis
The existing Rust downloader treats all files equally, which works well for most files but may not be optimal for large RAW files. The stabilization algorithm uses a fixed timeout regardless of file size or type, which could cause issues with:

1. **Large files still being written** by camera software
2. **Network timeouts** during long transfers
3. **Server connection limits** being exceeded
4. **Inefficient bandwidth usage** with high aggressiveness on large files

### Implementation Priority
1. **High Priority**: RAW file detection and enhanced stabilization
2. **Medium Priority**: Transfer optimization and resume capability
3. **Low Priority**: Advanced workflow integration and UI enhancements

### Testing Requirements
- Test with various RAW formats and sizes
- Validate performance with different aggressiveness levels
- Ensure compatibility with major photography software
- Verify behavior with concurrent RAW and JPEG transfers