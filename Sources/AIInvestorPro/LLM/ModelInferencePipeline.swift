// MARK: - Model Inference Pipeline
import Foundation

public enum ModelType: String, CaseIterable {
    case linearRegression = "linear_regression"
    case randomForest = "random_forest"
    case neuralNetwork = "neural_network"
    case xgBoost = "xgboost"
    case timeSeries = "time_series"
    
    public var description: String {
        rawValue.replacingUnderscoresWithSpaces()
    }
}

public enum PredictionType: String, CaseIterable {
    case priceDirection = "price_direction"   // Up/Down
    case priceValue = "price_value"         // Specific price
    case volatility = "volatility"          // Expected volatility
    case regime = "regime"                  // Market regime
    case risk = "risk"                      // Risk metric
    
    public var description: String {
        rawValue.replacingUnderscoresWithSpaces()
    }
}

public struct ModelPrediction: Equatable {
    public let modelType: ModelType
    public let predictionType: PredictionType
    public let predictedValue: Double
    public let confidence: Double // 0.0 - 1.0
    public let predictionInterval: ClosedRange<Double> // Lower and upper bound
    public let featuresUsed: [String]
    public let modelVersion: String
    public let timestamp: Date
    
    public static func == (lhs: ModelPrediction, rhs: ModelPrediction) -> Bool {
        lhs.modelType == rhs.modelType && lhs.predictedValue == rhs.predictedValue && lhs.confidence == rhs.confidence
    }
    
    var description: String {
        "\(modelType.rawValue) → \(predictionType.rawValue): \(String(format: "%.4f", predictedValue)) ± \(String(format: "%.2f", confidenceInterval.lowerBound))-\(String(format: "%.2f", confidenceInterval.upperBound)) (\(String(format: "%.1f%", confidence * 100))% conf)"
    }
}

public final class ModelInferencePipeline {
    private let featureEngineer: FeatureEngineer
    private let featureNames: [String]
    private var modelWeights: [Double]?
    private var modelBias: Double?
    private var isTrained = false
    
    public init(featureEngineer: FeatureEngineer? = nil) {
        self.featureEngineer = featureEngineer ?? FeatureEngineer()
        self.featureNames = featureEngineer?.featureNames() ?? FeatureType.allCases.map { $0.rawValue }
    }
    
    // Train simple linear model on provided data
    public func train(_ historicalPrices: [Double], _ targetReturns: [Double]) {
        guard historicalPrices.count == targetReturns.count && historicalPrices.count > 10 else {
            print("Insufficient data for training")
            return
        }
        
        // Simple linear regression: y = wx + b
        let n = Double(historicalPrices.count)
        let xMean = featureEngineer.featureArray().reduce(0, +) / n
        let yMean = targetReturns.reduce(0, +) / n
        
        // Calculate weights using simple formula
        var numerator = 0.0
        var denominator = 0.0
        
        for i in 0..<historicalPrices.count {
            let x = featureEngineer.featureArray()[i % featureEngineer.featureArray().count]
            let y = targetReturns[i]
            numerator += (x - xMean) * (y - yMean)
            denominator += pow(x - xMean, 2)
        }
        
        modelWeights = denominator > 0 ? numerator / denominator : 0
        modelBias = yMean - modelWeights! * xMean
        isTrained = true
    }
    
    // Make prediction using trained model
    public func predict(_ features: [Double]) -> ModelPrediction {
        guard isTrained, let weights = modelWeights, let bias = modelBias else {
            return ModelPrediction(
                modelType: .linearRegression,
                predictionType: .priceValue,
                predictedValue: 0,
                confidence: 0.0,
                predictionInterval: 0...0,
                featuresUsed: featureNames,
                modelVersion: "1.0.0",
                timestamp: Date()
            )
        }
        
        // Calculate prediction
        let prediction = zip(features, weights).reduce(0) { $0 + $1.0 * $1.1 } + bias
        let confidence = min(1.0, 0.5 + abs(prediction) * 0.1) // Simple confidence based on magnitude
        
        // Prediction interval: ± 1 standard deviation estimate
        let margin = 0.5 * abs(prediction) * 0.1
        let lower = prediction - margin
        let upper = prediction + margin
        
        return ModelPrediction(
            modelType: .linearRegression,
            predictionType: .priceValue,
            predictedValue: prediction,
            confidence: confidence,
            predictionInterval: lower...upper,
            featuresUsed: featureNames,
            modelVersion: "1.0.0",
            timestamp: Date()
        )
    }
    
    // Predict using multiple model types
    public func predictEnsemble(_ features: [Double], models: [ModelType] = [.linearRegression]) -> ModelPrediction {
        var predictions: [ModelPrediction] = []
        
        for modelType in models {
            let pred = predict(features)
            // Adjust confidence based on model type
            var adjustedPred = pred
            adjustedPred.predictedValue *= modelType == .linearRegression ? 1.0 : 0.9
            adjustedPred.confidence *= modelType == .linearRegression ? 1.0 : 0.8
            predictions.append(adjustedPred)
        }
        
        // Average predictions
        if !predictions.isEmpty {
            let avgPrediction = predictions.map { $0.predictedValue }.reduce(0, +) / Double(predictions.count)
            let avgConfidence = predictions.map { $0.confidence }.reduce(0, +) / Double(predictions.count)
            let lower = predictions.map { $0.predictionInterval.lowerBound }.reduce(0, +) / Double(predictions.count)
            let upper = predictions.map { $0.predictionInterval.upperBound }.reduce(0, +) / Double(predictions.count)
            
            return ModelPrediction(
                modelType: .linearRegression, // Use first model as wrapper
                predictionType: .priceValue,
                predictedValue: avgPrediction,
                confidence: avgConfidence,
                predictionInterval: lower...upper,
                featuresUsed: featureNames,
                modelVersion: "ensemble_1.0.0",
                timestamp: Date()
            )
        } else {
            return predict(features)
        }
    }
    
    // Get feature importance (simple based on weight magnitude)
    public func featureImportance() -> [String: Double] {
        guard let weights = modelWeights else { return [:] }
        
        var importance: [String: Double] = [:]
        for (i, name) in featureNames.enumerated() {
            importance[name] = abs(weights[i])
        }
        
        // Sort by importance descending
        return Dictionary(uniqueKeysWithValues: importance.sorted { $0.value > $1.value })
    }
}

// MARK: - Pipeline Registry
public final class InferenceRegistry: ObservableObject {
    @Published public var lastPrediction: ModelPrediction?
    @Published public var modelInfo: String = "No model loaded"
    @Published public var isModelTrained = false
    
    private var pipeline: ModelInferencePipeline?
    
    public func setPipeline(_ pipeline: ModelInferencePipeline) {
        self.pipeline = pipeline
        isModelTrained = pipeline.isTrained
        modelInfo = "Model: \(pipeline.modelType.rawValue) - \(pipeline.featureEngineer.featureArray().count) features"
    }
    
    public func trainOnData(_ prices: [Double], _ targets: [Double]) {
        pipeline?.train(prices, targets)
        isModelTrained = pipeline!.isTrained
        modelInfo = "Trained on \(prices.count) data points"
    }
    
    public func predictCurrent(prices: [Double], featureEngineer: FeatureEngineer) {
        let engineer = FeatureEngineer(prices: prices)
        let features = engineer.featureArray()
        let prediction = pipeline?.predict(features)
        
        lastPrediction = prediction
        modelInfo = "Current prediction: \(String(format: "%.2f", prediction?.predictedValue ?? 0)) (\(String(format: "%.1f%", prediction?.confidence ?? 0) * 100))% conf"
    }
}
