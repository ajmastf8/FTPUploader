// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FTPSender",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "FTPSender",
            targets: ["FTPSender"]
        )
    ],
    dependencies: [
    ],
    targets: [
        .executableTarget(
            name: "FTPSender",
            dependencies: [],
            path: "Sources/FTPSender",
            resources: [
                .copy("Help"),
                .copy("FTPSender.storekit")
            ],
            cSettings: [
                // Import bridging header for Rust FFI
                .headerSearchPath("../../RustFTP")
            ],
            swiftSettings: [],
            linkerSettings: [
                // Link Rust static library
                .unsafeFlags([
                    "-L/Users/ajmast/Development/GitHub/FTPSender/RustFTP/target/release",
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
