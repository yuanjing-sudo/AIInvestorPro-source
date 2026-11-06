// MARK: - Model Inference Pipeline
import Foundation
import Combine

public enum ModelType: String, CaseIterable, Sendable, Equatable {
    case linearRegression = "linear_regression"
    case randomForest = "random_forest"
    case neuralNetwork = "neural_network"
    case xgBoost = "xgboost"
    case timeSeries = "time_series"

    public var description: String {
        rawValue.replacingUnderscoresWithSpaces
    }
}

public enum PredictionType: String, CaseIterable, Sendable, Equatable {
    case priceDirection = "price_direction"
    case priceValue = "price_value"
    case volatility = "volatility"
    case regime = "regime"
    case risk = "risk"

    public var description: String {
        rawValue.replacingUnderscoresWithSpaces
    }
}

public struct ModelPrediction: Equatable, Sendable {
    public let modelType: ModelType
    public let predictionType: PredictionType
    public var predictedValue: Double
    public var confidence: Double
    public let predictionInterval: ClosedRange<Double>
    public let featuresUsed: [String]
    public let modelVersion: String
    public let timestamp: Date

    public init(
        modelType: ModelType,
        predictionType: PredictionType,
        predictedValue: Double,
        confidence: Double,
        predictionInterval: ClosedRange<Double>,
        featuresUsed: [String],
        modelVersion: String,
        timestamp: Date = Date()
    ) {
        self.modelType = modelType
        self.predictionType = predictionType
        self.predictedValue = predictedValue
        self.confidence = confidence
        self.predictionInterval = predictionInterval
        self.featuresUsed = featuresUsed
        self.modelVersion = modelVersion
        self.timestamp = timestamp
    }

    public static func == (lhs: ModelPrediction, rhs: ModelPrediction) -> Bool {
        lhs.modelType == rhs.modelType &&
        lhs.predictedValue == rhs.predictedValue &&
        lhs.confidence == rhs.confidence
    }

    var description: String {
        "\(modelType.rawValue) → \(predictionType.rawValue): \(String(format: "%.4f", predictedValue)) ± \(String(format: "%.2f", predictionInterval.lowerBound))-\(String(format: "%.2f", predictionInterval.upperBound)) (\(String(format: "%.1f", confidence * 100))% conf)"
    }
}

public final class ModelInferencePipeline {
    public let modelType: ModelType = .linearRegression
    public let featureEngineer: FeatureEngineer
    public let featureNames: [String]
    private var modelWeights: [Double]?
    private var modelBias: Double?
    public private(set) var isTrained = false

    public init(featureEngineer: FeatureEngineer? = nil) {
        let engineer = featureEngineer ?? FeatureEngineer(prices: [100, 101, 102])
        self.featureEngineer = engineer
        self.featureNames = engineer.featureNames()
    }

    /// Train a simple multivariate linear model. Features are generated from
    /// rolling price windows; coefficients are univariate covariances, which is
    /// a fast, deterministic baseline rather than a full least-squares fit.
    public func train(_ historicalPrices: [Double], _ targetReturns: [Double]) {
        let minimumHistory = 25
        guard historicalPrices.count == targetReturns.count,
              historicalPrices.count > minimumHistory else {
            return
        }

        let start = minimumHistory
        let featureCount = featureNames.count
        guard featureCount > 0 else { return }

        var rows: [[Double]] = []
        var targets: [Double] = []
        for index in start..<historicalPrices.count {
            let prefix = Array(historicalPrices[0...index])
            let engineer = FeatureEngineer(prices: prefix)
            rows.append(engineer.featureArray())
            targets.append(targetReturns[index])
        }
        guard !rows.isEmpty else { return }

        var means = Array(repeating: 0.0, count: featureCount)
        var targetMean = targets.mean
        for row in rows {
            for index in 0..<featureCount {
                means[index] += row[index]
            }
        }
        for index in 0..<featureCount {
            means[index] /= Double(rows.count)
        }

        var weights = Array(repeating: 0.0, count: featureCount)
        for index in 0..<featureCount {
            var covariance = 0.0
            var variance = 0.0
            for rowIndex in rows.indices {
                let x = rows[rowIndex][index] - means[index]
                covariance += x * (targets[rowIndex] - targetMean)
                variance += x * x
            }
            weights[index] = variance > 0 ? covariance / variance : 0
        }

        let bias = targetMean - zip(weights, means).reduce(0) { $0 + $1.0 * $1.1 }
        modelWeights = weights
        modelBias = bias
        isTrained = true
    }

