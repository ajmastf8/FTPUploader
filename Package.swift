// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FTPUploader",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "FTPUploader",
            targets: ["FTPUploader"]
        )
    ],
    dependencies: [
    ],
    targets: [
        .executableTarget(
            name: "FTPUploader",
            dependencies: [],
            path: "Sources/FTPUploader",
            resources: [
                .copy("Help"),
                .copy("FTPUploader.storekit")
            ],
            cSettings: [
                // Import bridging header for Rust FFI
                .headerSearchPath("../../RustFTP")
            ],
            swiftSettings: [],
            linkerSettings: [
                // Link Rust static library
                .unsafeFlags([
                    "-L/Users/ajmast/Development/GitHub/FTPUploader/RustFTP/target/release",
                    "-lrust_ftp",
                    // Required system frameworks for Rust dependencies
                    "-framework", "Security",
                    "-framework", "SystemConfiguration",
                    "-lresolv",
                    "-lc++"
                ])
            ]
        )
    ]
)
