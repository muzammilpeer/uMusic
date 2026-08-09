// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "PlaybackRestoreProbe",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "PlaybackRestoreProbe", targets: ["PlaybackRestoreProbe"]),
    ],
    targets: [
        .target(name: "PlaybackRestoreProbe"),
        .testTarget(
            name: "PlaybackRestoreProbeTests",
            dependencies: ["PlaybackRestoreProbe"]
        ),
    ]
)