    public func predict(_ features: [Double]) -> ModelPrediction {
        guard isTrained,
              let weights = modelWeights,
              let bias = modelBias,
              features.count == weights.count else {
            return ModelPrediction(
                modelType: .linearRegression,
                predictionType: .priceValue,
                predictedValue: 0,
                confidence: 0,
                predictionInterval: 0...0,
                featuresUsed: featureNames,
                modelVersion: "1.0.0"
            )
        }

        let prediction = zip(features, weights).reduce(0) { $0 + $1.0 * $1.1 } + bias
        let confidence = min(1.0, 0.5 + abs(prediction) * 0.1)
        let margin = max(0, abs(prediction) * 0.05)
        return ModelPrediction(
            modelType: .linearRegression,
            predictionType: .priceValue,
            predictedValue: prediction,
            confidence: confidence,
            predictionInterval: (prediction - margin)...(prediction + margin),
            featuresUsed: featureNames,
            modelVersion: "1.0.0"
        )
    }

    public func predictEnsemble(_ features: [Double], models: [ModelType] = [.linearRegression]) -> ModelPrediction {
        let predictions = models.map { modelType -> ModelPrediction in
            var prediction = predict(features)
            if modelType != .linearRegression {
                prediction.predictedValue *= 0.9
                prediction.confidence *= 0.8
            }
            return prediction
        }
        guard !predictions.isEmpty else { return predict(features) }

        let count = Double(predictions.count)
        let averagePrediction = predictions.map(\.predictedValue).reduce(0, +) / count
        let averageConfidence = predictions.map(\.confidence).reduce(0, +) / count
        let lower = predictions.map(\.predictionInterval.lowerBound).reduce(0, +) / count
        let upper = predictions.map(\.predictionInterval.upperBound).reduce(0, +) / count
        return ModelPrediction(
            modelType: models.first ?? .linearRegression,
            predictionType: .priceValue,
            predictedValue: averagePrediction,
            confidence: averageConfidence,
            predictionInterval: min(lower, upper)...max(lower, upper),
            featuresUsed: featureNames,
            modelVersion: "ensemble_1.0.0"
        )
    }

    public func featureImportance() -> [String: Double] {
        guard let weights = modelWeights else { return [:] }
        var importance: [String: Double] = [:]
        for (index, name) in featureNames.enumerated() where index < weights.count {
            importance[name] = abs(weights[index])
        }
        return Dictionary(uniqueKeysWithValues: importance.sorted { $0.value > $1.value })
    }
}

// MARK: - Pipeline Registry
public final class InferenceRegistry: ObservableObject {
    @Published public var lastPrediction: ModelPrediction?
    @Published public var modelInfo: String = "No model loaded"
    @Published public var isModelTrained = false

    private var pipeline: ModelInferencePipeline?

    public init() {}

    public func setPipeline(_ pipeline: ModelInferencePipeline) {
        self.pipeline = pipeline
        isModelTrained = pipeline.isTrained
        modelInfo = "Model: \(pipeline.modelType.rawValue) - \(pipeline.featureEngineer.featureArray().count) features"
    }

    public func trainOnData(_ prices: [Double], _ targets: [Double]) {
        pipeline?.train(prices, targets)
        isModelTrained = pipeline?.isTrained ?? false
        modelInfo = "Trained on \(prices.count) data points"
    }

    public func predictCurrent(prices: [Double], featureEngineer: FeatureEngineer) {
        _ = featureEngineer
        let engineer = FeatureEngineer(prices: prices)
        let features = engineer.featureArray()
        let prediction = pipeline?.predict(features)
        lastPrediction = prediction
        modelInfo = "Current prediction: \(String(format: "%.2f", prediction?.predictedValue ?? 0)) (\(String(format: "%.1f", (prediction?.confidence ?? 0) * 100))% conf)"
    }
}
