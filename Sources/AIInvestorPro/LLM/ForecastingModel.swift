// MARK: - Time Series Forecasting
import Foundation
import Combine

public enum ForecastHorizon: String, CaseIterable, Identifiable, Sendable, Equatable {
    case shortTerm = "short"   // 1-5 days
    case mediumTerm = "medium" // 6-20 days
    case longTerm = "long"     // 21-60 days
    case veryLongTerm = "very_long" // 60+ days

    public var id: String { rawValue }

    public var description: String {
        rawValue.capitalized
    }
}

public struct PricePoint: Identifiable {
    public let id: String
    public let date: Date
    public let price: Double
    public let volume: Double?
    
    public init(date: Date, price: Double, volume: Double? = nil) {
        self.id = UUID().uuidString
        self.date = date
        self.price = price
        self.volume = volume
    }
}

public struct ForecastResult: Equatable {
    public let horizon: ForecastHorizon
    public let predictedPrices: [Double]
    public let confidenceIntervals: [Date: Double] // date -> width
    public let modelName: String
    public let mse: Double? // Mean Squared Error if available
    public let lastUpdated: Date
    
    public static func == (lhs: ForecastResult, rhs: ForecastResult) -> Bool {
        lhs.horizon == rhs.horizon && lhs.modelName == rhs.modelName
    }
    
    var averagePredictedPrice: Double {
        predictedPrices.isEmpty ? 0 : predictedPrices.reduce(0, +) / Double(predictedPrices.count)
    }
    
    var trendDirection: String {
        guard predictedPrices.count >= 2,
              let first = predictedPrices.first,
              let last = predictedPrices.last,
              first != 0 else { return "unknown" }
        let change = (last - first) / abs(first) * 100
        return change > 0 ? "bullish" : change < 0 ? "bearish" : "sideways"
    }
}

// MARK: - Forecasting Model Protocol
public protocol ForecastingModel: AnyObject {
    /// Train the model on historical data
    /// - Parameter prices: Historical closing prices
    /// -param horizons: Forecast horizons to train for
    func train(_ prices: [Double], forHorizons horizons: [ForecastHorizon]) throws
    
    /// Generate price forecast
    /// - Parameter lastPrices: Most recent prices (typically last 60-100 days)
    /// -Parameter horizon: How far to forecast
    /// -Returns: Forecast result with predictions and confidence
    func forecast(_ lastPrices: [Double], horizon: ForecastHorizon) throws -> ForecastResult
    
    /// Get model name/identifier
    var modelIdentifier: String { get }
}

// MARK: - Naive Forecast Model
public class NaiveForecastModel: ForecastingModel {
    public let modelIdentifier = "naive"
    
    public init() {}
    
    public func train(_ prices: [Double], forHorizons horizons: [ForecastHorizon] = [.shortTerm, .mediumTerm, .longTerm]) throws {
        // Naive model needs no training - just validates data
        guard prices.count >= 20 else {
            throw ForecastError.insufficientData
        }
    }
    
    public func forecast(_ lastPrices: [Double], horizon: ForecastHorizon) throws -> ForecastResult {
        guard !lastPrices.isEmpty else {
            throw ForecastError.noData
        }
        
        let count: Int
        
        switch horizon {
        case .shortTerm: count = 5
        case .mediumTerm: count = 15
        case .longTerm: count = 30
        case .veryLongTerm: count = 60
        }
        
        // Naive forecast: repeat the last price.
        guard let predicted = lastPrices.last else { throw ForecastError.noData }
        let predictions = Array(repeating: predicted, count: count)
        
        // confidence widens over time
        var confidenceBands: [Date: Double] = [:]
        for i in 0..<count {
            let dateOffset = Double(i + 1)
            confidenceBands[Date().addingTimeInterval(dateOffset * 86400)] = dateOffset * 2.0 // $2 per day
        }
        
        return ForecastResult(
            horizon: horizon,
            predictedPrices: predictions,
            confidenceIntervals: confidenceBands,
            modelName: modelIdentifier,
            mse: nil,
            lastUpdated: Date()
        )
    }
}

// MARK: - Moving Average Forecast Model
public class MovingAverageForecastModel: ForecastingModel {
    public let modelIdentifier = "moving_average"
    
    private var windowSize: Int = 20
    
    public init(windowSize: Int = 20) {
        self.windowSize = max(1, windowSize)
    }
    
    public func train(_ prices: [Double], forHorizons horizons: [ForecastHorizon] = [.shortTerm, .mediumTerm, .longTerm]) throws {
        guard prices.count >= self.windowSize else {
            throw ForecastError.insufficientData
        }
    }
    
    public func forecast(_ lastPrices: [Double], horizon: ForecastHorizon) throws -> ForecastResult {
        guard !lastPrices.isEmpty, lastPrices.count >= self.windowSize else {
            throw ForecastError.noData
        }
        
        let count: Int
        switch horizon {
        case .shortTerm: count = 5
        case .mediumTerm: count = 15
        case .longTerm: count = 30
        case .veryLongTerm: count = 60
        }
        
        // Calculate moving average of last windowSize prices
        let startIndex = max(0, lastPrices.count - self.windowSize)
        let window = Array(lastPrices[startIndex...])
        let ma = window.reduce(0, +) / Double(window.count)
        
        // Simple forecast: persist the moving average.
        let predictions = Array(repeating: ma, count: count)
        
        // Confidence decreases slightly
        var confidenceBands: [Date: Double] = [:]
        for i in 0..<count {
            let dateOffset = Double(i + 1)
            confidenceBands[Date().addingTimeInterval(dateOffset * 86400)] = dateOffset * 1.5
        }
        
        return ForecastResult(
            horizon: horizon,
            predictedPrices: predictions,
            confidenceIntervals: confidenceBands,
            modelName: modelIdentifier,
            mse: nil,
            lastUpdated: Date()
        )
    }
}

// MARK: - Forecast Error
public enum ForecastError: Error {
    case insufficientData
    case noData
    case modelNotTrained
}

// MARK: - Model Registry
public final class ForecastModelRegistry: ObservableObject {
    @Published public var availableModels: [String] = []
    @Published public var loadedModel: String?
    @Published public var modelPerformance: [String: Double] = [:]
    
    public init() {
        availableModels = [
            "naive",
            "moving_average"
        ]
    }
    
    public func loadModel(_ identifier: String) {
        loadedModel = identifier
    }
    
    public func recordPerformance(_ identifier: String, _ score: Double) {
        modelPerformance[identifier] = score
    }
}
