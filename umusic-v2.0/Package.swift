// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "UMusicV2",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "UMusicCore", type: .static, targets: ["UMusicCore"]),
        .library(name: "UMusicImportClient", type: .static, targets: ["UMusicImportClient"]),
        .library(name: "UMusicOffline", targets: ["UMusicOffline"]),
        .library(name: "UMusicShareExtensionUI", targets: ["UMusicShareExtensionUI"]),
        .library(name: "UMusicPresentation", targets: ["UMusicPresentation"]),
        .library(name: "UMusicInspector", targets: ["UMusicInspector"]),
        .library(name: "UMusicMigration", targets: ["UMusicMigration"]),
    ],
    targets: [
        .target(name: "UMusicDomain"),
        .target(name: "UMusicSupport"),
        .target(name: "UMusicData", dependencies: ["UMusicDomain", "UMusicSupport"]),
        .target(name: "UMusicNetworking", dependencies: ["UMusicDomain", "UMusicSupport"]),
        .target(name: "UMusicPlayback", dependencies: ["UMusicDomain", "UMusicSupport"]),
        .target(name: "UMusicOffline", dependencies: ["UMusicDomain", "UMusicSupport"]),
        .target(name: "UMusicContext", dependencies: ["UMusicDomain", "UMusicSupport"]),
        .target(name: "UMusicLearning", dependencies: ["UMusicDomain", "UMusicSupport", "UMusicML"]),
        .target(name: "UMusicML", dependencies: ["UMusicDomain", "UMusicSupport"]),
        .target(name: "UMusicTelemetry", dependencies: ["UMusicDomain", "UMusicSupport"]),
        .target(name: "UMusicSecurity", dependencies: ["UMusicDomain", "UMusicSupport"]),
        .target(
            name: "UMusicCore",
            dependencies: [
                "UMusicDomain", "UMusicSupport", "UMusicData", "UMusicNetworking",
                "UMusicPlayback", "UMusicOffline", "UMusicContext", "UMusicLearning", "UMusicML",
                "UMusicTelemetry", "UMusicSecurity",
            ],
            resources: [
                .process("Resources/resource-manifest.json"),
                .process("Resources/release-freeze.json"),
                .process("Resources/ranker-feature-manifest.json"),
                .process("Resources/ranker-trusted-keys.json"),
                .process("Resources/ranker-training-report.json"),
                .process("Resources/PrivacyInfo.xcprivacy"),
                .copy("Resources/UMusicRanker.mlmodelc"),
            ]
        ),
        .target(name: "UMusicImportClient", dependencies: ["UMusicSupport"]),
        .target(
            name: "UMusicShareExtensionUI",
            dependencies: ["UMusicImportClient"],
            path: "Apps/UMusicApp/Extensions/UMusicShareExtension",
            exclude: ["README.md", "UMusicShareExtension.entitlements"]
        ),
        .target(name: "UMusicInspector", dependencies: ["UMusicDomain", "UMusicSupport"]),
        .target(name: "UMusicMigration", dependencies: ["UMusicDomain", "UMusicSupport"]),
        .target(name: "UMusicPresentation", dependencies: ["UMusicCore"]),
        .testTarget(name: "UMusicCoreTests", dependencies: ["UMusicCore", "UMusicContext", "UMusicData", "UMusicDomain", "UMusicLearning", "UMusicML", "UMusicNetworking", "UMusicOffline", "UMusicSecurity", "UMusicSupport", "UMusicTelemetry"]),
        .testTarget(name: "ArchitectureTests", dependencies: ["UMusicCore"]),
        .testTarget(name: "UMusicPresentationTests", dependencies: ["UMusicPresentation"]),
        .testTarget(name: "UMusicImportClientTests", dependencies: ["UMusicImportClient"]),
        .testTarget(name: "UMusicInspectorTests", dependencies: ["UMusicInspector", "UMusicDomain"]),
        .testTarget(name: "UMusicMigrationTests", dependencies: ["UMusicMigration", "UMusicDomain"]),
    ]
)
