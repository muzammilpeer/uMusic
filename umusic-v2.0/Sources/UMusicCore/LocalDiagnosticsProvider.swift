import Foundation
import UMusicDomain
import UMusicLearning
import UMusicML

public struct LocalDiagnosticsProvider: DiagnosticsProviding {
    private let buildIdentifier: String
    private let modelRanker: ModelRankerLifecycle?
    private let modelLoadIssue: String?
    public init(buildIdentifier: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "development", modelRanker: ModelRankerLifecycle? = nil, modelLoadIssue: String? = nil) {
        self.buildIdentifier = buildIdentifier
        self.modelRanker = modelRanker
        self.modelLoadIssue = modelLoadIssue
    }
    public func snapshot() async -> DiagnosticsSnapshot {
        let model = try? UMusicResources.rankerFeatureManifest()
        var issues: [DiagnosticIssue] = []
        if model?.modelVersion == "uninstalled" { issues.append(.init(code: "MODEL_NOT_INSTALLED", metadata: ["fallback": "heuristic"])) }
        if let modelLoadIssue { issues.append(.init(code: modelLoadIssue, metadata: ["fallback": "heuristic"])) }
        if let evaluation = await modelRanker?.evaluationSnapshot() {
            issues.append(.init(code: evaluation.mode == .shadow ? "MODEL_SHADOW_MODE" : "MODEL_\(evaluation.mode.rawValue.uppercased())", metadata: [
                "attempts": String(evaluation.attempts),
                "failures": String(evaluation.failures),
                "successes": String(evaluation.successes),
                "timeouts": String(evaluation.timeouts),
            ]))
        }
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
