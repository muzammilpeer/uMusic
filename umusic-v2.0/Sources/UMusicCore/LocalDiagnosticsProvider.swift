import Foundation
import UMusicDomain
import UMusicLearning

public struct LocalDiagnosticsProvider: DiagnosticsProviding {
    private let buildIdentifier: String
    public init(buildIdentifier: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "development") {
        self.buildIdentifier = buildIdentifier
    }
    public func snapshot() async -> DiagnosticsSnapshot {
        let model = try? UMusicResources.rankerFeatureManifest()
        var issues: [DiagnosticIssue] = []
        if model?.modelVersion == "uninstalled" { issues.append(.init(code: "MODEL_NOT_INSTALLED", metadata: ["fallback": "heuristic"])) }
        return DiagnosticsSnapshot(
            frameworkVersion: UMusicCoreVersion.current,
            schemaVersion: ResearchPackageWriter.schemaVersion,
            buildIdentifier: buildIdentifier,
            modelVersion: model?.modelVersion ?? "unavailable",
            featureSchemaVersion: model?.featureVersion ?? "unavailable",
            issues: issues
        )
    }
}
