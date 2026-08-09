// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "XCFrameworkResourceProbe",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "UMusicCoreProbe", type: .static, targets: ["UMusicCoreProbe"]),
        .library(name: "UMusicImportClientProbe", type: .static, targets: ["UMusicImportClientProbe"]),
    ],
    targets: [
        .target(
            name: "UMusicCoreProbe",
            resources: [.process("Resources")]
        ),
        .target(name: "UMusicImportClientProbe"),
        .testTarget(
            name: "FrameworkBoundaryTests",
            dependencies: ["UMusicCoreProbe", "UMusicImportClientProbe"]
        ),
    ]
)

