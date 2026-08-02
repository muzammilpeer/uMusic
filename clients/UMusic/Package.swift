// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "UMusicCore",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [.library(name: "UMusicCore", targets: ["UMusicCore"])],
    targets: [
        .target(
            name: "UMusicCore",
            path: "UMusic",
            exclude: [
                "AudioPlayer.swift", "KeychainStore.swift", "LibraryView.swift",
                "LibraryViewModel.swift", "OnboardingView.swift", "SessionStore.swift",
                "UMusicApp.swift", "DownloadPolicyMonitor.swift", "OfflineView.swift",
                "LocationContextService.swift", "HealthWorkoutService.swift", "WorkoutView.swift",
                "TextInputBehavior.swift", "ActivityDetectionService.swift",
            ],
            sources: [
                "APIClient.swift", "EventSyncService.swift", "Models.swift", "OfflineAPI.swift",
                "OfflineManager.swift", "OfflineModels.swift", "QueueStore.swift",
                "WorkoutAPI.swift", "WorkoutModels.swift",
            ]
        ),
        .testTarget(name: "UMusicCoreTests", dependencies: ["UMusicCore"]),
    ],
    swiftLanguageModes: [.v5]
)
