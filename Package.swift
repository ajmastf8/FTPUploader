// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FTPDownloader",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "FTPDownloader",
            targets: ["FTPDownloader"]
        )
    ],
    dependencies: [
    ],
    targets: [
        .executableTarget(
            name: "FTPDownloader",
            dependencies: [],
            path: "Sources/FTPDownloader",
            resources: [
                .copy("Help"),
                .copy("FTPDownloader.storekit")
            ],
            cSettings: [
                // Import bridging header for Rust FFI
                .headerSearchPath("../../RustFTP")
            ],
            swiftSettings: [],
            linkerSettings: [
                // Link Rust static library
                .unsafeFlags([
                    "-L/Users/ajmast/Development/GitHub/FTPDownloader/RustFTP/target/release",
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
