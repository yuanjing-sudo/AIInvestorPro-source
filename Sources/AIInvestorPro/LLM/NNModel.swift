// MARK: - Neural Network Models
import Foundation
import Combine

public enum NeuralNetworkType: String, CaseIterable {
    case pricePrediction = "price_prediction"
    case technicalPattern = "technical_pattern"
    case regimeClassification = "regime_classification"
    case sentimentAnalysis = "sentiment_analysis"
    
    public var description: String {
        rawValue.replacingUnderscoresWithSpaces
    }
}

// MARK: - Model Layers Description
public struct ModelLayer {
    public let type: String
    public let size: Int
    public let activation: String
    public let dropout: Double
    
    public init(type: String, size: Int, activation: String = "relu", dropout: Double = 0.0) {
        self.type = type
        self.size = size
        self.activation = activation
        self.dropout = dropout
    }
}

public struct ModelConfiguration {
    public let inputSize: Int
    public let hiddenLayers: [Int]
    public let outputSize: Int
    public let learningRate: Double
    public let batchSize: Int
    public let epochs: Int
    
    public init(
        inputSize: Int,
        hiddenLayers: [Int] = [],
        outputSize: Int = 1,
        learningRate: Double = 0.001,
        batchSize: Int = 32,
        epochs: Int = 100
    ) {
        self.inputSize = inputSize
        self.hiddenLayers = hiddenLayers
        self.outputSize = outputSize
        self.learningRate = learningRate
        self.batchSize = batchSize
        self.epochs = epochs
    }
}

// MARK: - Neural Network Model Base
public protocol NeuralNetworkModel: AnyObject {
    var configuration: ModelConfiguration { get }
    func forward(_ input: Any) throws -> Any
    func train(_ data: [Any], _ targets: [Any]) throws
    func predict(_ input: Any) throws -> Any
    func save(to path: String) throws
    func load(from path: String) throws
}

// MARK: - Model Registry
public final class ModelRegistry: ObservableObject {
    @Published public var availableTypes: [NeuralNetworkType] = []
    @Published public var loadedModel: NeuralNetworkType?
    @Published public var modelInfo: String = "No model loaded"
    
    public init() {
        availableTypes = [
            .pricePrediction,
            .technicalPattern,
            .regimeClassification,
            .sentimentAnalysis
        ]
    }
    
    public func load(_ type: NeuralNetworkType) {
        loadedModel = type
        switch type {
        case .pricePrediction:
            modelInfo = "Price Prediction Model - input: 60 days, output: next price"
        case .technicalPattern:
            modelInfo = "Technical Pattern Model - detects chart patterns"
        case .regimeClassification:
            modelInfo = "Regime Classification Model - 5 market regimes"
        case .sentimentAnalysis:
            modelInfo = "Sentiment Analysis Model - news/social media analysis"
        }
    }
}
