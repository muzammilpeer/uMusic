#if canImport(CoreML)
import CoreML
import Foundation

public actor CoreMLModelScorer: ModelBatchScoring {
    private let model: MLModel
    private let outputName: String
    public init(compiledModelURL: URL, outputName: String = "score", computeUnits: MLComputeUnits = .cpuAndNeuralEngine) throws {
        let configuration = MLModelConfiguration(); configuration.computeUnits = computeUnits
        model = try MLModel(contentsOf: compiledModelURL, configuration: configuration); self.outputName = outputName
    }
    public func scores(for batch: [[Double]], orderedFeatures: [String]) async throws -> [Double] {
        try batch.map { row in
            let values = Dictionary(uniqueKeysWithValues: zip(orderedFeatures, row).map { ($0.0, MLFeatureValue(double: $0.1)) })
            let output = try model.prediction(from: MLDictionaryFeatureProvider(dictionary: values))
            guard let feature = output.featureValue(for: outputName), feature.type == .double else { throw ModelRankerError.invalidOutput }
            return feature.doubleValue
        }
    }
}
#endif
