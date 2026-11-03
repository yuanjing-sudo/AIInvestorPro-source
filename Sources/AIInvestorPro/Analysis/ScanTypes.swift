// MARK: - Scan Types
import Foundation

public struct SymbolScan: Equatable {
    public let symbol: String
    public var forecast: Forecast
    public var composite: Double
    public var recommendation: Recommendation
    public var reasons: [String]
    public var detectedAt: Date
    
    public static func == (lhs: SymbolScan, rhs: SymbolScan) -> Bool {
        lhs.symbol == rhs.symbol && lhs.composite == rhs.composite
    }
}

public struct Forecast {
    public let predictedReturn: Double
    public let predictedPrice: Double
    public let horizonBars: Int
    
    public init(predictedReturn: Double, predictedPrice: Double, horizonBars: Int) {
        self.predictedReturn = predictedReturn
        self.predictedPrice = predictedPrice
        self.horizonBars = horizonBars
    }
}

public enum Recommendation: String, CaseIterable {
    case buy
    case sell
    case hold
    
    var description: String {
        rawValue.capitalized
    }
}
