// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VHSDigitizer",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "VHSDigitizer", targets: ["VHSDigitizerApp"])
    ],
    targets: [
        .executableTarget(
            name: "VHSDigitizerApp",
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("CoreVideo"),
                .linkedFramework("VideoToolbox"),
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI")
            ]
        )
    ]
)
